defmodule GatewayDb.Repo.Migrations.CreateIntegrationCredentials do
  use Ecto.Migration

  def change do
    create table(:integration_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :integration_id, :binary_id, null: false
      add :environment, :string, null: false
      add :api_key, :binary, null: false
      add :api_secret, :binary
      add :extra_credentials, :map, default: %{}
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:integration_credentials, [:integration_id])
    create unique_index(:integration_credentials, [:integration_id, :environment])

    execute(
      """
      ALTER TABLE integration_credentials
      ADD CONSTRAINT integration_credentials_integration_id_fkey
      FOREIGN KEY (integration_id)
      REFERENCES integrations(id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE integration_credentials DROP CONSTRAINT integration_credentials_integration_id_fkey"
    )
  end
end
