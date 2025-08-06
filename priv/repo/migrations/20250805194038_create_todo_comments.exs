defmodule LifeOrg.Repo.Migrations.CreateTodoComments do
  use Ecto.Migration

  def change do
    create table(:todo_comments) do
      add :content, :text, null: false
      add :todo_id, references(:todos, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:todo_comments, [:todo_id])
  end
end
