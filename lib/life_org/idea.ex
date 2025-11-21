defmodule LifeOrg.Idea do
  use Ecto.Schema
  import Ecto.Changeset

  @timeframe_options ~w(someday next_year distant_future)
  @status_options ~w(captured exploring parked converted)

  schema "ideas" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :timeframe, :string
    field :tags, {:array, :string}, default: []
    field :status, :string, default: "captured"
    field :position, :integer
    field :embedding, {:array, :float}
    field :embedding_generated_at, :utc_datetime

    belongs_to :workspace, LifeOrg.Workspace
    belongs_to :journal_entry, LifeOrg.JournalEntry

    timestamps()
  end

  def changeset(idea, attrs) do
    idea
    |> cast(attrs, [
      :title,
      :description,
      :category,
      :timeframe,
      :tags,
      :status,
      :position,
      :workspace_id,
      :journal_entry_id,
      :embedding,
      :embedding_generated_at
    ])
    |> validate_required([:title, :workspace_id])
    |> validate_inclusion(:timeframe, @timeframe_options)
    |> validate_inclusion(:status, @status_options)
    |> ensure_tags_are_strings()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:journal_entry_id)
  end

  defp ensure_tags_are_strings(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        string_tags = Enum.map(tags, &to_string/1)
        put_change(changeset, :tags, string_tags)

      _ ->
        changeset
    end
  end

  def timeframe_options, do: @timeframe_options
  def status_options, do: @status_options
end
