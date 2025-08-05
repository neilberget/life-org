defmodule LifeOrg.Todo do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Workspace

  schema "todos" do
    field :priority, :string
    field :description, :string
    field :title, :string
    field :completed, :boolean, default: false
    field :due_date, :date
    field :due_time, :time
    field :ai_generated, :boolean, default: false
    field :tags, {:array, :string}, default: []

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title, :description, :completed, :priority, :due_date, :due_time, :ai_generated, :workspace_id, :tags])
    |> validate_required([:title, :workspace_id])
    |> validate_inclusion(:priority, ["high", "medium", "low"])
    |> foreign_key_constraint(:workspace_id)
  end
end
