defmodule LifeOrg.Repo.Migrations.FixChatMessagesCascadeDelete do
  use Ecto.Migration

  def change do
    # Drop the existing foreign key constraint
    drop constraint(:chat_messages, "chat_messages_conversation_id_fkey")
    
    # Recreate with cascade delete
    alter table(:chat_messages) do
      modify :conversation_id, references(:conversations, on_delete: :delete_all)
    end
  end
end
