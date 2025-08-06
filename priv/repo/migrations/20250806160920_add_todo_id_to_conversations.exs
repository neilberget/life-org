defmodule LifeOrg.Repo.Migrations.AddTodoIdToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :todo_id, references(:todos, on_delete: :delete_all), null: true
    end

    create index(:conversations, [:todo_id])
  end
end
