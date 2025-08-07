defmodule LifeOrg.Repo.Migrations.CreateUserIntegrations do
  use Ecto.Migration

  def change do
    create table(:user_integrations) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :integration_id, references(:integrations, on_delete: :delete_all), null: false
      add :credentials, :text
      add :settings, :json
      add :last_sync_at, :utc_datetime
      add :status, :string, default: "active", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_integrations, [:workspace_id])
    create index(:user_integrations, [:integration_id])
    create index(:user_integrations, [:status])
    create unique_index(:user_integrations, [:workspace_id, :integration_id])
  end
end
