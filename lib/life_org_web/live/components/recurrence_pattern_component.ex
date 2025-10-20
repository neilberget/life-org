defmodule LifeOrgWeb.Components.RecurrencePatternComponent do
  use LifeOrgWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="space-y-4 border-t border-gray-200 pt-4 mt-4">
      <!-- Recurring Toggle -->
      <div class="flex items-center">
        <input
          type="checkbox"
          id="is_recurring"
          name="todo[is_recurring]"
          value="true"
          checked={@is_recurring}
          phx-click="toggle_recurring"
          phx-target={@myself}
          class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
        />
        <label for="is_recurring" class="ml-2 block text-sm font-medium text-gray-700">
          Make this a recurring todo
        </label>
      </div>

      <%= if @is_recurring do %>
        <!-- Recurrence Type -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Recurrence Type</label>
          <div class="flex gap-4">
            <label class="flex items-center">
              <input
                type="radio"
                name="todo[recurrence_type]"
                value="fixed"
                checked={@recurrence_type == "fixed"}
                phx-click="set_recurrence_type"
                phx-value-type="fixed"
                phx-target={@myself}
                class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300"
              />
              <span class="ml-2 text-sm text-gray-700">Fixed Schedule</span>
            </label>
            <label class="flex items-center">
              <input
                type="radio"
                name="todo[recurrence_type]"
                value="floating"
                checked={@recurrence_type == "floating"}
                phx-click="set_recurrence_type"
                phx-value-type="floating"
                phx-target={@myself}
                class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300"
              />
              <span class="ml-2 text-sm text-gray-700">After Completion</span>
            </label>
          </div>
          <p class="mt-1 text-xs text-gray-500">
            <%= if @recurrence_type == "fixed" do %>
              Fixed: Repeats on specific dates (e.g., every Monday, 1st of each month)
            <% else %>
              After Completion: Next due date is calculated from when you complete it
            <% end %>
          </p>
        </div>

        <%= if @recurrence_type == "fixed" do %>
          <!-- Fixed Pattern Builder -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Frequency</label>
            <select
              name="todo[recurrence_frequency]"
              phx-change="set_frequency"
              phx-target={@myself}
              class="mt-1 block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
            >
              <option value="daily" selected={@frequency == "daily"}>Daily</option>
              <option value="weekly" selected={@frequency == "weekly"}>Weekly</option>
              <option value="monthly" selected={@frequency == "monthly"}>Monthly</option>
              <option value="yearly" selected={@frequency == "yearly"}>Yearly</option>
            </select>
          </div>

          <!-- Interval -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Repeat every
            </label>
            <div class="flex items-center gap-2">
              <input
                type="number"
                name="todo[recurrence_interval]"
                value={@interval}
                min="1"
                phx-change="set_interval"
                phx-target={@myself}
                class="block w-20 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
              />
              <span class="text-sm text-gray-700">
                <%= frequency_unit(@frequency, @interval) %>
              </span>
            </div>
          </div>

          <!-- Weekly: Days of Week -->
          <%= if @frequency == "weekly" do %>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">On these days</label>
              <div class="flex flex-wrap gap-2">
                <%= for {day_name, day_num} <- [{"Mon", 1}, {"Tue", 2}, {"Wed", 3}, {"Thu", 4}, {"Fri", 5}, {"Sat", 6}, {"Sun", 7}] do %>
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      name="todo[recurrence_days_of_week][]"
                      value={day_num}
                      checked={day_num in @days_of_week}
                      phx-click="toggle_day"
                      phx-value-day={day_num}
                      phx-target={@myself}
                      class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                    />
                    <span class="ml-1 text-sm text-gray-700"><%= day_name %></span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Monthly: Day of Month -->
          <%= if @frequency == "monthly" do %>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">On day</label>
              <select
                name="todo[recurrence_day_of_month]"
                phx-change="set_day_of_month"
                phx-target={@myself}
                class="mt-1 block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
              >
                <%= for day <- 1..31 do %>
                  <option value={day} selected={@day_of_month == day}><%= day %></option>
                <% end %>
                <option value="-1" selected={@day_of_month == -1}>Last day of month</option>
              </select>
            </div>
          <% end %>

          <!-- Yearly: Month and Day -->
          <%= if @frequency == "yearly" do %>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Month</label>
                <select
                  name="todo[recurrence_month]"
                  phx-change="set_month"
                  phx-target={@myself}
                  class="mt-1 block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
                >
                  <%= for {month_name, month_num} <- month_options() do %>
                    <option value={month_num} selected={@month == month_num}><%= month_name %></option>
                  <% end %>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Day</label>
                <input
                  type="number"
                  name="todo[recurrence_day]"
                  value={@day}
                  min="1"
                  max="31"
                  phx-change="set_day"
                  phx-target={@myself}
                  class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                />
              </div>
            </div>
          <% end %>

        <% else %>
          <!-- Floating Pattern Builder -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Due again after completion
            </label>
            <div class="flex items-center gap-2">
              <input
                type="number"
                name="todo[recurrence_time_amount]"
                value={@time_amount}
                min="1"
                phx-change="set_time_amount"
                phx-target={@myself}
                class="block w-20 px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
              />
              <select
                name="todo[recurrence_time_unit]"
                phx-change="set_time_unit"
                phx-target={@myself}
                class="block w-32 pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
              >
                <option value="days" selected={@time_unit == "days"}>days</option>
                <option value="weeks" selected={@time_unit == "weeks"}>weeks</option>
                <option value="months" selected={@time_unit == "months"}>months</option>
                <option value="years" selected={@time_unit == "years"}>years</option>
              </select>
            </div>
          </div>
        <% end %>

        <!-- Date Range -->
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Start Date <span class="text-red-500">*</span>
            </label>
            <input
              type="date"
              name="todo[recurrence_start_date]"
              value={@start_date}
              required
              phx-change="set_start_date"
              phx-target={@myself}
              class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              End Date (optional)
            </label>
            <input
              type="date"
              name="todo[recurrence_end_date]"
              value={@end_date}
              phx-change="set_end_date"
              phx-target={@myself}
              class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
            />
          </div>
        </div>

        <!-- Pattern Preview -->
        <div class="bg-blue-50 border border-blue-200 rounded-md p-3">
          <p class="text-sm font-medium text-blue-900">Pattern Preview:</p>
          <p class="text-sm text-blue-700 mt-1"><%= pattern_preview(assigns) %></p>
        </div>

        <!-- Hidden fields to store JSON pattern -->
        <input type="hidden" name="todo[recurrence_pattern]" value={Jason.encode!(@pattern)} />
      <% end %>
    </div>
    """
  end

  def mount(socket) do
    {:ok,
     socket
     |> assign_defaults()}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Initialize from existing todo if provided
    socket =
      if Map.has_key?(assigns, :todo) && assigns.todo do
        initialize_from_todo(socket, assigns.todo)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("toggle_recurring", _, socket) do
    socket = assign(socket, :is_recurring, !socket.assigns.is_recurring)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_recurrence_type", %{"type" => type}, socket) do
    socket = assign(socket, :recurrence_type, type)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_frequency", %{"todo" => %{"recurrence_frequency" => freq}}, socket) do
    socket = assign(socket, :frequency, freq)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_interval", %{"todo" => %{"recurrence_interval" => interval}}, socket) do
    parsed_interval = safe_parse_integer(interval, socket.assigns.interval)
    socket = assign(socket, :interval, parsed_interval)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("toggle_day", %{"day" => day}, socket) do
    day = String.to_integer(day)
    days = socket.assigns.days_of_week

    new_days =
      if day in days do
        List.delete(days, day)
      else
        [day | days] |> Enum.sort()
      end

    socket = assign(socket, :days_of_week, new_days)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_day_of_month", %{"todo" => %{"recurrence_day_of_month" => dom}}, socket) do
    parsed_dom = safe_parse_integer(dom, socket.assigns.day_of_month)
    socket = assign(socket, :day_of_month, parsed_dom)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_month", %{"todo" => %{"recurrence_month" => month}}, socket) do
    parsed_month = safe_parse_integer(month, socket.assigns.month)
    socket = assign(socket, :month, parsed_month)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_day", %{"todo" => %{"recurrence_day" => day}}, socket) do
    parsed_day = safe_parse_integer(day, socket.assigns.day)
    socket = assign(socket, :day, parsed_day)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_time_amount", %{"todo" => %{"recurrence_time_amount" => amount}}, socket) do
    parsed_amount = safe_parse_integer(amount, socket.assigns.time_amount)
    socket = assign(socket, :time_amount, parsed_amount)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_time_unit", %{"todo" => %{"recurrence_time_unit" => unit}}, socket) do
    socket = assign(socket, :time_unit, unit)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_start_date", %{"todo" => %{"recurrence_start_date" => date}}, socket) do
    socket = assign(socket, :start_date, date)
    {:noreply, update_pattern(socket)}
  end

  def handle_event("set_end_date", %{"todo" => %{"recurrence_end_date" => date}}, socket) do
    socket = assign(socket, :end_date, date)
    {:noreply, update_pattern(socket)}
  end

  # Build the pattern JSON based on current settings
  defp update_pattern(socket) do
    pattern =
      if socket.assigns.recurrence_type == "floating" do
        %{
          "frequency" => "floating",
          "time_unit" => socket.assigns.time_unit,
          "time_amount" => socket.assigns.time_amount
        }
      else
        base = %{
          "frequency" => socket.assigns.frequency,
          "interval" => socket.assigns.interval
        }

        case socket.assigns.frequency do
          "weekly" ->
            Map.put(base, "days_of_week", socket.assigns.days_of_week)

          "monthly" ->
            Map.put(base, "day_of_month", socket.assigns.day_of_month)

          "yearly" ->
            base
            |> Map.put("month", socket.assigns.month)
            |> Map.put("day", socket.assigns.day)

          _ ->
            base
        end
      end

    assign(socket, :pattern, pattern)
  end

  # Helper functions

  defp assign_defaults(socket) do
    today = Date.utc_today() |> Date.to_iso8601()

    socket
    |> assign(:is_recurring, false)
    |> assign(:recurrence_type, "fixed")
    |> assign(:frequency, "daily")
    |> assign(:interval, 1)
    |> assign(:days_of_week, [1])
    |> assign(:day_of_month, 1)
    |> assign(:month, 1)
    |> assign(:day, 1)
    |> assign(:time_amount, 1)
    |> assign(:time_unit, "days")
    |> assign(:start_date, today)
    |> assign(:end_date, "")
    |> assign(:pattern, %{"frequency" => "daily", "interval" => 1})
  end

  defp initialize_from_todo(socket, todo) do
    if todo.is_recurring do
      pattern = todo.recurrence_pattern || %{}

      socket
      |> assign(:is_recurring, true)
      |> assign(:recurrence_type, todo.recurrence_type || "fixed")
      |> assign(:frequency, pattern["frequency"] || "daily")
      |> assign(:interval, pattern["interval"] || 1)
      |> assign(:days_of_week, pattern["days_of_week"] || [1])
      |> assign(:day_of_month, pattern["day_of_month"] || 1)
      |> assign(:month, pattern["month"] || 1)
      |> assign(:day, pattern["day"] || 1)
      |> assign(:time_amount, pattern["time_amount"] || 1)
      |> assign(:time_unit, pattern["time_unit"] || "days")
      |> assign(
        :start_date,
        if(todo.recurrence_start_date, do: Date.to_iso8601(todo.recurrence_start_date), else: "")
      )
      |> assign(
        :end_date,
        if(todo.recurrence_end_date, do: Date.to_iso8601(todo.recurrence_end_date), else: "")
      )
    else
      socket
    end
  end

  defp frequency_unit("daily", 1), do: "day"
  defp frequency_unit("daily", _), do: "days"
  defp frequency_unit("weekly", 1), do: "week"
  defp frequency_unit("weekly", _), do: "weeks"
  defp frequency_unit("monthly", 1), do: "month"
  defp frequency_unit("monthly", _), do: "months"
  defp frequency_unit("yearly", 1), do: "year"
  defp frequency_unit("yearly", _), do: "years"

  defp month_options do
    [
      {"January", 1},
      {"February", 2},
      {"March", 3},
      {"April", 4},
      {"May", 5},
      {"June", 6},
      {"July", 7},
      {"August", 8},
      {"September", 9},
      {"October", 10},
      {"November", 11},
      {"December", 12}
    ]
  end

  defp pattern_preview(assigns) do
    cond do
      !assigns.is_recurring ->
        "Not recurring"

      assigns.recurrence_type == "floating" ->
        "Due #{assigns.time_amount} #{assigns.time_unit} after completion"

      assigns.recurrence_type == "fixed" ->
        case assigns.frequency do
          "daily" ->
            if assigns.interval == 1,
              do: "Every day",
              else: "Every #{assigns.interval} days"

          "weekly" ->
            days = Enum.map(assigns.days_of_week, &day_name/1) |> Enum.join(", ")

            prefix =
              if assigns.interval == 1,
                do: "Every week",
                else: "Every #{assigns.interval} weeks"

            "#{prefix} on #{days}"

          "monthly" ->
            day_str = if assigns.day_of_month == -1, do: "last day", else: "day #{assigns.day_of_month}"

            if assigns.interval == 1,
              do: "Every month on the #{day_str}",
              else: "Every #{assigns.interval} months on the #{day_str}"

          "yearly" ->
            month = Enum.find(month_options(), fn {_, num} -> num == assigns.month end) |> elem(0)

            if assigns.interval == 1,
              do: "Every year on #{month} #{assigns.day}",
              else: "Every #{assigns.interval} years on #{month} #{assigns.day}"
        end

      true ->
        "Invalid pattern"
    end
  end

  defp day_name(1), do: "Monday"
  defp day_name(2), do: "Tuesday"
  defp day_name(3), do: "Wednesday"
  defp day_name(4), do: "Thursday"
  defp day_name(5), do: "Friday"
  defp day_name(6), do: "Saturday"
  defp day_name(7), do: "Sunday"

  # Safe integer parsing that handles empty strings and invalid input
  defp safe_parse_integer(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      trimmed ->
        case Integer.parse(trimmed) do
          {num, _} when num > 0 -> num
          _ -> default
        end
    end
  end

  defp safe_parse_integer(value, _default) when is_integer(value), do: value
  defp safe_parse_integer(_, default), do: default
end
