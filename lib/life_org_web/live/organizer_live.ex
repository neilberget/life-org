defmodule LifeOrgWeb.OrganizerLive do
  use LifeOrgWeb, :live_view
  alias LifeOrg.{Repo, JournalEntry, Todo, AIHandler, ConversationService, WorkspaceService}
  alias LifeOrgWeb.Components.{JournalComponent, ChatComponent, TodoComponent}

  @impl true
  def mount(_params, _session, socket) do
    # Get default workspace
    current_workspace = WorkspaceService.get_default_workspace()
    workspaces = WorkspaceService.list_workspaces()
    
    # Load data for current workspace
    journal_entries = WorkspaceService.list_journal_entries(current_workspace.id)
    todos = WorkspaceService.list_todos(current_workspace.id) |> sort_todos()
    conversations = WorkspaceService.list_conversations(current_workspace.id)
    
    {:ok,
     socket
     |> assign(:current_workspace, current_workspace)
     |> assign(:workspaces, workspaces)
     |> assign(:journal_entries, journal_entries)
     |> assign(:todos, todos)
     |> assign(:incoming_todos, [])
     |> assign(:conversations, conversations)
     |> assign(:current_conversation, nil)
     |> assign(:chat_messages, [])
     |> assign(:processing_message, false)
     |> assign(:editing_entry, nil)
     |> assign(:editing_todo, nil)
     |> assign(:editing_workspace, nil)
     |> assign(:show_workspace_form, false)
     |> assign(:show_ai_sidebar, false)
     |> assign(:ai_sidebar_view, :conversations)
     |> assign(:tag_filter, nil)}
  end

  @impl true
  def handle_event("create_journal_entry", %{"journal_entry" => params}, socket) do
    case WorkspaceService.create_journal_entry(params, socket.assigns.current_workspace.id) do
      {:ok, entry} ->
        entries = [entry | socket.assigns.journal_entries]
        
        # Extract todos from journal entry in background
        parent_pid = self()
        workspace_id = socket.assigns.current_workspace.id
        existing_todos = socket.assigns.todos
        
        Task.start(fn ->
          {:ok, todo_actions} = AIHandler.extract_todos_from_journal(entry.content, existing_todos)
          send(parent_pid, {:extracted_todos, todo_actions, workspace_id})
        end)
        
        {:noreply,
         socket
         |> assign(:journal_entries, entries)
         |> push_event("clear_journal_form", %{})
         |> put_flash(:info, "Journal entry created successfully")}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error creating journal entry")}
    end
  end

  @impl true
  def handle_event("delete_journal_entry", %{"id" => id}, socket) do
    entry = Repo.get!(JournalEntry, id)
    {:ok, _} = WorkspaceService.delete_journal_entry(entry)
    
    entries = Enum.reject(socket.assigns.journal_entries, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :journal_entries, entries)}
  end

  @impl true
  def handle_event("switch_workspace", %{"id" => id}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id))
    
    # Load data for the new workspace
    journal_entries = WorkspaceService.list_journal_entries(workspace.id)
    todos = WorkspaceService.list_todos(workspace.id) |> sort_todos()
    conversations = WorkspaceService.list_conversations(workspace.id)
    
    {:noreply,
     socket
     |> assign(:current_workspace, workspace)
     |> assign(:journal_entries, journal_entries)
     |> assign(:todos, todos)
     |> assign(:incoming_todos, [])
     |> assign(:conversations, conversations)
     |> assign(:current_conversation, nil)
     |> assign(:chat_messages, [])
     |> assign(:tag_filter, nil)}
  end

  @impl true
  def handle_event("toggle_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, id)
    {:ok, updated_todo} = WorkspaceService.update_todo(todo, %{completed: !todo.completed})
    
    todos = update_todo_in_list(socket.assigns.todos, updated_todo)
    {:noreply, assign(socket, :todos, todos)}
  end

  @impl true
  def handle_event("edit_journal_entry", %{"id" => id}, socket) do
    entry = Repo.get!(JournalEntry, String.to_integer(id))
    
    {:noreply,
     socket
     |> assign(:editing_entry, entry)
     |> push_event("show_modal", %{id: "edit-journal-modal"})}
  end

  @impl true
  def handle_event("update_journal_entry", %{"id" => id, "journal_entry" => params}, socket) do
    entry = Repo.get!(JournalEntry, String.to_integer(id))
    
    case WorkspaceService.update_journal_entry(entry, params) do
      {:ok, updated_entry} ->
        entries = socket.assigns.journal_entries
                  |> Enum.map(fn e -> 
                    if e.id == updated_entry.id, do: updated_entry, else: e
                  end)
        
        {:noreply,
         socket
         |> assign(:journal_entries, entries)
         |> assign(:editing_entry, nil)
         |> push_event("hide_modal", %{id: "edit-journal-modal"})
         |> put_flash(:info, "Journal entry updated successfully")}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error updating journal entry")}
    end
  end

  @impl true
  def handle_event("edit_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, String.to_integer(id))
    
    {:noreply,
     socket
     |> assign(:editing_todo, todo)
     |> push_event("show_modal", %{id: "edit-todo-modal"})}
  end

  @impl true
  def handle_event("update_todo", %{"id" => id, "todo" => params}, socket) do
    todo = Repo.get!(Todo, String.to_integer(id))
    
    # Clean up empty strings for optional fields
    cleaned_params = params
    |> Map.update("description", nil, fn desc -> if String.trim(desc || "") == "", do: nil, else: desc end)
    |> Map.update("due_date", nil, fn date -> if String.trim(date || "") == "", do: nil, else: date end)
    |> Map.update("due_time", nil, fn time -> if String.trim(time || "") == "", do: nil, else: time end)
    |> process_tags_input()
    
    case WorkspaceService.update_todo(todo, cleaned_params) do
      {:ok, updated_todo} ->
        todos = socket.assigns.todos
                |> Enum.map(fn t -> 
                  if t.id == updated_todo.id, do: updated_todo, else: t
                end)
                |> sort_todos()
        
        {:noreply,
         socket
         |> assign(:todos, todos)
         |> assign(:editing_todo, nil)
         |> push_event("hide_modal", %{id: "edit-todo-modal"})
         |> put_flash(:info, "Todo updated successfully")}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error updating todo")}
    end
  end

  @impl true
  def handle_event("delete_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, String.to_integer(id))
    {:ok, _} = WorkspaceService.delete_todo(todo)
    
    todos = Enum.reject(socket.assigns.todos, &(&1.id == String.to_integer(id)))
    {:noreply, 
     socket
     |> assign(:todos, todos)
     |> put_flash(:info, "Todo deleted successfully")}
  end

  @impl true
  def handle_event("send_chat_message", %{"message" => message}, socket) do
    # Get or create conversation with workspace support
    {:ok, conversation} = case socket.assigns.current_conversation do
      nil ->
        title = LifeOrg.Conversation.generate_title_from_message(message)
        WorkspaceService.create_conversation(%{"title" => title}, socket.assigns.current_workspace.id)
      current_conv ->
        {:ok, current_conv}
    end
    
    # Add user message to database
    {:ok, _user_message} = ConversationService.add_message_to_conversation(
      conversation.id, "user", message
    )
    
    # Load fresh messages from database
    conversation_with_messages = ConversationService.get_conversation_with_messages(conversation.id)
    display_messages = Enum.map(conversation_with_messages.chat_messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
    
    # Add loading indicator
    loading_message = %{role: "assistant", content: "Thinking...", loading: true}
    messages_with_loading = display_messages ++ [loading_message]
    
    # Process asynchronously
    parent_pid = self()
    conversation_history = ConversationService.get_conversation_messages_for_ai(conversation.id)
    
    # Use filtered todos if tag filter is active, otherwise use all todos
    todos_for_ai = filter_todos_by_tag(socket.assigns.todos, socket.assigns.tag_filter)
    
    Task.start(fn ->
      try do
        IO.puts("Starting AI request...")
        case AIHandler.process_message(message, socket.assigns.journal_entries, todos_for_ai, conversation_history) do
          {:ok, response, tool_actions} ->
            IO.puts("AI response received: #{inspect(response)}")
            send(parent_pid, {:ai_response, response, tool_actions, conversation.id})
          {:error, error} ->
            IO.puts("AI error: #{inspect(error)}")
            send(parent_pid, {:ai_error, error})
        end
      rescue
        error ->
          IO.puts("Task error: #{inspect(error)}")
          send(parent_pid, {:ai_error, "Unexpected error: #{inspect(error)}"})
      end
    end)
    
    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:chat_messages, messages_with_loading)
     |> assign(:processing_message, true)}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_conversation, nil)
     |> assign(:chat_messages, [])
     |> assign(:ai_sidebar_view, :chat)}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    conversation = ConversationService.get_conversation_with_messages(String.to_integer(id))
    
    display_messages = Enum.map(conversation.chat_messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
    
    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:chat_messages, display_messages)
     |> assign(:ai_sidebar_view, :chat)}
  end

  @impl true
  def handle_event("show_workspace_form", _params, socket) do
    {:noreply, assign(socket, :show_workspace_form, true)}
  end

  @impl true
  def handle_event("hide_workspace_form", _params, socket) do
    {:noreply, assign(socket, :show_workspace_form, false)}
  end

  @impl true
  def handle_event("create_workspace", %{"workspace" => params}, socket) do
    case WorkspaceService.create_workspace(params) do
      {:ok, _workspace} ->
        workspaces = WorkspaceService.list_workspaces()
        {:noreply,
         socket
         |> assign(:workspaces, workspaces)
         |> assign(:show_workspace_form, false)
         |> put_flash(:info, "Workspace created successfully")}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error creating workspace")}
    end
  end

  @impl true
  def handle_event("edit_workspace", %{"id" => id}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id))
    
    {:noreply,
     socket
     |> assign(:editing_workspace, workspace)
     |> push_event("show_modal", %{id: "edit-workspace-modal"})}
  end

  @impl true
  def handle_event("update_workspace", %{"id" => id, "workspace" => params}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id))
    
    case WorkspaceService.update_workspace(workspace, params) do
      {:ok, updated_workspace} ->
        workspaces = WorkspaceService.list_workspaces()
        current_workspace = if socket.assigns.current_workspace.id == updated_workspace.id do
          updated_workspace
        else
          socket.assigns.current_workspace
        end
        
        {:noreply,
         socket
         |> assign(:workspaces, workspaces)
         |> assign(:current_workspace, current_workspace)
         |> assign(:editing_workspace, nil)
         |> push_event("hide_modal", %{id: "edit-workspace-modal"})
         |> put_flash(:info, "Workspace updated successfully")}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error updating workspace")}
    end
  end

  @impl true
  def handle_event("delete_workspace", %{"id" => id}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id))
    
    case WorkspaceService.delete_workspace(workspace) do
      {:ok, _} ->
        workspaces = WorkspaceService.list_workspaces()
        
        # If we deleted the current workspace, switch to default
        current_workspace = if socket.assigns.current_workspace.id == workspace.id do
          WorkspaceService.get_default_workspace()
        else
          socket.assigns.current_workspace
        end
        
        # Reload data if workspace changed
        {journal_entries, todos, conversations} = if current_workspace.id != socket.assigns.current_workspace.id do
          {
            WorkspaceService.list_journal_entries(current_workspace.id),
            WorkspaceService.list_todos(current_workspace.id) |> sort_todos(),
            WorkspaceService.list_conversations(current_workspace.id)
          }
        else
          {socket.assigns.journal_entries, socket.assigns.todos, socket.assigns.conversations}
        end
        
        {:noreply,
         socket
         |> assign(:workspaces, workspaces)
         |> assign(:current_workspace, current_workspace)
         |> assign(:journal_entries, journal_entries)
         |> assign(:todos, todos)
         |> assign(:conversations, conversations)
         |> assign(:current_conversation, nil)
         |> assign(:chat_messages, [])
         |> put_flash(:info, "Workspace deleted successfully")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("toggle_ai_sidebar", _params, socket) do
    # When opening sidebar, default to conversations view unless we're in an active chat
    new_view = if !socket.assigns.show_ai_sidebar and length(socket.assigns.chat_messages) == 0 do
      :conversations
    else
      socket.assigns.ai_sidebar_view
    end
    
    {:noreply, 
     socket
     |> assign(:show_ai_sidebar, !socket.assigns.show_ai_sidebar)
     |> assign(:ai_sidebar_view, new_view)}
  end

  @impl true
  def handle_event("ai_sidebar_show_conversations", _params, socket) do
    {:noreply, assign(socket, :ai_sidebar_view, :conversations)}
  end

  @impl true
  def handle_event("ai_sidebar_show_chat", _params, socket) do
    {:noreply, assign(socket, :ai_sidebar_view, :chat)}
  end

  @impl true
  def handle_event("toggle_tag_dropdown", _params, socket) do
    {:noreply, push_event(socket, "toggle_dropdown", %{id: "tag-dropdown"})}
  end

  @impl true
  def handle_event("hide_tag_dropdown", _params, socket) do
    {:noreply, push_event(socket, "hide_dropdown", %{id: "tag-dropdown"})}
  end

  @impl true
  def handle_event("filter_by_tag", %{"tag" => tag}, socket) do
    filter = if tag == "", do: nil, else: tag
    {:noreply, 
     socket
     |> assign(:tag_filter, filter)
     |> push_event("hide_dropdown", %{id: "tag-dropdown"})}
  end

  @impl true
  def handle_event("clear_tag_filter", _params, socket) do
    {:noreply, 
     socket
     |> assign(:tag_filter, nil)
     |> push_event("hide_dropdown", %{id: "tag-dropdown"})}
  end

  @impl true
  def handle_event("accept_incoming_todos", _params, socket) do
    # Move all incoming todos to regular todos list
    new_todos = socket.assigns.todos ++ socket.assigns.incoming_todos
    
    {:noreply,
     socket
     |> assign(:todos, sort_todos(new_todos))
     |> assign(:incoming_todos, [])}
  end

  @impl true
  def handle_event("dismiss_incoming_todos", _params, socket) do
    # Delete all incoming todos
    Enum.each(socket.assigns.incoming_todos, fn todo ->
      WorkspaceService.delete_todo(todo)
    end)
    
    {:noreply, assign(socket, :incoming_todos, [])}
  end

  @impl true
  def handle_event("delete_incoming_todo", %{"id" => id}, socket) do
    todo = Enum.find(socket.assigns.incoming_todos, &(&1.id == String.to_integer(id)))
    if todo do
      WorkspaceService.delete_todo(todo)
      remaining_todos = Enum.reject(socket.assigns.incoming_todos, &(&1.id == todo.id))
      {:noreply, assign(socket, :incoming_todos, remaining_todos)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ai_response, response, tool_actions, conversation_id}, socket) do
    # Save assistant response to database
    {:ok, _assistant_message} = ConversationService.add_message_to_conversation(
      conversation_id, "assistant", response
    )
    
    # Load fresh messages from database
    conversation_with_messages = ConversationService.get_conversation_with_messages(conversation_id)
    display_messages = Enum.map(conversation_with_messages.chat_messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
    
    # Execute tool actions
    updated_todos = Enum.reduce(tool_actions, socket.assigns.todos, fn action, todos ->
      case AIHandler.execute_tool_action(action, socket.assigns.current_workspace.id) do
        {:ok, todo} when action.action == :create_todo ->
          [todo | todos] |> sort_todos()
        {:ok, updated_todo} when action.action == :complete_todo ->
          update_todo_in_list(todos, updated_todo)
        _ ->
          todos
      end
    end)
    
    {:noreply,
     socket
     |> assign(:chat_messages, display_messages)
     |> assign(:todos, updated_todos)
     |> assign(:processing_message, false)}
  end

  @impl true
  def handle_info({:ai_error, error}, socket) do
    # Remove loading message and add error
    messages_without_loading = Enum.reject(socket.assigns.chat_messages, &Map.get(&1, :loading, false))
    messages = messages_without_loading ++ [%{role: "assistant", content: error}]
    
    {:noreply,
     socket
     |> assign(:chat_messages, messages)
     |> assign(:processing_message, false)}
  end

  @impl true
  def handle_info({:extracted_todos, todo_actions, workspace_id}, socket) do
    # Only process if we're still in the same workspace
    if socket.assigns.current_workspace.id == workspace_id and length(todo_actions) > 0 do
      # Process all actions and separate new vs updated todos
      {created_todos, updated_todos} = Enum.reduce(todo_actions, {[], socket.assigns.todos}, fn action, {new_acc, todos_acc} ->
        case AIHandler.execute_tool_action(action, workspace_id) do
          {:ok, todo} when action.action == :create_todo ->
            {[todo | new_acc], todos_acc}
          {:ok, updated_todo} when action.action in [:update_todo, :complete_todo] ->
            updated_todos_list = update_todo_in_list(todos_acc, updated_todo)
            {new_acc, updated_todos_list}
          _ ->
            {new_acc, todos_acc}
        end
      end)
      
      # Generate appropriate flash message
      flash_message = case {length(created_todos), length(todo_actions) - length(created_todos)} do
        {0, 0} -> nil
        {new_count, 0} -> "Found #{new_count} new todo(s) from your journal entry!"
        {0, updated_count} -> "Updated #{updated_count} existing todo(s) based on your journal entry!"
        {new_count, updated_count} -> "Found #{new_count} new todo(s) and updated #{updated_count} existing todo(s)!"
      end
      
      socket = socket
      |> assign(:todos, sort_todos(updated_todos))
      |> (fn s -> if length(created_todos) > 0, do: assign(s, :incoming_todos, sort_todos(created_todos)), else: s end).()
      
      if flash_message do
        {:noreply, put_flash(socket, :info, flash_message)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp update_todo_in_list(todos, updated_todo) do
    todos
    |> Enum.map(fn t -> 
      if t.id == updated_todo.id, do: updated_todo, else: t
    end)
    |> sort_todos()
  end
  
  defp sort_todos(todos) do
    Enum.sort_by(todos, fn todo ->
      priority_order = case todo.priority do
        "high" -> 0
        "medium" -> 1
        "low" -> 2
        _ -> 3
      end
      
      # Create a datetime for sorting (nil dates go to end)
      due_datetime = case {todo.due_date, todo.due_time} do
        {nil, _} -> ~N[2099-12-31 23:59:59]  # Far future for todos without due dates
        {date, nil} -> NaiveDateTime.new!(date, ~T[23:59:59])  # End of day if no time specified
        {date, time} -> NaiveDateTime.new!(date, time)
      end
      
      {todo.completed, priority_order, due_datetime, todo.inserted_at}
    end)
  end
  
  defp process_tags_input(params) do
    case Map.get(params, "tags_input") do
      nil ->
        params
      tags_string when is_binary(tags_string) ->
        tags = if String.trim(tags_string) == "" do
          []
        else
          tags_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()
        end
        
        params
        |> Map.put("tags", tags)
        |> Map.delete("tags_input")
    end
  end
  
  defp filter_todos_by_tag(todos, nil), do: todos
  defp filter_todos_by_tag(todos, tag) do
    Enum.filter(todos, fn todo ->
      todo.tags && Enum.member?(todo.tags, tag)
    end)
  end

end