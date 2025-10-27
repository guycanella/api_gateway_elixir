defmodule GatewayDb.RequestLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_methods ~w(GET POST PUT PATCH DELETE HEAD OPTIONS)

  @required_fields ~w(integration_id request_id method endpoint)a
  @optional_fields ~w(request_headers request_body response_status response_headers response_body duration_ms error_message)a

  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "request_logs" do
    belongs_to :integration, GatewayDb.Integration
    field :request_id, :string
    field :method, :string
    field :endpoint, :string
    # Be careful: do not log sensitive data here
    field :request_headers, :map, default: %{}
    field :request_body, :map, default: %{}
    field :response_status, :integer
    field :response_headers, :map, default: %{}
    field :response_body, :map, default: %{}
    field :duration_ms, :integer
    field :error_message, :string

    timestamps(@timestamps_opts)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:method, @valid_methods,
      message: "should be one of the following: #{Enum.join(@valid_methods, ", ")}")
    |> validate_http_status()
    |> validate_duration()
    |> validate_request_id_format()
    |> assoc_constraint(:integration,
      message: "integration not found")
  end

  def error_changeset(log, attrs) do
    log
    |> cast(attrs, @required_fields ++ [:error_message, :duration_ms])
    |> validate_required(@required_fields ++ [:error_message])
    |> validate_inclusion(:method, @valid_methods)
    |> validate_duration()
    |> validate_request_id_format()
    |> assoc_constraint(:integration)
  end


  defp validate_http_status(changeset) do
    validate_change(changeset, :response_status, fn :response_status, status ->
      if status && (status < 100 || status > 599) do
        [{:response_status, "should be a valid HTTP status code (100-599)"}]
      else
        []
      end
    end)
  end

  defp validate_duration(changeset) do
    validate_change(changeset, :duration_ms, fn :duration_ms, duration ->
      if duration && duration < 0 do
        [{:duration_ms, "should be a positive value"}]
      else
        []
      end
    end)
  end

  defp validate_request_id_format(changeset) do
    validate_change(changeset, :request_id, fn :request_id, request_id ->
      if String.trim(request_id) == "" do
        [{:request_id, "can't be blank"}]
      else
        []
      end
    end)
  end

  def success?(%__MODULE__{response_status: status}) when is_integer(status) do
    status >= 200 && status < 300
  end
  def success?(%__MODULE__{}), do: false

  def error?(%__MODULE__{error_message: msg}) when is_binary(msg), do: true
  def error?(%__MODULE__{response_status: status}) when is_integer(status) do
    status >= 400
  end
  def error?(%__MODULE__{}), do: false

  def classify_response(%__MODULE__{response_status: status}) when status >= 200 and status < 300, do: :success
  def classify_response(%__MODULE__{response_status: status}) when status >= 300 and status < 400, do: :redirect
  def classify_response(%__MODULE__{response_status: status}) when status >= 400 and status < 500, do: :client_error
  def classify_response(%__MODULE__{response_status: status}) when status >= 500 and status < 600, do: :server_error
  def classify_response(%__MODULE__{error_message: msg}) when is_binary(msg), do: :error
  def classify_response(%__MODULE__{}), do: :unknown

  def sanitize_sensitive_data(data) when is_map(data) do
    sensitive_keys = ["authorization", "password", "secret", "token", "api_key"]

    Enum.reduce(data, %{}, fn {key, value}, acc ->
      key_lower = String.downcase(to_string(key))

      if Enum.any?(sensitive_keys, &String.contains?(key_lower, &1)) do
        Map.put(acc, key, mask_value(value))
      else
        Map.put(acc, key, value)
      end
    end)
  end
  def sanitize_sensitive_data(data), do: data

  defp mask_value(value) when is_binary(value) do
    case String.length(value) do
      len when len <= 4 -> "***"
      _len -> String.slice(value, 0, 4) <> "***"
    end
  end
  defp mask_value(_), do: "***"
end
