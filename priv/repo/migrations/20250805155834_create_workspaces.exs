defmodule LifeOrg.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces) do
      add :name, :string, null: false
      add :description, :text
      add :color, :string, default: "#3B82F6"
      add :is_default, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspaces, [:name])
    create index(:workspaces, [:is_default])
  end
end
