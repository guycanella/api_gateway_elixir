defmodule GatewayIntegrations.OpenWeather do
  alias GatewayIntegrations.HttpClient
  alias GatewayDb.Integrations

  @base_url "https://api.openweathermap.org/data/2.5"

  @type weather_data :: %{
    temperature: float(),
    feels_like: float(),
    temp_min: float(),
    temp_max: float(),
    pressure: integer(),
    humidity: integer(),
    description: String.t(),
    icon: String.t(),
    wind_speed: float(),
    clouds: integer(),
    timestamp: DateTime.t()
  }

  @type forecast_item :: %{
    temperature: float(),
    description: String.t(),
    timestamp: DateTime.t()
  }

  @spec get_current_weather(String.t(), String.t() | nil, keyword()) ::
    {:ok, weather_data()} | {:error, atom() | term()}
  def get_current_weather(city, country_code \\ nil, opts \\ []) do
    with {:ok, query} <- build_location_query(city, country_code),
         {:ok, integration_id, api_key} <- get_credentials(),
         {:ok, response} <- make_weather_request(query, integration_id, api_key, opts) do
      {:ok, normalize_current_weather(response.body)}
    end
  end

  @spec get_forecast(String.t(), String.t() | nil, keyword()) ::
    {:ok, [forecast_item()]} | {:error, atom() | term()}
  def get_forecast(city, country_code \\ nil, opts \\ []) do
    with {:ok, query} <- build_location_query(city, country_code),
         {:ok, integration_id, api_key} <- get_credentials(),
         {:ok, response} <- make_forecast_request(query, integration_id, api_key, opts) do
      forecast_list = normalize_forecast(response.body)
      {:ok, forecast_list}
    end
  end

  # Private functions

  defp build_location_query(city, nil) when is_binary(city) and byte_size(city) > 0 do
    {:ok, city}
  end

  defp build_location_query(city, country_code)
      when is_binary(city) and byte_size(city) > 0 and
           is_binary(country_code) and byte_size(country_code) == 2 do
    {:ok, "#{city},#{country_code}"}
  end

  defp build_location_query(_city, _country_code) do
    {:error, :invalid_params}
  end

  defp get_credentials do
    case Integrations.get_integration_by_name("openweather") do
      {:ok, integration} ->
        case Integrations.get_credential(integration.id, "production") do
          {:ok, credentials} ->
            {:ok, integration.id, credentials.api_key}

          {:error, :not_found} ->
            {:error, :credentials_not_found}
        end

      {:error, :not_found} ->
        {:error, :integration_not_configured}
    end
  end

  defp make_weather_request(location_query, integration_id, api_key, opts) do
    url = "#{@base_url}/weather"

    params = %{
      q: location_query,
      appid: api_key,
      units: "metric",
      lang: "pt_br"
    }

    url_with_params = add_query_params(url, params)

    request_opts = Keyword.merge(opts, [
      integration_id: integration_id,
      timeout: 5_000
    ])

    case HttpClient.get(url_with_params, request_opts) do
      {:ok, %{body: %{"cod" => 404}}} ->
        {:error, :not_found}

      {:ok, %{body: %{"cod" => "404"}}} ->
        {:error, :not_found}

      {:ok, %{body: %{"cod" => 401}}} ->
        {:error, :invalid_api_key}

      {:ok, %{body: body}} when body == %{} or map_size(body) == 0 ->
        {:error, :empty_response}

      {:ok, response} ->
        {:ok, response}

      {:error, {:http_error, 404}} ->
        {:error, :not_found}

      {:error, {:http_error, 401}} ->
        {:error, :invalid_api_key}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_forecast_request(location_query, integration_id, api_key, opts) do
    url = "#{@base_url}/forecast"

    params = %{
      q: location_query,
      appid: api_key,
      units: "metric",
      lang: "pt_br"
    }

    url_with_params = add_query_params(url, params)

    request_opts = Keyword.merge(opts, [
      integration_id: integration_id,
      timeout: 5_000
    ])

    case HttpClient.get(url_with_params, request_opts) do
      {:ok, %{body: %{"cod" => "404"}}} ->
        {:error, :not_found}

      {:ok, %{body: %{"cod" => "401"}}} ->
        {:error, :invalid_api_key}

      {:ok, response} ->
        {:ok, response}

      {:error, {:http_error, 404}} ->
        {:error, :not_found}

      {:error, {:http_error, 401}} ->
        {:error, :invalid_api_key}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_query_params(url, params) do
    query_string =
      params
      |> Enum.map(fn {key, value} -> "#{key}=#{URI.encode_www_form(to_string(value))}" end)
      |> Enum.join("&")

    "#{url}?#{query_string}"
  end

  defp normalize_current_weather(raw_response) do
    main = Map.get(raw_response, "main", %{})
    weather = List.first(Map.get(raw_response, "weather", [%{}]))
    wind = Map.get(raw_response, "wind", %{})
    clouds = Map.get(raw_response, "clouds", %{})

    %{
      temperature: Map.get(main, "temp"),
      feels_like: Map.get(main, "feels_like"),
      temp_min: Map.get(main, "temp_min"),
      temp_max: Map.get(main, "temp_max"),
      pressure: Map.get(main, "pressure"),
      humidity: Map.get(main, "humidity"),
      description: Map.get(weather, "description"),
      icon: Map.get(weather, "icon"),
      wind_speed: Map.get(wind, "speed"),
      clouds: Map.get(clouds, "all"),
      timestamp: DateTime.utc_now()
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_forecast(raw_response) do
    raw_response
    |> Map.get("list", [])
    |> Enum.map(fn item ->
      main = Map.get(item, "main", %{})
      weather = List.first(Map.get(item, "weather", [%{}]))
      dt = Map.get(item, "dt")

      %{
        temperature: Map.get(main, "temp"),
        feels_like: Map.get(main, "feels_like"),
        humidity: Map.get(main, "humidity"),
        description: Map.get(weather, "description"),
        icon: Map.get(weather, "icon"),
        timestamp: datetime_from_unix(dt)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  defp datetime_from_unix(nil), do: nil
  defp datetime_from_unix(unix_timestamp) when is_integer(unix_timestamp) do
    DateTime.from_unix!(unix_timestamp)
  end
end
