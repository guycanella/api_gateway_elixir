defmodule GatewayIntegrations.ViaCep do
  alias GatewayIntegrations.HttpClient
  alias GatewayDb.Integrations

  @base_url "https://viacep.com.br/ws"

  @spec get_address(String.t(), keyword()) :: {:ok, map()} | {:error, atom() | term()}
  def get_address(cep, opts \\ []) do
    with {:ok, normalized_cep} <- normalize_cep(cep),
         {:ok, integration_id} <- get_integration_id(),
         {:ok, response} <- make_request(normalized_cep, integration_id, opts) do
      {:ok, normalize_response(response.body)}
    end
  end

  @spec search_address(String.t(), String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, atom() | term()}
  def search_address(state, city, street, opts \\ []) do
    with {:ok, params} <- validate_search_params(state, city, street),
         {:ok, integration_id} <- get_integration_id(),
         {:ok, response} <- make_search_request(params, integration_id, opts) do
      addresses =
        response.body
        |> List.wrap()
        |> Enum.map(&normalize_response/1)

      {:ok, addresses}
    end
  end

  defp normalize_cep(cep) when is_binary(cep) do
    clean_cep = String.replace(cep, ~r/[^0-9]/, "")

    case String.length(clean_cep) do
      8 -> {:ok, clean_cep}
      _ -> {:error, :invalid_cep}
    end
  end
  defp normalize_cep(_), do: {:error, :invalid_cep}

  defp validate_search_params(state, city, street) do
    cond do
      String.length(state) != 2 ->
        {:error, :invalid_params}

      String.length(city) < 3 ->
        {:error, :invalid_params}

      String.length(street) < 3 ->
        {:error, :invalid_params}

      true ->
        {:ok, %{state: state, city: city, street: street}}
    end
  end

  defp get_integration_id do
    case Integrations.get_integration_by_name("viacep") do
      {:ok, integration} -> {:ok, integration.id}
      {:error, :not_found} -> {:error, :integration_not_configured}
    end
  end

  defp make_request(cep, integration_id, opts) do
    url = "#{@base_url}/#{cep}/json/"

    request_opts = Keyword.merge(opts, [
      integration_id: integration_id,
      timeout: 5_000
    ])

    case HttpClient.get(url, request_opts) do
      {:ok, %{body: %{"erro" => true}}} ->
        {:error, :not_found}

      {:ok, response} ->
        {:ok, response}

      {:error, {:http_error, 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_search_request(%{state: state, city: city, street: street}, integration_id, opts) do
    encoded_city = URI.encode(city)
    encoded_street = URI.encode(street)

    url = "#{@base_url}/#{state}/#{encoded_city}/#{encoded_street}/json/"

    request_opts = Keyword.merge(opts, [
      integration_id: integration_id,
      timeout: 5_000
    ])

    case HttpClient.get(url, request_opts) do
      {:ok, %{body: body}} when body == [] or body == %{} ->
        {:error, :not_found}

      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response(raw_response) when is_map(raw_response) do
    %{
      cep: Map.get(raw_response, "cep"),
      street: Map.get(raw_response, "logradouro"),
      complement: Map.get(raw_response, "complemento"),
      neighborhood: Map.get(raw_response, "bairro"),
      city: Map.get(raw_response, "localidade"),
      state: Map.get(raw_response, "uf"),
      ibge_code: Map.get(raw_response, "ibge"),
      gia_code: Map.get(raw_response, "gia"),
      ddd: Map.get(raw_response, "ddd"),
      siafi_code: Map.get(raw_response, "siafi")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end
end
