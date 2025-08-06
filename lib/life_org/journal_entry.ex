defmodule LifeOrg.JournalEntry do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Workspace
  alias LifeOrg.Todo

  schema "journal_entries" do
    field :content, :string
    field :tags, {:array, :string}, default: []
    field :mood, :string
    field :entry_date, :date

    belongs_to :workspace, Workspace
    has_many :todos, Todo

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(journal_entry, attrs) do
    journal_entry
    |> cast(attrs, [:content, :tags, :mood, :entry_date, :workspace_id])
    |> validate_required([:content, :entry_date, :workspace_id])
    |> foreign_key_constraint(:workspace_id)
  end
end
