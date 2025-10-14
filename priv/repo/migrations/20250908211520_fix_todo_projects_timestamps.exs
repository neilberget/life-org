defmodule LifeOrg.Repo.Migrations.FixTodoProjectsTimestamps do
  use Ecto.Migration

  def change do
    alter table(:todo_projects) do
      modify :inserted_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP")
      modify :updated_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")
    end
  end
end