defmodule GatewayDb.Repo.Migrations.CreateRequestLogs do
  use Ecto.Migration

  def change do
    create table(:request_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :integration_id, :binary_id, null: false
      add :request_id, :string, null: false
      add :method, :string, null: false
      add :endpoint, :string, null: false
      add :request_headers, :map, default: %{}
      add :request_body, :map, default: %{}
      add :response_status, :integer
      add :response_headers, :map, default: %{}
      add :response_body, :map, default: %{}
      add :duration_ms, :integer
      add :error_message, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:request_logs, [:integration_id])
    create index(:request_logs, [:request_id])
    create index(:request_logs, [:response_status])
    create index(:request_logs, [:inserted_at])

    execute(
      """
      ALTER TABLE request_logs
      ADD CONSTRAINT request_logs_integration_id_fkey
      FOREIGN KEY (integration_id)
      REFERENCES integrations(id)
      ON DELETE RESTRICT
      """,
      "ALTER TABLE request_logs DROP CONSTRAINT request_logs_integration_id_fkey"
    )
  end
end
