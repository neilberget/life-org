defmodule LifeOrgWeb.OrganizerLive do
  use LifeOrgWeb, :live_view
  import Ecto.Query
  alias LifeOrg.{Repo, JournalEntry, Todo, TodoComment, AIHandler, ConversationService, WorkspaceService}
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
     |> assign(:adding_todo, false)
     |> assign(:editing_workspace, nil)
     |> assign(:show_workspace_form, false)
     |> assign(:show_ai_sidebar, false)
     |> assign(:ai_sidebar_view, :conversations)
     |> assign(:tag_filter, nil)
     |> assign(:viewing_todo, nil)
     |> assign(:todo_comments, [])
     |> assign(:show_comment_form, false)
     |> assign(:processing_journal_todos, false)
     |> assign(:comment_todo_id, nil)
     |> assign(:show_todo_chat, false)
     |> assign(:chat_todo_id, nil)
     |> assign(:todo_chat_messages, [])
     |> assign(:todo_conversations, [])
     |> assign(:current_todo_conversation, nil)
     |> assign(:layout_expanded, nil)
     |> assign(:checkbox_update_trigger, 0)}
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
          {:ok, todo_actions} = AIHandler.extract_todos_from_journal(entry.content, existing_todos, entry.id)
          send(parent_pid, {:extracted_todos, todo_actions, workspace_id})
        end)
        
        {:noreply,
         socket
         |> assign(:journal_entries, entries)
         |> assign(:processing_journal_todos, true)
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
  def handle_event("load_saved_workspace", %{"workspace_id" => workspace_id}, socket) do
    # Try to load the saved workspace, fall back to current if not found
    workspace = 
      case WorkspaceService.get_workspace(String.to_integer(workspace_id)) do
        nil -> socket.assigns.current_workspace
        ws -> ws
      end
    
    if workspace.id != socket.assigns.current_workspace.id do
      # Load data for the saved workspace
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
       |> assign(:tag_filter, nil)
       |> assign(:viewing_todo, nil)
       |> assign(:todo_comments, [])}
    else
      {:noreply, socket}
    end
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
     |> push_event("workspace_changed", %{workspace_id: workspace.id})
     |> assign(:tag_filter, nil)
     |> assign(:viewing_todo, nil)
     |> assign(:todo_comments, [])}
  end

  @impl true
  def handle_event("toggle_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, id)
    {:ok, updated_todo} = WorkspaceService.update_todo(todo, %{completed: !todo.completed})
    
    todos = update_todo_in_list(socket.assigns.todos, updated_todo)
    {:noreply, assign(socket, :todos, todos)}
  end

  @impl true
  def handle_event("toggle_description_checkbox", params, socket) do
    %{"todo-id" => todo_id, "checkbox-index" => checkbox_index, "checked" => checked_str} = params
    todo = Repo.get!(Todo, String.to_integer(todo_id)) |> Repo.preload(:journal_entry)
    
    # checkbox_index might already be an integer from JavaScript
    checkbox_index = if is_integer(checkbox_index), do: checkbox_index, else: String.to_integer(checkbox_index)
    checked = checked_str == "true"
    
    case update_description_checkbox(todo.description, checkbox_index, checked) do
      {:ok, updated_description} ->
        {:ok, updated_todo} = WorkspaceService.update_todo(todo, %{description: updated_description})
        
        # Update both todos list and viewing_todo if it's the same
        todos = update_todo_in_list(socket.assigns.todos, updated_todo)
        
        socket = socket
        |> assign(:todos, todos)
        
        # If we're viewing this todo, update it and keep modal open
        socket = if socket.assigns[:viewing_todo] && socket.assigns.viewing_todo.id == updated_todo.id do
          socket
          |> assign(:viewing_todo, updated_todo)
          |> push_event("checkbox_toggle_complete", %{
            todo_id: todo.id,
            checkbox_index: checkbox_index,
            checked: checked
          })
          |> push_event("show_modal", %{id: "view-todo-modal"})
        else
          socket
          |> push_event("checkbox_toggle_complete", %{
            todo_id: todo.id,
            checkbox_index: checkbox_index,
            checked: checked
          })
        end
        
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update checkbox: #{reason}")}
    end
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
  def handle_event("add_todo", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_todo, true)
     |> push_event("show_modal", %{id: "add-todo-modal"})}
  end

  @impl true
  def handle_event("create_todo", %{"todo" => params}, socket) do
    # Clean up empty strings for optional fields
    cleaned_params = params
    |> Map.update("description", nil, fn desc -> if String.trim(desc || "") == "", do: nil, else: desc end)
    |> Map.update("due_date", nil, fn date -> if String.trim(date || "") == "", do: nil, else: date end)
    |> Map.update("due_time", nil, fn time -> if String.trim(time || "") == "", do: nil, else: time end)
    |> process_tags_input()
    
    case WorkspaceService.create_todo(cleaned_params, socket.assigns.current_workspace.id) do
      {:ok, todo} ->
        todos = [todo | socket.assigns.todos] |> sort_todos()
        
        {:noreply,
         socket
         |> assign(:todos, todos)
         |> assign(:adding_todo, false)
         |> push_event("hide_modal", %{id: "add-todo-modal"})
         |> put_flash(:info, "Todo created successfully")}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error creating todo")}
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
        
        # If we were viewing this todo before editing, return to view modal
        should_return_to_view = socket.assigns[:viewing_todo] != nil || 
                               (socket.assigns[:viewing_todo] == nil && socket.assigns[:editing_todo] && socket.assigns.editing_todo.id == updated_todo.id)

        socket = socket
         |> assign(:todos, todos)
         |> assign(:editing_todo, nil)
         |> push_event("hide_modal", %{id: "edit-todo-modal"})
         |> put_flash(:info, "Todo updated successfully")

        socket = if should_return_to_view do
          # Reload comments for the updated todo
          comments = Repo.all(from c in TodoComment, where: c.todo_id == ^updated_todo.id, order_by: [desc: c.inserted_at])
          |> Repo.preload([])

          socket
          |> assign(:viewing_todo, updated_todo)
          |> assign(:todo_comments, comments)
          |> push_event("show_modal", %{id: "view-todo-modal"})
        else
          socket
        end

        {:noreply, socket}

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
     |> assign(:viewing_todo, nil)
     |> assign(:editing_todo, nil)
     |> assign(:adding_todo, false)
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
  def handle_event("edit_todo_from_view", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, String.to_integer(id))
    
    {:noreply,
     socket
     |> assign(:viewing_todo, nil)
     |> assign(:editing_todo, todo)
     |> push_event("hide_modal", %{id: "view-todo-modal"})
     |> push_event("show_modal", %{id: "edit-todo-modal"})}
  end

  @impl true
  def handle_event("view_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, String.to_integer(id)) |> Repo.preload(:journal_entry)
    comments = Repo.all(from c in TodoComment, where: c.todo_id == ^todo.id, order_by: [desc: c.inserted_at])
    |> Repo.preload([])
    
    {:noreply,
     socket
     |> assign(:viewing_todo, todo)
     |> assign(:todo_comments, comments)
     |> push_event("show_modal", %{id: "view-todo-modal"})}
  end

  @impl true
  def handle_event("show_add_comment_form", %{"todo-id" => todo_id}, socket) do
    
    {:noreply,
     socket
     |> assign(:show_comment_form, true)
     |> assign(:comment_todo_id, String.to_integer(todo_id))
     |> push_event("show_comment_form", %{todo_id: todo_id})}
  end

  @impl true
  def handle_event("hide_add_comment_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_comment_form, false)
     |> assign(:comment_todo_id, nil)
     |> push_event("hide_comment_form", %{})}
  end

  @impl true
  def handle_event("add_todo_comment", %{"todo-id" => todo_id, "comment" => comment_params}, socket) do
    case Repo.insert(TodoComment.changeset(%TodoComment{}, Map.put(comment_params, "todo_id", String.to_integer(todo_id)))) do
      {:ok, _comment} ->
        # Reload comments for the current viewing todo
        comments = Repo.all(from c in TodoComment, where: c.todo_id == ^String.to_integer(todo_id), order_by: [desc: c.inserted_at])
        |> Repo.preload([])

        # Refresh todos list to update comment count
        todos = WorkspaceService.list_todos(socket.assigns.current_workspace.id) |> sort_todos()

        # Make sure the modal stays open by keeping the viewing_todo assigned and explicitly showing it
        {:noreply,
         socket
         |> assign(:todos, todos)
         |> assign(:todo_comments, comments)
         |> assign(:show_comment_form, false)
         |> assign(:comment_todo_id, nil)
         |> push_event("hide_comment_form", %{})
         |> push_event("clear_comment_form", %{todo_id: todo_id})
         |> push_event("show_modal", %{id: "view-todo-modal"})}
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error adding comment")}
    end
  end

  @impl true
  def handle_event("delete_todo_comment", %{"id" => id}, socket) do
    comment = Repo.get!(TodoComment, String.to_integer(id))
    Repo.delete!(comment)
    
    # Refresh todos list to update comment count
    todos = WorkspaceService.list_todos(socket.assigns.current_workspace.id) |> sort_todos()
    
    # Reload comments if we're currently viewing this todo
    if socket.assigns[:viewing_todo] do
      comments = Repo.all(from c in TodoComment, where: c.todo_id == ^socket.assigns.viewing_todo.id, order_by: [desc: c.inserted_at])
      |> Repo.preload([])

      {:noreply, 
       socket
       |> assign(:todos, todos)
       |> assign(:todo_comments, comments)
       |> push_event("show_modal", %{id: "view-todo-modal"})}
    else
      {:noreply, assign(socket, :todos, todos)}
    end
  end

  @impl true
  def handle_event("toggle_todo_chat", %{"id" => todo_id}, socket) do
    current_chat_todo = socket.assigns[:chat_todo_id]
    todo_id_int = String.to_integer(todo_id)
    
    # Ensure viewing_todo is set - if not, reload it
    socket = if socket.assigns[:viewing_todo] == nil do
      todo = Repo.get!(Todo, todo_id_int) |> Repo.preload(:journal_entry)
      comments = Repo.all(from c in TodoComment, where: c.todo_id == ^todo_id_int, order_by: [desc: c.inserted_at])
      |> Repo.preload([])
      socket 
      |> assign(:viewing_todo, todo) 
      |> assign(:todo_comments, comments)
    else
      socket
    end
    
    socket = if current_chat_todo == todo_id_int do
      # Close chat if it's already open for this todo
      socket
      |> assign(:show_todo_chat, false)
      |> assign(:chat_todo_id, nil)
      |> assign(:todo_chat_messages, [])
      |> assign(:todo_conversations, [])
      |> assign(:current_todo_conversation, nil)
    else
      # Open chat for this todo - load existing conversations
      conversations = ConversationService.list_todo_conversations(todo_id_int)
      
      # Load messages from most recent conversation if exists
      messages = case conversations do
        [] -> []
        [conversation | _] ->
          conversation.chat_messages
          |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
      end
      
      socket
      |> assign(:show_todo_chat, true)
      |> assign(:chat_todo_id, todo_id_int)
      |> assign(:todo_conversations, conversations)
      |> assign(:current_todo_conversation, List.first(conversations))
      |> assign(:todo_chat_messages, messages)
    end
    
    {:noreply, socket |> push_event("show_modal", %{id: "view-todo-modal"})}
  end

  @impl true
  def handle_event("expand_todos", _params, socket) do
    {:noreply, assign(socket, :layout_expanded, :todos)}
  end

  @impl true
  def handle_event("expand_journal", _params, socket) do
    {:noreply, assign(socket, :layout_expanded, :journal)}
  end

  @impl true
  def handle_event("return_to_normal_layout", _params, socket) do
    {:noreply, assign(socket, :layout_expanded, nil)}
  end

  @impl true
  def handle_event("send_todo_chat_message", %{"todo-id" => todo_id, "message" => message}, socket) do
    todo_id_int = String.to_integer(todo_id)
    todo = Repo.get!(Todo, todo_id_int) |> Repo.preload(:journal_entry)
    workspace_id = socket.assigns.current_workspace.id
    
    # Get or create conversation for this todo
    conversation = case socket.assigns[:current_todo_conversation] do
      nil ->
        {:ok, conv} = ConversationService.get_or_create_todo_conversation(todo_id_int, workspace_id, message)
        conv
      conv -> conv
    end
    
    # Save user message
    {:ok, _user_msg} = ConversationService.add_message_to_conversation(conversation.id, "user", message)
    
    # Show user message immediately with loading indicator
    current_messages = socket.assigns[:todo_chat_messages] || []
    loading_message = %{role: "assistant", content: "Thinking...", loading: true}
    messages_with_user_and_loading = current_messages ++ [%{role: "user", content: message}, loading_message]
    
    socket = socket 
    |> assign(:todo_chat_messages, messages_with_user_and_loading)
    |> assign(:processing_message, true)
    |> push_event("show_modal", %{id: "view-todo-modal"})
    
    # Start AI processing in background
    parent_pid = self()
    conversation_history = ConversationService.get_conversation_messages_for_ai(conversation.id)
    
    # Get todo comments for context
    todo_comments = Repo.all(from c in TodoComment, where: c.todo_id == ^todo_id_int, order_by: [asc: c.inserted_at])
    |> Repo.preload([])
    
    # Get all todos for context
    all_todos = WorkspaceService.list_todos(workspace_id)
    
    Task.start(fn ->
      try do
        IO.puts("Starting todo-specific AI request...")
        case AIHandler.process_todo_message(message, todo, todo_comments, all_todos, socket.assigns.journal_entries, conversation_history) do
          {:ok, response, tool_actions} ->
            IO.puts("Todo AI response received: #{inspect(response)}")
            send(parent_pid, {:todo_ai_response, response, tool_actions, conversation.id, todo_id_int})
          {:error, error} ->
            IO.puts("Todo AI error: #{inspect(error)}")
            send(parent_pid, {:todo_ai_error, error, conversation.id, todo_id_int})
        end
      rescue
        error ->
          IO.puts("Todo AI task error: #{inspect(error)}")
          send(parent_pid, {:todo_ai_error, "Unexpected error occurred", conversation.id, todo_id_int})
      end
    end)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_todo_conversation", %{"todo-id" => _todo_id, "value" => conversation_id}, socket) do
    conversation_id_int = String.to_integer(conversation_id)
    
    # Find the conversation and load its messages
    conversation = ConversationService.get_conversation_with_messages(conversation_id_int)
    messages = conversation.chat_messages
    |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
    
    {:noreply,
     socket
     |> assign(:current_todo_conversation, conversation)
     |> assign(:todo_chat_messages, messages)
     |> push_event("show_modal", %{id: "view-todo-modal"})}
  end

  @impl true
  def handle_event("create_new_todo_conversation", %{"todo-id" => todo_id}, socket) do
    todo_id_int = String.to_integer(todo_id)
    workspace_id = socket.assigns.current_workspace.id
    
    # Create new conversation with placeholder message
    {:ok, conversation} = ConversationService.create_new_todo_conversation(
      todo_id_int, 
      workspace_id, 
      "New conversation"
    )
    
    # Update conversations list and switch to new conversation
    conversations = ConversationService.list_todo_conversations(todo_id_int)
    
    {:noreply,
     socket
     |> assign(:current_todo_conversation, conversation)
     |> assign(:todo_conversations, conversations)
     |> assign(:todo_chat_messages, [])
     |> push_event("show_modal", %{id: "view-todo-modal"})}
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
          # Preload journal_entry for new todos
          todo_with_journal = Repo.preload(todo, :journal_entry)
          [todo_with_journal | todos] |> sort_todos()
        {:ok, updated_todo} when action.action == :complete_todo ->
          # Preload journal_entry for updated todos
          todo_with_journal = Repo.preload(updated_todo, :journal_entry)
          update_todo_in_list(todos, todo_with_journal)
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
  def handle_info({:reopen_modal, modal_id}, socket) do
    {:noreply, push_event(socket, "show_modal", %{id: modal_id})}
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
  def handle_info({:todo_ai_response, response, tool_actions, conversation_id, todo_id}, socket) do
    # Only save assistant response to database if there's actual content
    # (AI might respond with only tool calls and no text)
    if String.trim(response) != "" do
      {:ok, _assistant_message} = ConversationService.add_message_to_conversation(
        conversation_id, "assistant", response
      )
    end
    
    # Remove loading message
    messages_without_loading = Enum.reject(socket.assigns[:todo_chat_messages] || [], &Map.get(&1, :loading, false))
    
    # Only add response message if there's content, otherwise show action confirmation
    updated_messages = if String.trim(response) != "" do
      messages_without_loading ++ [%{role: "assistant", content: response}]
    else
      # Show a confirmation message for tool-only responses
      action_summary = case tool_actions do
        [] -> "Action completed"
        [%{action: :update_todo}] -> "Todo updated successfully"
        [%{action: :create_todo}] -> "New todo created"
        [%{action: :complete_todo}] -> "Todo marked as complete"
        _ -> "Actions completed"
      end
      messages_without_loading ++ [%{role: "assistant", content: "✓ #{action_summary}"}]
    end
    
    socket = socket
    |> assign(:todo_chat_messages, updated_messages)
    |> assign(:processing_message, false)
    |> push_event("show_modal", %{id: "view-todo-modal"})
    
    # Execute any tool actions for todo operations
    socket = if length(tool_actions) > 0 do
      IO.puts("Executing #{length(tool_actions)} todo tool actions...")
      execute_todo_tool_actions(socket, tool_actions, todo_id)
    else
      socket
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:todo_ai_error, error, _conversation_id, _todo_id}, socket) do
    # Remove loading message and show error
    messages_without_loading = Enum.reject(socket.assigns[:todo_chat_messages] || [], &Map.get(&1, :loading, false))
    error_message = %{role: "assistant", content: "Sorry, I encountered an error: #{error}"}
    updated_messages = messages_without_loading ++ [error_message]
    
    {:noreply,
     socket
     |> assign(:todo_chat_messages, updated_messages)
     |> assign(:processing_message, false)
     |> push_event("show_modal", %{id: "view-todo-modal"})}
  end

  @impl true
  def handle_info({:extracted_todos, todo_actions, workspace_id}, socket) do
    # Only process if we're still in the same workspace
    if socket.assigns.current_workspace.id == workspace_id and length(todo_actions) > 0 do
      # Process all actions and separate new vs updated todos
      {created_todos, updated_todos} = Enum.reduce(todo_actions, {[], socket.assigns.todos}, fn action, {new_acc, todos_acc} ->
        case AIHandler.execute_tool_action(action, workspace_id) do
          {:ok, todo} when action.action == :create_todo ->
            # Preload journal_entry for new todos (especially important since these are created from journal entries)
            todo_with_journal = Repo.preload(todo, :journal_entry)
            {[todo_with_journal | new_acc], todos_acc}
          {:ok, updated_todo} when action.action in [:update_todo, :complete_todo] ->
            # Preload journal_entry for updated todos
            todo_with_journal = Repo.preload(updated_todo, :journal_entry)
            updated_todos_list = update_todo_in_list(todos_acc, todo_with_journal)
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
      |> assign(:processing_journal_todos, false)
      |> (fn s -> if length(created_todos) > 0, do: assign(s, :incoming_todos, sort_todos(created_todos)), else: s end).()
      
      if flash_message do
        {:noreply, put_flash(socket, :info, flash_message)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :processing_journal_todos, false)}
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
  
  defp get_unique_tags(todos) do
    todos
    |> Enum.flat_map(fn todo -> todo.tags || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp execute_todo_tool_actions(socket, tool_actions, _todo_id) do
    updated_todos = Enum.reduce(tool_actions, socket.assigns.todos, fn action, todos ->
      case AIHandler.execute_tool_action(action, socket.assigns.current_workspace.id) do
        {:ok, todo} when action.action == :create_todo ->
          # Preload journal_entry for new todos
          todo_with_journal = Repo.preload(todo, :journal_entry)
          [todo_with_journal | todos] |> sort_todos()
        {:ok, updated_todo} when action.action in [:update_todo, :complete_todo] ->
          # Preload journal_entry for updated todos
          todo_with_journal = Repo.preload(updated_todo, :journal_entry)
          update_todo_in_list(todos, todo_with_journal)
        _ ->
          todos
      end
    end)
    
    # Update the viewing_todo if it was modified
    viewing_todo = case socket.assigns[:viewing_todo] do
      nil -> nil
      current_todo ->
        # Find the updated todo and ensure it has journal_entry preloaded
        case Enum.find(updated_todos, fn todo -> todo.id == current_todo.id end) do
          nil -> current_todo
          found_todo -> Repo.preload(found_todo, :journal_entry)
        end
    end
    
    # Reload todo conversations list since we may have created new todos
    conversations = if socket.assigns[:chat_todo_id] do
      ConversationService.list_todo_conversations(socket.assigns.chat_todo_id)
    else
      socket.assigns[:todo_conversations] || []
    end
    
    socket
    |> assign(:todos, updated_todos)
    |> assign(:viewing_todo, viewing_todo)
    |> assign(:todo_conversations, conversations)
  end

  # Helper function to update a checkbox in todo description markdown
  defp update_description_checkbox(description, checkbox_index, checked) do
    if description && String.trim(description) != "" do
      lines = String.split(description, "\n")
      {updated_lines, _} = Enum.map_reduce(lines, 0, fn line, checkbox_count ->
        if String.contains?(line, "- [") do
          if checkbox_count == checkbox_index do
            # This is the checkbox we want to update
            if checked do
              {String.replace(line, "- [ ]", "- [x]", global: false), checkbox_count + 1}
            else
              {String.replace(line, "- [x]", "- [ ]", global: false), checkbox_count + 1}
            end
          else
            {line, checkbox_count + 1}
          end
        else
          {line, checkbox_count}
        end
      end)
      
      {:ok, Enum.join(updated_lines, "\n")}
    else
      {:error, "No description to update"}
    end
  end

end