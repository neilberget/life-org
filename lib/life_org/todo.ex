defmodule LifeOrg.Todo do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Workspace
  alias LifeOrg.TodoComment
  alias LifeOrg.JournalEntry
  alias LifeOrg.Projects.Project

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
    field :embedding, {:array, :float}
    field :embedding_generated_at, :utc_datetime
    field :position, :integer, default: 0

    # Recurring todo fields
    field :is_recurring, :boolean, default: false
    field :recurrence_type, :string  # "fixed" or "floating"
    field :recurrence_pattern, :map  # Flexible JSON pattern
    field :recurrence_start_date, :date
    field :recurrence_end_date, :date
    field :parent_todo_id, :integer
    field :occurrence_date, :date
    field :is_template, :boolean, default: false
    field :occurrence_number, :integer
    field :last_generated_occurrence_date, :date

    belongs_to :workspace, Workspace
    belongs_to :journal_entry, JournalEntry
    has_many :comments, TodoComment, foreign_key: :todo_id
    many_to_many :projects, Project,
      join_through: "todo_projects",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [
      :title, :description, :completed, :priority, :due_date, :due_time,
      :ai_generated, :current, :workspace_id, :journal_entry_id, :tags, :position,
      :is_recurring, :recurrence_type, :recurrence_pattern, :recurrence_start_date,
      :recurrence_end_date, :parent_todo_id, :occurrence_date, :is_template,
      :occurrence_number, :last_generated_occurrence_date
    ])
    |> validate_required([:title, :workspace_id])
    |> validate_inclusion(:priority, ["high", "medium", "low"])
    |> validate_recurrence_fields()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:parent_todo_id)
  end

  defp validate_recurrence_fields(changeset) do
    case get_field(changeset, :is_recurring) do
      true ->
        changeset
        |> validate_required([:recurrence_type, :recurrence_pattern, :recurrence_start_date])
        |> validate_inclusion(:recurrence_type, ["fixed", "floating"])
        |> validate_recurrence_pattern()
      _ ->
        changeset
    end
  end

  defp validate_recurrence_pattern(changeset) do
    case get_change(changeset, :recurrence_pattern) do
      nil -> changeset
      pattern when is_map(pattern) ->
        case validate_pattern_structure(pattern) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, :recurrence_pattern, message)
        end
      _ ->
        add_error(changeset, :recurrence_pattern, "must be a valid map")
    end
  end

  defp validate_pattern_structure(%{"frequency" => frequency} = pattern) when frequency in ["daily", "weekly", "monthly", "yearly"] do
    cond do
      frequency == "weekly" and not is_list(pattern["days_of_week"]) ->
        {:error, "weekly pattern must include days_of_week as a list"}
      frequency == "monthly" and not is_integer(pattern["day_of_month"]) ->
        {:error, "monthly pattern must include day_of_month as an integer"}
      frequency == "yearly" and (not is_integer(pattern["month"]) or not is_integer(pattern["day"])) ->
        {:error, "yearly pattern must include month and day as integers"}
      true ->
        :ok
    end
  end

  defp validate_pattern_structure(%{"frequency" => "floating", "time_unit" => unit, "time_amount" => amount})
      when unit in ["days", "weeks", "months", "years"] and is_integer(amount) and amount > 0 do
    :ok
  end

  defp validate_pattern_structure(_), do: {:error, "invalid recurrence pattern structure"}
end
