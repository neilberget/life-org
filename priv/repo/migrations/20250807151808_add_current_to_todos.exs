defmodule LifeOrg.Repo.Migrations.AddCurrentToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :current, :boolean, default: false, null: false
    end
  end
end
