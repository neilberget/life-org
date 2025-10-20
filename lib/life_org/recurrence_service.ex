defmodule LifeOrg.RecurrenceService do
  @moduledoc """
  Service for managing recurring todo generation and calculations.
  Supports both fixed (date-based) and floating (completion-based) recurrence patterns.
  """

  alias LifeOrg.{Repo, Todo}
  import Ecto.Query
  require Logger

  @doc """
  Calculate the next occurrence date based on the template's pattern.

  For fixed recurrence, calculates from the base_date according to the pattern.
  For floating recurrence, calculates from the completion_date.
  """
  def calculate_next_occurrence(%Todo{recurrence_type: "fixed"} = template, base_date) do
    pattern = template.recurrence_pattern

    case pattern["frequency"] do
      "daily" -> calculate_daily_next(base_date, pattern["interval"] || 1)
      "weekly" -> calculate_weekly_next(base_date, pattern["interval"] || 1, pattern["days_of_week"])
      "monthly" -> calculate_monthly_next(base_date, pattern["interval"] || 1, pattern["day_of_month"])
      "yearly" -> calculate_yearly_next(base_date, pattern["interval"] || 1, pattern["month"], pattern["day"])
      _ -> {:error, "Unknown frequency: #{pattern["frequency"]}"}
    end
  end

  def calculate_next_occurrence(%Todo{recurrence_type: "floating"} = template, completion_date) do
    pattern = template.recurrence_pattern
    calculate_floating_next(completion_date, pattern["time_unit"], pattern["time_amount"])
  end

  @doc """
  Generate the next occurrence from a template todo.
  Returns {:ok, todo} if successfully created, {:ok, :recurrence_ended} if the series has ended.
  """
  def generate_next_occurrence(%Todo{is_template: true} = template) do
    base_date = get_base_date_for_next_occurrence(template)

    case calculate_next_occurrence(template, base_date) do
      {:ok, next_date} ->
        if should_generate_occurrence?(template, next_date) do
          create_occurrence_from_template(template, next_date)
        else
          {:ok, :recurrence_ended}
        end

      {:error, _reason} = error ->
        error
    end
  end

  def generate_next_occurrence(_todo), do: {:error, "Not a recurring template"}

  @doc """
  Handle the completion of a recurring todo occurrence.
  Updates the template metadata and generates the next occurrence.
  """
  def handle_occurrence_completion(%Todo{parent_todo_id: parent_id} = occurrence)
      when not is_nil(parent_id) do
    template = Repo.get!(Todo, parent_id)

    # Update template metadata with the completion
    update_template_metadata(template, occurrence)

    # Generate next occurrence (just-in-time strategy)
    generate_next_occurrence(template)
  end

  def handle_occurrence_completion(_todo), do: {:ok, :not_recurring}

  @doc """
  Update a template and optionally propagate changes to future occurrences.
  """
  def update_template_and_propagate(template, changes, propagate_to_future?) do
    # Update the template
    changeset = Todo.changeset(template, changes)

    case Repo.update(changeset) do
      {:ok, updated_template} ->
        # Optionally propagate to future occurrences
        if propagate_to_future? do
          propagate_changes_to_future_occurrences(updated_template, changes)
        end

        {:ok, updated_template}

      error ->
        error
    end
  end

  @doc """
  Get a human-readable description of the recurrence pattern.
  """
  def pattern_description(%Todo{recurrence_type: "fixed", recurrence_pattern: pattern}) do
    case pattern["frequency"] do
      "daily" ->
        interval = pattern["interval"] || 1
        if interval == 1, do: "Daily", else: "Every #{interval} days"

      "weekly" ->
        interval = pattern["interval"] || 1
        days = pattern["days_of_week"] || []
        day_names = Enum.map(days, &day_of_week_name/1) |> Enum.join(", ")
        prefix = if interval == 1, do: "Weekly on", else: "Every #{interval} weeks on"
        "#{prefix} #{day_names}"

      "monthly" ->
        interval = pattern["interval"] || 1
        day = pattern["day_of_month"]
        day_str = if day == -1, do: "last day", else: ordinal(day)
        if interval == 1, do: "Monthly on the #{day_str}", else: "Every #{interval} months on the #{day_str}"

      "yearly" ->
        interval = pattern["interval"] || 1
        month = month_name(pattern["month"])
        day = ordinal(pattern["day"])
        if interval == 1, do: "Yearly on #{month} #{day}", else: "Every #{interval} years on #{month} #{day}"

      _ ->
        "Unknown pattern"
    end
  end

  def pattern_description(%Todo{recurrence_type: "floating", recurrence_pattern: pattern}) do
    amount = pattern["time_amount"]
    unit = pattern["time_unit"]

    unit_str = if amount == 1, do: String.trim_trailing(unit, "s"), else: unit
    "#{amount} #{unit_str} after completion"
  end

  def pattern_description(_), do: ""

  # Private helper functions

  defp get_base_date_for_next_occurrence(%Todo{last_generated_occurrence_date: nil} = template) do
    # First occurrence: start from the recurrence_start_date
    template.recurrence_start_date || Date.utc_today()
  end

  defp get_base_date_for_next_occurrence(%Todo{last_generated_occurrence_date: last_date}) do
    # Subsequent occurrences: calculate from the last generated occurrence
    last_date
  end

  defp should_generate_occurrence?(%Todo{recurrence_end_date: nil}, _next_date), do: true

  defp should_generate_occurrence?(%Todo{recurrence_end_date: end_date}, next_date) do
    Date.compare(next_date, end_date) != :gt
  end

  defp create_occurrence_from_template(template, occurrence_date) do
    next_occurrence_number = (template.occurrence_number || 0) + 1

    occurrence_attrs = %{
      title: template.title,
      description: template.description,
      priority: template.priority,
      due_date: occurrence_date,
      due_time: template.due_time,
      tags: template.tags,
      workspace_id: template.workspace_id,
      parent_todo_id: template.id,
      occurrence_date: occurrence_date,
      occurrence_number: next_occurrence_number,
      is_recurring: false,
      is_template: false,
      position: 0
    }

    changeset = %Todo{} |> Todo.changeset(occurrence_attrs)

    case Repo.insert(changeset) do
      {:ok, occurrence} ->
        # Update template's metadata
        template
        |> Todo.changeset(%{
          last_generated_occurrence_date: occurrence_date,
          occurrence_number: next_occurrence_number
        })
        |> Repo.update()

        {:ok, occurrence}

      error ->
        error
    end
  end

  defp update_template_metadata(template, _completed_occurrence) do
    # Template metadata is already updated when occurrence was created
    # This could be extended to track additional statistics if needed
    {:ok, template}
  end

  defp propagate_changes_to_future_occurrences(template, changes) do
    # Fields that should propagate to future occurrences
    propagatable_fields = [:title, :description, :priority, :tags, :due_time]

    # Get only the fields that should propagate
    updates =
      changes
      |> Map.take(propagatable_fields)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(updates) > 0 do
      # Update all pending (not completed) occurrences
      from(t in Todo,
        where: t.parent_todo_id == ^template.id,
        where: t.completed == false
      )
      |> Repo.update_all(set: Map.to_list(updates))
    end

    :ok
  end

  # Date calculation functions

  defp calculate_daily_next(base_date, interval) do
    {:ok, Date.add(base_date, interval)}
  end

  defp calculate_weekly_next(base_date, interval, days_of_week) when is_list(days_of_week) do
    # Find the next occurrence of any of the specified weekdays
    # considering the interval (every N weeks)

    base_dow = Date.day_of_week(base_date)
    sorted_days = Enum.sort(days_of_week)

    # Find next day in current week
    case Enum.find(sorted_days, fn day -> day > base_dow end) do
      nil ->
        # No more days this week, go to first day of next interval
        first_day = hd(sorted_days)
        days_until_next = (7 - base_dow) + first_day + (7 * (interval - 1))
        {:ok, Date.add(base_date, days_until_next)}

      next_day ->
        # Found a day later this week
        days_until_next = next_day - base_dow
        {:ok, Date.add(base_date, days_until_next)}
    end
  end

  defp calculate_weekly_next(_base_date, _interval, _days_of_week) do
    {:error, "Weekly pattern requires days_of_week"}
  end

  defp calculate_monthly_next(base_date, interval, day_of_month) when is_integer(day_of_month) do
    next_month_date = Date.add(base_date, 30 * interval)  # Approximate next month
    year = next_month_date.year
    month = next_month_date.month

    # Handle last day of month
    target_day =
      if day_of_month == -1 do
        Date.days_in_month(Date.new!(year, month, 1))
      else
        min(day_of_month, Date.days_in_month(Date.new!(year, month, 1)))
      end

    {:ok, Date.new!(year, month, target_day)}
  end

  defp calculate_monthly_next(_base_date, _interval, _day_of_month) do
    {:error, "Monthly pattern requires day_of_month"}
  end

  defp calculate_yearly_next(base_date, interval, month, day)
      when is_integer(month) and is_integer(day) do
    next_year = base_date.year + interval

    # Handle February 29 on non-leap years
    target_day =
      if month == 2 and day == 29 and not Date.leap_year?(Date.new!(next_year, 1, 1)) do
        28
      else
        day
      end

    {:ok, Date.new!(next_year, month, target_day)}
  end

  defp calculate_yearly_next(_base_date, _interval, _month, _day) do
    {:error, "Yearly pattern requires month and day"}
  end

  defp calculate_floating_next(completion_date, time_unit, time_amount)
      when is_integer(time_amount) and time_amount > 0 do
    case time_unit do
      "days" ->
        {:ok, Date.add(completion_date, time_amount)}

      "weeks" ->
        {:ok, Date.add(completion_date, time_amount * 7)}

      "months" ->
        add_months(completion_date, time_amount)

      "years" ->
        {:ok, Date.new!(completion_date.year + time_amount, completion_date.month, completion_date.day)}

      _ ->
        {:error, "Unknown time unit: #{time_unit}"}
    end
  end

  defp add_months(date, months) do
    # Calculate target month/year
    total_months = date.year * 12 + date.month - 1 + months
    target_year = div(total_months, 12)
    target_month = rem(total_months, 12) + 1

    # Handle day overflow (e.g., Jan 31 + 1 month = Feb 28/29)
    max_day = Date.days_in_month(Date.new!(target_year, target_month, 1))
    target_day = min(date.day, max_day)

    {:ok, Date.new!(target_year, target_month, target_day)}
  end

  # Helper functions for human-readable descriptions

  defp day_of_week_name(1), do: "Monday"
  defp day_of_week_name(2), do: "Tuesday"
  defp day_of_week_name(3), do: "Wednesday"
  defp day_of_week_name(4), do: "Thursday"
  defp day_of_week_name(5), do: "Friday"
  defp day_of_week_name(6), do: "Saturday"
  defp day_of_week_name(7), do: "Sunday"
  defp day_of_week_name(_), do: "Unknown"

  defp month_name(1), do: "January"
  defp month_name(2), do: "February"
  defp month_name(3), do: "March"
  defp month_name(4), do: "April"
  defp month_name(5), do: "May"
  defp month_name(6), do: "June"
  defp month_name(7), do: "July"
  defp month_name(8), do: "August"
  defp month_name(9), do: "September"
  defp month_name(10), do: "October"
  defp month_name(11), do: "November"
  defp month_name(12), do: "December"
  defp month_name(_), do: "Unknown"

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(21), do: "21st"
  defp ordinal(22), do: "22nd"
  defp ordinal(23), do: "23rd"
  defp ordinal(31), do: "31st"
  defp ordinal(n), do: "#{n}th"
end
