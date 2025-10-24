defmodule GatewayDb.Repo.Migrations.CreateIntegrations do
  use Ecto.Migration

  def change do
    create table(:integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :base_url, :string, null: false
      add :is_active, :boolean, null: false, default: true
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:integrations, [:name])
    create index(:integrations, [:type])
    create index(:integrations, [:is_active])
  end
end
