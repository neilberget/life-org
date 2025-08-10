defmodule LifeOrgWeb.SearchDropdownComponent do
  use LifeOrgWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:query, fn -> "" end)
     |> assign_new(:results, fn -> [] end)
     |> assign_new(:selected_index, fn -> -1 end)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:show_dropdown, fn -> false end)}
  end

  @impl true
  def handle_event("search_input", %{"value" => query}, socket) do
    cond do
      String.trim(query) == "" ->
        {:noreply,
         socket
         |> assign(:query, query)
         |> assign(:results, [])
         |> assign(:show_dropdown, false)
         |> assign(:loading, false)}

      String.length(String.trim(query)) < 2 ->
        {:noreply,
         socket
         |> assign(:query, query)
         |> assign(:loading, false)}

      true ->
        # Cancel any existing search timer
        if socket.assigns[:search_timer] do
          Process.cancel_timer(socket.assigns.search_timer)
        end

        # Set up debounced search (300ms)
        timer = Process.send_after(self(), {:search_dropdown_perform, query, socket.assigns.id}, 300)

        {:noreply,
         socket
         |> assign(:query, query)
         |> assign(:search_timer, timer)
         |> assign(:loading, true)}
    end
  end

  @impl true
  def handle_event("navigate", %{"key" => key}, socket) do
    case key do
      "ArrowDown" ->
        new_index = min(socket.assigns.selected_index + 1, length(socket.assigns.results) - 1)
        {:noreply, assign(socket, :selected_index, new_index)}

      "ArrowUp" ->
        new_index = max(socket.assigns.selected_index - 1, -1)
        {:noreply, assign(socket, :selected_index, new_index)}

      "Enter" ->
        if socket.assigns.selected_index >= 0 do
          result = Enum.at(socket.assigns.results, socket.assigns.selected_index)
          navigate_to_result(socket, result)
        else
          # Submit full search
          send(self(), {:submit_full_search, socket.assigns.query})
          {:noreply, socket}
        end

      "Escape" ->
        {:noreply,
         socket
         |> assign(:show_dropdown, false)
         |> assign(:selected_index, -1)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_result", %{"index" => index}, socket) do
    index = String.to_integer(index)
    result = Enum.at(socket.assigns.results, index)
    navigate_to_result(socket, result)
  end

  @impl true
  def handle_event("submit_search", _params, socket) do
    send(self(), {:submit_full_search, socket.assigns.query})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:results, [])
     |> assign(:show_dropdown, false)
     |> assign(:selected_index, -1)}
  end


  defp navigate_to_result(socket, nil) do
    {:noreply, socket}
  end

  defp navigate_to_result(socket, result) do
    case result.type do
      :journal_entry ->
        send(self(), {:navigate_to, "/journal/#{result.id}"})

      :todo ->
        send(self(), {:navigate_to, "/todo/#{result.id}"})

      _ ->
        :ok
    end

    {:noreply,
     socket
     |> assign(:show_dropdown, false)
     |> assign(:selected_index, -1)}
  end

  defp format_preview(content, type) do
    max_length = if type == :todo, do: 80, else: 120
    
    content
    |> String.trim()
    |> String.slice(0, max_length)
    |> then(fn text ->
      if String.length(content) > max_length do
        text <> "..."
      else
        text
      end
    end)
  end

  defp type_icon(:journal_entry), do: "📓"
  defp type_icon(:todo), do: "✓"
  defp type_icon(_), do: "📄"

  defp type_label(:journal_entry), do: "Journal"
  defp type_label(:todo), do: "Todo"
  defp type_label(_), do: "Item"

  defp type_color(:journal_entry), do: "text-purple-600"
  defp type_color(:todo), do: "text-blue-600"
  defp type_color(_), do: "text-gray-600"
end