defmodule LifeOrg.ConversationService do
  alias LifeOrg.{Repo, Conversation, ChatMessage}
  import Ecto.Query

  def create_conversation(title) do
    %Conversation{}
    |> Conversation.changeset(%{title: title})
    |> Repo.insert()
  end

  def get_conversation_with_messages(id) do
    Conversation
    |> where([c], c.id == ^id)
    |> preload(:chat_messages)
    |> Repo.one()
  end

  def list_conversations do
    Conversation
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  def add_message_to_conversation(conversation_id, role, content) do
    %ChatMessage{}
    |> ChatMessage.changeset(%{
      conversation_id: conversation_id,
      role: role,
      content: content
    })
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        # Update conversation's updated_at timestamp
        conversation = Repo.get!(Conversation, conversation_id)
        conversation
        |> Ecto.Changeset.change(updated_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update!()
        
        {:ok, message}
      error -> error
    end
  end

  def get_or_create_conversation(nil, first_message) do
    title = Conversation.generate_title_from_message(first_message)
    create_conversation(title)
  end
  
  def get_or_create_conversation(conversation_id, _first_message) do
    case get_conversation_with_messages(conversation_id) do
      nil -> {:error, "Conversation not found"}
      conversation -> {:ok, conversation}
    end
  end

  def get_conversation_messages_for_ai(conversation_id) do
    ChatMessage
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
  end
end