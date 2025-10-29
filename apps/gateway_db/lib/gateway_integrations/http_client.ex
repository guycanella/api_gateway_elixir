defmodule GatewayIntegrations.HttpClient do
  require Logger
  alias GatewayDb.{Logs, Integrations}

  @type http_method :: :get | :post | :put | :patch | :delete
  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type body :: map() | String.t() | nil
  @type opts :: keyword()

  @type response :: %{
    status: integer(),
    body: map() | String.t(),
    headers: headers()
  }

  @type error_reason ::
    :timeout
    | :connection_refused
    | :invalid_response
    | {:http_error, integer()}
    | term()

  @spec get(url(), opts()) :: {:ok, response()} | {:error, error_reason()}
  def get(url, opts \\ []) do
    request(:get, url, nil, opts)
  end

  @spec post(url(), body(), opts()) :: {:ok, response()} | {:error, error_reason()}
  def post(url, body, opts \\ []) do
    request(:post, url, body, opts)
  end

  @spec put(url(), body(), opts()) :: {:ok, response()} | {:error, error_reason()}
  def put(url, body, opts \\ []) do
    request(:put, url, body, opts)
  end

  @spec patch(url(), body(), opts()) :: {:ok, response()} | {:error, error_reason()}
  def patch(url, body, opts \\ []) do
    request(:patch, url, body, opts)
  end

  @spec delete(url(), opts()) :: {:ok, response()} | {:error, error_reason()}
  def delete(url, opts \\ []) do
    request(:delete, url, nil, opts)
  end

  @spec request(http_method(), url(), body(), opts()) :: {:ok, response()} | {:error, error_reason()}
  defp request(method, url, body, opts) do
    request_id = generate_request_id()
    start_time = System.monotonic_time(:millisecond)

    headers = build_headers(opts)
    timeout = Keyword.get(opts, :timeout, 15_000)

    uri = URI.parse(url)
    endpoint = uri.path || "/"

    Logger.info("HTTP Request: #{method |> to_string() |> String.upcase()} #{url}",
      request_id: request_id,
      method: method,
      url: url
    )

    finch_request = build_finch_request(method, url, headers, body)

    result = Finch.request(finch_request, GatewayIntegrations.Finch, receive_timeout: timeout)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, %Finch.Response{status: status, body: response_body, headers: response_headers}} ->
        parsed_response = parse_response_body(response_body)

        Logger.info("HTTP Response: #{status}",
          request_id: request_id,
          status: status,
          duration_ms: duration
        )

        if integration_id = Keyword.get(opts, :integration_id) do
          log_request(integration_id, request_id, method, endpoint, headers, body,
                     status, response_headers, parsed_response, duration, nil)
        end

        response = %{
          status: status,
          body: parsed_response,
          headers: response_headers
        }

        if status >= 400 do
          {:error, {:http_error, status}}
        else
          {:ok, response}
        end

      {:error, %Mint.TransportError{reason: :timeout}} ->
        Logger.error("HTTP Request timeout",
          request_id: request_id,
          duration_ms: duration
        )

        if integration_id = Keyword.get(opts, :integration_id) do
          log_request(integration_id, request_id, method, endpoint, headers, body,
                     nil, [], %{}, duration, "Request timeout after #{timeout}ms")
        end

        {:error, :timeout}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        Logger.error("HTTP Connection refused",
          request_id: request_id,
          duration_ms: duration
        )

        if integration_id = Keyword.get(opts, :integration_id) do
          log_request(integration_id, request_id, method, endpoint, headers, body,
                     nil, [], %{}, duration, "Connection refused")
        end

        {:error, :connection_refused}

      {:error, reason} ->
        error_message = inspect(reason)

        Logger.error("HTTP Request failed: #{error_message}",
          request_id: request_id,
          duration_ms: duration
        )

        if integration_id = Keyword.get(opts, :integration_id) do
          log_request(integration_id, request_id, method, endpoint, headers, body,
                     nil, [], %{}, duration, error_message)
        end

        {:error, reason}
    end
  end

  defp build_finch_request(method, url, headers, nil) do
    Finch.build(method, url, headers)
  end

  defp build_finch_request(method, url, headers, body) when is_map(body) do
    json_body = Jason.encode!(body)
    Finch.build(method, url, headers, json_body)
  end

  defp build_finch_request(method, url, headers, body) when is_binary(body) do
    Finch.build(method, url, headers, body)
  end

  defp build_headers(opts) do
    custom_headers = Keyword.get(opts, :headers, [])

    default_headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "GatewayIntegrations/1.0"}
    ]

    Enum.uniq_by(custom_headers ++ default_headers, fn {key, _} -> String.downcase(key) end)
  end

  defp parse_response_body(""), do: %{}
  defp parse_response_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      {:error, _} -> body
    end
  end

  defp generate_request_id do
    "req_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp log_request(integration_id, request_id, method, endpoint, request_headers,
                   request_body, response_status, response_headers, response_body,
                   duration, error_message) do
    request_headers_map = headers_to_map(request_headers)
    response_headers_map = headers_to_map(response_headers)

    request_body_map = ensure_map(request_body)
    response_body_map = ensure_map(response_body)

    attrs = %{
      request_id: request_id,
      method: method |> to_string() |> String.upcase(),
      endpoint: endpoint,
      request_headers: request_headers_map,
      request_body: request_body_map,
      response_status: response_status,
      response_headers: response_headers_map,
      response_body: response_body_map,
      duration_ms: duration,
      error_message: error_message
    }

    case Integrations.get_integration(integration_id) do
      {:ok, integration} ->
        case Logs.create_log(Map.put(attrs, :integration_id, integration.id)) do
          {:ok, _log} -> :ok
          {:error, reason} ->
            Logger.warning("Failed to log request: #{inspect(reason)}")
        end

      {:error, _} ->
        Logger.warning("Integration not found for logging: #{integration_id}")
    end
  end

  defp headers_to_map(headers) when is_list(headers) do
    Enum.into(headers, %{})
  end

  defp ensure_map(nil), do: %{}
  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(value) when is_binary(value), do: %{"raw" => value}
  defp ensure_map(_), do: %{}
end
