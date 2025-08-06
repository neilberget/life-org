defmodule LifeOrg.TodoComment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todo_comments" do
    field :content, :string
    belongs_to :todo, LifeOrg.Todo

    timestamps()
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:content, :todo_id])
    |> validate_required([:content, :todo_id])
    |> validate_length(:content, min: 1)
  end
end