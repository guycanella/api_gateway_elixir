defmodule GatewayDb.Integration do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @valid_types ~w(payment email shipping notification sms other)
  @required_fields ~w(name type base_url)a
  @optional_fields ~w(is_active config)a

  schema "integrations" do
    field :name, :string
    field :type, :string
    field :base_url, :string
    field :is_active, :boolean, default: true
    field :config, :map, default: %{}

    has_many :credentials, GatewayDb.IntegrationCredential, foreign_key: :integration_id
    has_many :request_logs, GatewayDb.RequestLog, foreign_key: :integration_id
    has_many :circuit_breaker_states, GatewayDb.CircuitBreakerState, foreign_key: :integration_id

    timestamps(type: :utc_datetime)
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
    |> validate_inclusion(:type, @valid_types,
         message: "should be one of the following: #{Enum.join(@valid_types, ", ")}")
    |> validate_url(:base_url)
    |> validate_config()
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      url_regex = ~r/^https?:\/\/.+/

      if String.match?(url, url_regex) do
        []
      else
        [{field, "should be a valid URL (http:// or https://)"}]
      end
    end)
  end

  defp validate_config(changeset) do
    validate_change(changeset, :config, fn _, config ->
      if is_map(config) do
        []
      else
        [:config, "deve ser um mapa/objeto JSON válido"]
      end
    end)
  end
end
