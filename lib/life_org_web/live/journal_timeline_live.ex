defmodule LifeOrgWeb.JournalTimelineLive do
  use LifeOrgWeb, :live_view

  on_mount {LifeOrgWeb.UserAuth, :ensure_authenticated}

  alias LifeOrg.WorkspaceService

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    
    {:ok, _} = WorkspaceService.ensure_default_workspace(current_user)
    
    current_workspace = WorkspaceService.get_default_workspace(current_user.id)
    workspaces = WorkspaceService.list_workspaces(current_user.id)
    journal_entries = WorkspaceService.list_journal_entries(current_workspace.id)

    # Auto-select first entry if any exist
    {selected_entry, related_todos} = 
      case journal_entries do
        [] -> {nil, []}
        [first_entry | _] -> 
          todos = WorkspaceService.list_journal_todos(first_entry.id)
          {first_entry, todos}
      end

    {:ok,
     socket
     |> assign(:current_workspace, current_workspace)
     |> assign(:workspaces, workspaces)
     |> assign(:journal_entries, journal_entries)
     |> assign(:selected_entry, selected_entry)
     |> assign(:related_todos, related_todos)
     |> assign(:user_timezone, current_user.timezone || "America/Chicago")}
  end

  @impl true
  def handle_event("select_entry", %{"id" => id}, socket) do
    selected_entry = Enum.find(socket.assigns.journal_entries, &(&1.id == String.to_integer(id)))
    
    # Get todos extracted from this journal entry
    related_todos = WorkspaceService.list_journal_todos(String.to_integer(id))
    
    {:noreply,
     socket
     |> assign(:selected_entry, selected_entry)
     |> assign(:related_todos, related_todos)
     |> push_event("scroll_to_entry", %{entry_id: String.to_integer(id)})}
  end

  @impl true
  def handle_event("navigate_timeline", %{"key" => "j"}, socket) do
    # Navigate to next entry
    case get_next_entry(socket.assigns.journal_entries, socket.assigns.selected_entry) do
      nil ->
        {:noreply, socket}
      
      next_entry ->
        related_todos = WorkspaceService.list_journal_todos(next_entry.id)
        
        {:noreply,
         socket
         |> assign(:selected_entry, next_entry)
         |> assign(:related_todos, related_todos)
         |> push_event("scroll_to_entry", %{entry_id: next_entry.id})}
    end
  end

  @impl true
  def handle_event("navigate_timeline", %{"key" => "k"}, socket) do
    # Navigate to previous entry
    case get_previous_entry(socket.assigns.journal_entries, socket.assigns.selected_entry) do
      nil ->
        {:noreply, socket}
      
      prev_entry ->
        related_todos = WorkspaceService.list_journal_todos(prev_entry.id)
        
        {:noreply,
         socket
         |> assign(:selected_entry, prev_entry)
         |> assign(:related_todos, related_todos)
         |> push_event("scroll_to_entry", %{entry_id: prev_entry.id})}
    end
  end

  @impl true
  def handle_event("navigate_timeline", %{"key" => _other}, socket) do
    # Ignore other keys
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_workspace", %{"id" => id}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id), socket.assigns.current_user.id)
    journal_entries = WorkspaceService.list_journal_entries(workspace.id)

    {:noreply,
     socket
     |> assign(:current_workspace, workspace)
     |> assign(:journal_entries, journal_entries)
     |> assign(:selected_entry, nil)
     |> assign(:related_todos, [])
     |> push_event("workspace_changed", %{workspace_id: workspace.id})}
  end

  @impl true
  def handle_event("load_saved_workspace", %{"workspace_id" => workspace_id}, socket) do
    workspace =
      case WorkspaceService.get_workspace(String.to_integer(workspace_id), socket.assigns.current_user.id) do
        nil -> socket.assigns.current_workspace
        ws -> ws
      end

    if workspace.id != socket.assigns.current_workspace.id do
      journal_entries = WorkspaceService.list_journal_entries(workspace.id)

      {:noreply,
       socket
       |> assign(:current_workspace, workspace)
       |> assign(:journal_entries, journal_entries)
       |> assign(:selected_entry, nil)
       |> assign(:related_todos, [])}
    else
      {:noreply, socket}
    end
  end

  defp get_next_entry(entries, nil) do
    # If no entry selected, select the first one
    List.first(entries)
  end

  defp get_next_entry(entries, current_entry) do
    current_index = Enum.find_index(entries, &(&1.id == current_entry.id))
    
    case current_index do
      nil -> nil
      index when index < length(entries) - 1 -> Enum.at(entries, index + 1)
      _ -> nil  # Already at last entry
    end
  end

  defp get_previous_entry(_entries, nil) do
    nil
  end

  defp get_previous_entry(entries, current_entry) do
    current_index = Enum.find_index(entries, &(&1.id == current_entry.id))
    
    case current_index do
      nil -> nil
      0 -> nil  # Already at first entry
      index -> Enum.at(entries, index - 1)
    end
  end
end