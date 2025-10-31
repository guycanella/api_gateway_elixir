defmodule GatewayIntegrations.CircuitBreakerViaCepIntegrationTest do
  use ExUnit.Case, async: true

  alias GatewayIntegrations.{ViaCep, CircuitBreaker}
  alias GatewayDb.{Repo, Integration, CircuitBreakers}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

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

    %{integration_id: integration.id}
  end

  defp simulate_failure(integration_id) do
    CircuitBreaker.record_failure(integration_id, "Simulated failure")
  end

  defp make_success do
    {:ok, _} = ViaCep.get_address("01001000")
  end

  describe "circuit breaker opens after consecutive failures" do
    test "circuit opens after 5 failed requests", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..4, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 4

      simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
      assert state.failure_count == 5
      assert state.opened_at != nil
      assert state.next_retry_at != nil
    end

    test "opened_at timestamp is set when circuit opens", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..5, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
      assert state.opened_at != nil

      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(now, state.opened_at, :second)
      assert diff_seconds >= 0 and diff_seconds < 5
    end

    test "next_retry_at is set 60 seconds in the future", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      now = DateTime.utc_now()

      for _ <- 1..5, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)

      assert state.state == "open"
      assert state.next_retry_at != nil

      diff_seconds = DateTime.diff(state.next_retry_at, now, :second)
      assert diff_seconds >= 55 and diff_seconds <= 65
    end
  end

  describe "circuit breaker blocks requests when open" do
    test "requests are blocked when circuit is open", %{integration_id: integration_id} do
      next_retry = DateTime.add(DateTime.utc_now(), 60, :second)
      CircuitBreakers.open_circuit(integration_id, next_retry)

      result = ViaCep.get_address("01001000")

      assert result == {:error, :circuit_breaker_open}
    end

    test "failure count does not increase when circuit is open", %{integration_id: integration_id} do
      next_retry = DateTime.add(DateTime.utc_now(), 60, :second)
      CircuitBreakers.open_circuit(integration_id, next_retry)

      {:ok, state_before} = CircuitBreakers.get_state(integration_id)
      initial_failure_count = state_before.failure_count

      for _ <- 1..3 do
        {:error, :circuit_breaker_open} = ViaCep.get_address("01001000")
      end

      {:ok, state_after} = CircuitBreakers.get_state(integration_id)

      assert state_after.failure_count == initial_failure_count
    end
  end

  describe "circuit breaker recovery (half-open state)" do
    test "circuit transitions to half_open after timeout", %{integration_id: integration_id} do
      past_time = DateTime.add(DateTime.utc_now(), -1, :second)
      CircuitBreakers.open_circuit(integration_id, past_time)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"

      assert :allow = CircuitBreaker.check_request(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "half_open"
    end

    test "successful request in half_open closes the circuit", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "half_open")

      make_success()

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "failed request in half_open reopens the circuit", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "half_open")

      simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
      assert state.next_retry_at != nil
    end
  end

  describe "circuit breaker resets on success" do
    test "successful request resets failure count", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..3, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.failure_count == 3

      make_success()

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.failure_count == 0
      assert state.state == "closed"
    end

    test "circuit stays closed after multiple successful requests", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..10, do: make_success()

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end
  end

  describe "mixed success and failure scenarios" do
    test "alternating success and failure keeps circuit closed", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..3 do
        simulate_failure(integration_id)
        make_success()
      end

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "4 failures + success + 5 failures opens circuit", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..4, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.failure_count == 4

      make_success()

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.failure_count == 0

      for _ <- 1..5, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
    end
  end

  describe "state persistence" do
    test "circuit breaker state persists across function calls", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..3, do: simulate_failure(integration_id)

      {:ok, state1} = CircuitBreakers.get_state(integration_id)
      assert state1.failure_count == 3

      for _ <- 1..2, do: simulate_failure(integration_id)

      {:ok, state2} = CircuitBreakers.get_state(integration_id)
      assert state2.failure_count == 5
      assert state2.state == "open"
    end

    test "opened_at and next_retry_at persist in database", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..5, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)

      assert state.state == "open"
      assert state.opened_at != nil
      assert state.next_retry_at != nil

      {:ok, reloaded_state} = CircuitBreakers.get_state(integration_id)
      assert reloaded_state.opened_at == state.opened_at
      assert reloaded_state.next_retry_at == state.next_retry_at
    end
  end

  describe "manual circuit breaker operations" do
    test "manually opening circuit blocks requests", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      {:ok, _state} = CircuitBreaker.open(integration_id)

      assert {:error, :circuit_breaker_open} = ViaCep.get_address("01001000")
    end

    test "manually resetting circuit allows requests", %{integration_id: integration_id} do
      next_retry = DateTime.add(DateTime.utc_now(), 60, :second)
      CircuitBreakers.open_circuit(integration_id, next_retry)

      {:ok, _state} = CircuitBreaker.reset(integration_id)

      make_success()

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end
  end

  describe "complete lifecycle test" do
    test "full circuit breaker lifecycle: closed -> open -> half_open -> closed",
         %{integration_id: integration_id} do

      CircuitBreakers.create_state(integration_id, "closed")
      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"

      for _ <- 1..5, do: simulate_failure(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"

      assert {:error, :circuit_breaker_open} = ViaCep.get_address("01001000")

      CircuitBreakers.transition_to_half_open(integration_id)
      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "half_open"

      make_success()

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0

      {:ok, _address} = ViaCep.get_address("01310100")
      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
    end
  end
end
