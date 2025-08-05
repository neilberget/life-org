defmodule LifeOrg.Repo.Migrations.AddWorkspaceToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: true
    end

    create index(:todos, [:workspace_id])
  end
end
