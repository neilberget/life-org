defmodule LifeOrg.Repo.Migrations.AddWorkspaceToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: true
    end

    create index(:conversations, [:workspace_id])
  end
end
