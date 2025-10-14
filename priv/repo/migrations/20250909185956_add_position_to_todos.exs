defmodule LifeOrg.Repo.Migrations.AddPositionToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :position, :integer, default: 0
    end

    create index(:todos, [:workspace_id, :position])
  end
end
