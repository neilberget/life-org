defmodule LifeOrg.Todo do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Workspace
  alias LifeOrg.TodoComment
  alias LifeOrg.JournalEntry

  schema "todos" do
    field :priority, :string
    field :description, :string
    field :title, :string
    field :completed, :boolean, default: false
    field :due_date, :date
    field :due_time, :time
    field :ai_generated, :boolean, default: false
    field :current, :boolean, default: false
    field :tags, {:array, :string}, default: []
    field :comment_count, :integer, virtual: true, default: 0

    belongs_to :workspace, Workspace
    belongs_to :journal_entry, JournalEntry
    has_many :comments, TodoComment, foreign_key: :todo_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title, :description, :completed, :priority, :due_date, :due_time, :ai_generated, :current, :workspace_id, :journal_entry_id, :tags])
    |> validate_required([:title, :workspace_id])
    |> validate_inclusion(:priority, ["high", "medium", "low"])
    |> foreign_key_constraint(:workspace_id)
  end
end
