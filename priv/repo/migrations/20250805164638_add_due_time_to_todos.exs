defmodule LifeOrg.Repo.Migrations.AddDueTimeToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :due_time, :time
    end
  end
end
