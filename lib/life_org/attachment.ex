defmodule LifeOrg.Attachment do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.{JournalEntry, Todo}
  alias LifeOrg.Accounts.User

  schema "attachments" do
    field :filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :file_size, :integer

    belongs_to :user, User
    belongs_to :journal_entry, JournalEntry
    belongs_to :todo, Todo

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :original_filename, :content_type, :file_size, :user_id, :journal_entry_id, :todo_id])
    |> validate_required([:filename, :original_filename, :content_type, :file_size, :user_id])
    |> validate_number(:file_size, greater_than: 0, less_than: 10_000_000) # 10MB max
    |> validate_format(:content_type, ~r/^image\/(jpeg|jpg|png|gif|webp)$/)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:journal_entry_id)
    |> foreign_key_constraint(:todo_id)
  end
end
