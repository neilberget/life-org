defmodule LifeOrg.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :description, :text
      add :color, :string, default: "#6B7280"
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:projects, [:workspace_id])
    create unique_index(:projects, [:workspace_id, :name])

    create table(:todo_projects, primary_key: false) do
      add :todo_id, references(:todos, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      
      timestamps()
    end

    create index(:todo_projects, [:todo_id])
    create index(:todo_projects, [:project_id])
    create unique_index(:todo_projects, [:todo_id, :project_id])
  end
end