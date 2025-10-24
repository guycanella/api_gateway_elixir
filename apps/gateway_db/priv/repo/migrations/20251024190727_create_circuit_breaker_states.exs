defmodule GatewayDb.Repo.Migrations.CreateCircuitBreakerStates do
  use Ecto.Migration

  def change do
    create table(:circuit_breaker_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :integration_id, :binary_id, null: false
      add :state, :string, null: false, default: "closed"
      add :failure_count, :integer, default: 0, null: false
      add :last_failure_at, :utc_datetime
      add :opened_at, :utc_datetime
      add :next_retry_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:circuit_breaker_states, [:integration_id])
    create index(:circuit_breaker_states, [:state])

    # Adicionar foreign key depois da tabela ser criada
    execute(
      """
      ALTER TABLE circuit_breaker_states
      ADD CONSTRAINT circuit_breaker_states_integration_id_fkey
      FOREIGN KEY (integration_id)
      REFERENCES integrations(id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE circuit_breaker_states DROP CONSTRAINT circuit_breaker_states_integration_id_fkey"
    )
  end
end
