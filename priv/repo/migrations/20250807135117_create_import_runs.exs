defmodule LifeOrg.Repo.Migrations.CreateImportRuns do
  use Ecto.Migration

  def change do
    create table(:import_runs) do
      add :integration_id, references(:integrations, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :items_imported, :integer, default: 0
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :log, :json

      timestamps(type: :utc_datetime)
    end

    create index(:import_runs, [:integration_id])
    create index(:import_runs, [:workspace_id])
    create index(:import_runs, [:status])
    create index(:import_runs, [:started_at])
  end
end
