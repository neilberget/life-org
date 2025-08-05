defmodule LifeOrg.Repo.Migrations.AddWorkspaceToJournalEntries do
  use Ecto.Migration

  def change do
    alter table(:journal_entries) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: true
    end

    create index(:journal_entries, [:workspace_id])
  end
end
