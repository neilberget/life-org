defmodule LifeOrg.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages) do
      add :role, :string
      add :content, :text
      add :conversation_id, references(:conversations, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:conversation_id])
  end
end
