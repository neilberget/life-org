defmodule LifeOrg.Conversation do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.{ChatMessage, Workspace}

  schema "conversations" do
    field :title, :string
    has_many :chat_messages, ChatMessage, preload_order: [asc: :inserted_at]
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :workspace_id])
    |> validate_required([:title, :workspace_id])
    |> foreign_key_constraint(:workspace_id)
  end
  
  def generate_title_from_message(message) do
    # Generate a title from the first message, truncating if too long
    message
    |> String.trim()
    |> String.slice(0, 50)
    |> case do
      title when byte_size(title) == 50 -> title <> "..."
      title -> title
    end
  end
end
