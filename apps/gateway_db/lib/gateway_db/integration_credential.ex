defmodule GatewayDb.IntegrationCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_environments ~w(development staging production)

  @required_fields ~w(integration_id environment api_key)a
  @optional_fields ~w(api_secret extra_credentials expires_at)a

  schema "integration_credentials" do
    belongs_to :integration, GatewayDb.Integration
    field :environment, :string
    field :api_key, GatewayDb.Encrypted.Binary
    field :api_secret, GatewayDb.Encrypted.Binary
    field :extra_credentials, :map, default: %{}
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:environment, @valid_environments,
         message: "should be one of the following: #{Enum.join(@valid_environments, ", ")}")
    |> validate_length(:api_key, min: 1, message: "cannot be empty")
    |> validate_expiration_date()
    |> assoc_constraint(:integration,
         message: "integration not found")
    |> unique_constraint([:integration_id, :environment],
         name: :integration_credentials_integration_id_environment_index,
         message: "a credential already exists for this integration in this environment")
  end

  def update_credentials_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:api_key, :api_secret, :extra_credentials, :expires_at])
    |> validate_length(:api_key, min: 1, message: "cannot be empty")
    |> validate_expiration_date()
  end

  defp validate_expiration_date(changeset) do
    validate_change(changeset, :expires_at, fn _, expires_at ->
      if expires_at do
        now = DateTime.utc_now()

        if DateTime.compare(expires_at, now) == :gt do
          []
        else
          [:expires_at, "should be a future date"]
        end
      else
        []
      end
    end)
  end

  def expired?(%__MODULE__{expires_at: nil}), do: false
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  def environment_atom(%__MODULE__{environment: env}) when is_binary(env) do
    String.to_existing_atom(env)
  end
end
