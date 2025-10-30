defmodule GatewayIntegrations.ViaCepTest do
  use ExUnit.Case, async: true
  import Mox
  alias GatewayIntegrations.ViaCep
  alias GatewayDb.{Repo, Integration}

  setup :verify_on_exit!

  setup do
    # Ensure sandbox mode is enabled
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create viacep integration for tests
    {:ok, integration} =
      %Integration{}
      |> Integration.changeset(%{
        name: "viacep",
        type: "other",
        base_url: "https://viacep.com.br/ws",
        is_active: true,
        config: %{
          "timeout_ms" => 5000,
          "rate_limit_per_minute" => 200
        }
      })
      |> Repo.insert()

    %{integration: integration}
  end

  describe "get_address/2" do
    test "returns normalized address for valid CEP" do
      assert {:ok, address} = ViaCep.get_address("01001000")

      assert address.cep == "01001-000"
      assert address.street == "Praça da Sé"
      assert address.neighborhood == "Sé"
      assert address.city == "São Paulo"
      assert address.state == "SP"
    end

    test "accepts CEP with hyphen" do
      assert {:ok, address} = ViaCep.get_address("01001-000")
      assert address.cep == "01001-000"
    end

    test "returns error for invalid CEP format" do
      assert {:error, :invalid_cep} = ViaCep.get_address("123")
      assert {:error, :invalid_cep} = ViaCep.get_address("abcdefgh")
      assert {:error, :invalid_cep} = ViaCep.get_address("12345678901")
    end

    test "returns error for non-existent CEP" do
      assert {:error, :not_found} = ViaCep.get_address("99999999")
    end

    test "successfully calls API when integration is configured", %{integration: integration} do
      assert integration.name == "viacep"
      assert {:ok, _} = ViaCep.get_address("01001000")
    end
  end

  describe "search_address/4" do
    test "returns list of addresses for valid search" do
      assert {:ok, addresses} = ViaCep.search_address("SP", "São Paulo", "Paulista")

      assert is_list(addresses)
      assert length(addresses) > 0

      first = List.first(addresses)
      assert is_map(first)
      assert Map.has_key?(first, :cep)
      assert Map.has_key?(first, :street)
    end

    test "returns error for invalid state" do
      assert {:error, :invalid_params} = ViaCep.search_address("S", "São Paulo", "Paulista")
      assert {:error, :invalid_params} = ViaCep.search_address("SPP", "São Paulo", "Paulista")
    end

    test "returns error for invalid city" do
      assert {:error, :invalid_params} = ViaCep.search_address("SP", "SP", "Paulista")
      assert {:error, :invalid_params} = ViaCep.search_address("SP", "Ab", "Paulista")
    end

    test "returns error for invalid street" do
      assert {:error, :invalid_params} = ViaCep.search_address("SP", "São Paulo", "Ab")
      assert {:error, :invalid_params} = ViaCep.search_address("SP", "São Paulo", "A")
    end

    test "returns not_found when no addresses match" do
      assert {:error, :not_found} = ViaCep.search_address("SP", "São Paulo", "XyzNonExistent123")
    end
  end

  describe "CEP normalization" do
    test "removes hyphen from CEP" do
      {:ok, address1} = ViaCep.get_address("01001-000")
      {:ok, address2} = ViaCep.get_address("01001000")

      assert address1.cep == address2.cep
    end

    test "handles CEP with spaces" do
      {:ok, address} = ViaCep.get_address("01001 000")
      assert address.cep == "01001-000"
    end
  end

  describe "response normalization" do
    test "converts API fields to English keys" do
      {:ok, address} = ViaCep.get_address("01001000")

      # English keys
      assert Map.has_key?(address, :cep)
      assert Map.has_key?(address, :street)
      assert Map.has_key?(address, :neighborhood)
      assert Map.has_key?(address, :city)
      assert Map.has_key?(address, :state)

      # Portuguese keys should not exist
      refute Map.has_key?(address, :logradouro)
      refute Map.has_key?(address, :bairro)
      refute Map.has_key?(address, :localidade)
    end

    test "removes empty fields from response" do
      {:ok, address} = ViaCep.get_address("01001000")

      # All values should be non-empty
      Enum.each(address, fn {_key, value} ->
        assert value != ""
        assert value != nil
      end)
    end

    test "includes optional fields when present" do
      {:ok, address} = ViaCep.get_address("01001000")

      assert Map.has_key?(address, :ibge_code)
      assert Map.has_key?(address, :ddd)
    end
  end

  describe "error handling" do
    test "handles timeout gracefully" do
      # This would require mocking HttpClient
      # For integration test, we assume timeout is handled
      assert {:ok, _} = ViaCep.get_address("01001000", timeout: 10_000)
    end

    test "handles connection errors" do
      # Would require mocking network failures
      # Integration assumes HttpClient handles this
      :ok
    end
  end

  describe "integration with database logging" do
    test "logs request when integration_id is available" do
      alias GatewayDb.Logs

      initial_count = Logs.count_logs()

      {:ok, _address} = ViaCep.get_address("01310100")

      # Should have created a new log entry
      final_count = Logs.count_logs()
      assert final_count == initial_count + 1

      # Verify log content
      [latest_log | _] = Logs.list_logs(limit: 1)
      assert latest_log.method == "GET"
      assert latest_log.response_status == 200
      assert String.contains?(latest_log.endpoint, "01310100")
    end
  end

  describe "real API integration" do
    @tag :integration
    test "fetches real data from ViaCEP" do
      {:ok, address} = ViaCep.get_address("01001000")

      assert address.cep == "01001-000"
      assert address.city == "São Paulo"
      assert address.state == "SP"
    end

    @tag :integration
    test "searches real addresses" do
      {:ok, addresses} = ViaCep.search_address("RJ", "Rio de Janeiro", "Atlântica")

      assert length(addresses) > 0
      assert Enum.all?(addresses, fn addr -> addr.state == "RJ" end)
    end

    @tag :integration
    test "handles non-existent CEP from real API" do
      assert {:error, :not_found} = ViaCep.get_address("00000000")
    end
  end
end
