defmodule LifeOrg.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Conversation

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    belongs_to :conversation, Conversation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [:role, :content, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
