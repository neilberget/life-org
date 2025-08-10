defmodule LifeOrgWeb.OrganizerLive do
  use LifeOrgWeb, :live_view
  import Ecto.Query

  on_mount {LifeOrgWeb.UserAuth, :ensure_authenticated}

  alias LifeOrg.{
    Repo,
    JournalEntry,
    Todo,
    TodoComment,
    AIHandler,
    ConversationService,
    WorkspaceService,
    EmbeddingsService
  }

  alias LifeOrgWeb.Components.{JournalComponent, ChatComponent, TodoComponent}

  @impl true
  def mount(params, _session, socket) do
    # Get current user from socket assigns (set by user_auth plug)
    current_user = socket.assigns.current_user
    
    # Ensure user has a default workspace
    {:ok, _} = WorkspaceService.ensure_default_workspace(current_user)
    
    # Get user's workspaces
    current_workspace = WorkspaceService.get_default_workspace(current_user.id)
    workspaces = WorkspaceService.list_workspaces(current_user.id)

    # Load data for current workspace
    journal_entries = WorkspaceService.list_journal_entries(current_workspace.id)
    todos = WorkspaceService.list_todos(current_workspace.id) |> sort_todos()
    conversations = WorkspaceService.list_conversations(current_workspace.id)

    # Handle todo route parameter
    {viewing_todo, todo_comments} =
      case Map.get(params, "id") do
        nil ->
          {nil, []}

        id ->
          case WorkspaceService.get_todo(String.to_integer(id)) do
            nil ->
              {nil, []}

            todo ->
              comments =
                Repo.all(
                  from(c in TodoComment, where: c.todo_id == ^todo.id, order_by: [desc: c.inserted_at])
                )
                |> Repo.preload([])

              {todo, comments}
          end
      end

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
     |> assign(:viewing_todo, viewing_todo)
     |> assign(:todo_comments, todo_comments)
     |> assign(:show_comment_form, false)
     |> assign(:processing_journal_todos, false)
     |> assign(:comment_todo_id, nil)
     |> assign(:show_todo_chat, false)
     |> assign(:chat_todo_id, nil)
     |> assign(:todo_chat_messages, [])
     |> assign(:todo_conversations, [])
     |> assign(:current_todo_conversation, nil)
     |> assign(:show_journal_chat, false)
     |> assign(:chat_journal_id, nil)
     |> assign(:journal_chat_messages, [])
     |> assign(:journal_conversations, [])
     |> assign(:current_journal_conversation, nil)
     |> assign(:layout_expanded, nil)
     |> assign(:ai_chat_expanded, false)
     |> assign(:checkbox_update_trigger, 0)
     |> assign(:deleting_todo_id, nil)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> assign(:searching, false)
     |> assign(:show_completed, false)
     |> then(fn socket ->
       # Show todo modal if viewing a specific todo
       if viewing_todo do
         push_event(socket, "show_modal", %{id: "view-todo-modal"})
       else
         socket
       end
     end)}
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
          case AIHandler.extract_todos_from_journal(entry.content, existing_todos, entry.id, workspace_id, true) do
            {:ok, todo_actions, conversation_messages} ->
              send(parent_pid, {:extracted_todos, todo_actions, workspace_id, entry.id, conversation_messages})
            {:ok, todo_actions} ->
              # Fallback for backward compatibility
              send(parent_pid, {:extracted_todos, todo_actions, workspace_id, entry.id, []})
          end
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
      case WorkspaceService.get_workspace(String.to_integer(workspace_id), socket.assigns.current_user.id) do
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
       |> assign(:todo_comments, [])
       |> assign(:deleting_todo_id, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch_workspace", %{"id" => id}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id), socket.assigns.current_user.id)

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
     |> assign(:todo_comments, [])
     |> assign(:deleting_todo_id, nil)}
  end

  @impl true
  def handle_event("toggle_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, id)
    
    # If marking as completed, also turn off current status
    updates = if !todo.completed do
      %{completed: true, current: false}
    else
      %{completed: false}
    end
    
    {:ok, updated_todo} = WorkspaceService.update_todo(todo, updates)

    todos = update_todo_in_list(socket.assigns.todos, updated_todo)
    {:noreply, assign(socket, :todos, todos)}
  end

  @impl true
  def handle_event("toggle_description_checkbox", params, socket) do
    %{"todo-id" => todo_id, "checkbox-index" => checkbox_index, "checked" => checked_str} = params
    
    # Handle "preview" case where we don't have a real todo
    if todo_id == "preview" do
      # For preview mode, we don't persist changes
      {:noreply, socket}
    else
      todo = WorkspaceService.get_todo(String.to_integer(todo_id))

      # checkbox_index might already be an integer from JavaScript
      checkbox_index =
        if is_integer(checkbox_index), do: checkbox_index, else: String.to_integer(checkbox_index)

      checked = checked_str == "true"

      case update_description_checkbox(todo.description, checkbox_index, checked) do
      {:ok, updated_description} ->
        case WorkspaceService.update_todo(todo, %{description: updated_description}) do
          {:ok, updated_todo} ->
            
            # Update both todos list and viewing_todo if it's the same
            todos = update_todo_in_list(socket.assigns.todos, updated_todo)

            socket =
              socket
              |> assign(:todos, todos)

            # If we're viewing this todo, update it and keep modal open
            socket =
              if socket.assigns[:viewing_todo] && socket.assigns.viewing_todo.id == updated_todo.id do
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
          {:error, changeset} ->
            IO.inspect(changeset.errors, label: "Error updating todo")
            {:noreply, put_flash(socket, :error, "Failed to update todo: #{inspect(changeset.errors)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update checkbox: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("process_link_previews", %{"content" => content, "html" => html}, socket) do
    try do
      # Process using existing HTML with interactive checkboxes instead of raw content
      processed_content =
        LifeOrg.Decorators.Pipeline.process_html_safe(
          html,
          content,
          socket.assigns.current_workspace.id,
          %{enable_decorators: true, fetch_timeout: 3000}
        )
      {:reply, %{processed_content: processed_content}, socket}
    rescue
      error ->
        {:reply, %{error: "Processing failed: #{inspect(error)}"}, socket}
    end
  end

  # Fallback for clients that don't send HTML (backwards compatibility)
  def handle_event("process_link_previews", %{"content" => content}, socket) do
    try do
      # Process content with link previews
      link_processed_content =
        LifeOrg.Decorators.Pipeline.process_content_safe(
          content,
          socket.assigns.current_workspace.id,
          %{enable_decorators: true, fetch_timeout: 3000}
        )

      # Also apply checkbox processing (like render_interactive_description does)
      # Convert markdown to HTML first
      html = Earmark.as_html!(link_processed_content)

      # Transform checkboxes to be interactive (using a generic todo_id since we don't have context)
      # process_link_previews is typically called from modal contexts, so use interactive checkboxes
      interactive_html =
        LifeOrgWeb.Components.TodoComponent.make_checkboxes_interactive(html, "preview",
          interactive: true
        )

      {:reply, %{processed_content: interactive_html}, socket}
    rescue
      error ->
        {:reply, %{error: "Processing failed: #{inspect(error)}"}, socket}
    end
  end

  @impl true
  def handle_event("perform_search", %{"query" => query}, socket) do
    if String.trim(query) == "" do
      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:show_search_results, false)
       |> assign(:searching, false)}
    else
      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:searching, true)
       |> perform_vector_search(query)}
    end
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> assign(:searching, false)}
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
        entries =
          socket.assigns.journal_entries
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
    cleaned_params =
      params
      |> Map.update("description", nil, fn desc ->
        if String.trim(desc || "") == "", do: nil, else: desc
      end)
      |> Map.update("due_date", nil, fn date ->
        if String.trim(date || "") == "", do: nil, else: date
      end)
      |> Map.update("due_time", nil, fn time ->
        if String.trim(time || "") == "", do: nil, else: time
      end)
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
    todo = WorkspaceService.get_todo(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:editing_todo, todo)
     |> push_event("show_modal", %{id: "edit-todo-modal"})}
  end

  @impl true
  def handle_event("update_todo", %{"id" => id, "todo" => params}, socket) do
    todo = WorkspaceService.get_todo(String.to_integer(id))

    # Clean up empty strings for optional fields
    cleaned_params =
      params
      |> Map.update("description", nil, fn desc ->
        if String.trim(desc || "") == "", do: nil, else: desc
      end)
      |> Map.update("due_date", nil, fn date ->
        if String.trim(date || "") == "", do: nil, else: date
      end)
      |> Map.update("due_time", nil, fn time ->
        if String.trim(time || "") == "", do: nil, else: time
      end)
      |> process_tags_input()

    case WorkspaceService.update_todo(todo, cleaned_params) do
      {:ok, updated_todo} ->
        todos =
          socket.assigns.todos
          |> Enum.map(fn t ->
            if t.id == updated_todo.id, do: updated_todo, else: t
          end)
          |> sort_todos()

        # If we were viewing this todo before editing, return to view modal
        should_return_to_view =
          socket.assigns[:viewing_todo] != nil ||
            (socket.assigns[:viewing_todo] == nil && socket.assigns[:editing_todo] &&
               socket.assigns.editing_todo.id == updated_todo.id)

        socket =
          socket
          |> assign(:todos, todos)
          |> assign(:editing_todo, nil)
          |> push_event("hide_modal", %{id: "edit-todo-modal"})
          |> put_flash(:info, "Todo updated successfully")

        socket =
          if should_return_to_view do
            # Reload comments for the updated todo
            comments =
              Repo.all(
                from(c in TodoComment,
                  where: c.todo_id == ^updated_todo.id,
                  order_by: [desc: c.inserted_at]
                )
              )
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
  def handle_event("show_delete_confirmation", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_todo_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_delete_todo", _params, socket) do
    {:noreply, assign(socket, :deleting_todo_id, nil)}
  end

  @impl true
  def handle_event("confirm_delete_todo", %{"id" => id}, socket) do
    todo = WorkspaceService.get_todo(String.to_integer(id))
    {:ok, _} = WorkspaceService.delete_todo(todo)

    todos = Enum.reject(socket.assigns.todos, &(&1.id == String.to_integer(id)))

    {:noreply,
     socket
     |> assign(:todos, todos)
     |> assign(:deleting_todo_id, nil)
     |> put_flash(:info, "Todo deleted successfully")}
  end

  @impl true
  def handle_event("delete_todo", %{"id" => id}, socket) do
    # Keep the old event handler for backward compatibility
    todo = WorkspaceService.get_todo(String.to_integer(id))
    {:ok, _} = WorkspaceService.delete_todo(todo)

    todos = Enum.reject(socket.assigns.todos, &(&1.id == String.to_integer(id)))

    {:noreply,
     socket
     |> assign(:todos, todos)
     |> assign(:deleting_todo_id, nil)
     |> put_flash(:info, "Todo deleted successfully")}
  end

  @impl true
  def handle_event("start_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, id)
    {:ok, updated_todo} = WorkspaceService.update_todo(todo, %{current: true})

    todos = update_todo_in_list(socket.assigns.todos, updated_todo)
    {:noreply, assign(socket, :todos, todos)}
  end

  @impl true
  def handle_event("stop_todo", %{"id" => id}, socket) do
    todo = Repo.get!(Todo, id)
    {:ok, updated_todo} = WorkspaceService.update_todo(todo, %{current: false})

    todos = update_todo_in_list(socket.assigns.todos, updated_todo)
    {:noreply, assign(socket, :todos, todos)}
  end

  @impl true
  def handle_event("send_chat_message", %{"message" => message}, socket) do
    # Get or create conversation with workspace support
    {:ok, conversation} =
      case socket.assigns.current_conversation do
        nil ->
          title = LifeOrg.Conversation.generate_title_from_message(message)

          WorkspaceService.create_conversation(
            %{"title" => title},
            socket.assigns.current_workspace.id
          )

        current_conv ->
          {:ok, current_conv}
      end

    # Add user message to database
    {:ok, _user_message} =
      ConversationService.add_message_to_conversation(
        conversation.id,
        "user",
        message
      )

    # Load fresh messages from database
    conversation_with_messages =
      ConversationService.get_conversation_with_messages(conversation.id)

    display_messages =
      Enum.map(conversation_with_messages.chat_messages, fn msg ->
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
        case AIHandler.process_message(
               message,
               socket.assigns.journal_entries,
               todos_for_ai,
               conversation_history,
               socket.assigns.current_workspace.id
             ) do
          {:ok, response, tool_actions} ->
            send(parent_pid, {:ai_response, response, tool_actions, conversation.id})

          {:error, error} ->
            send(parent_pid, {:ai_error, error})
        end
      rescue
        _error ->
          send(parent_pid, {:ai_error, "Unexpected error occurred"})
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

    display_messages =
      Enum.map(conversation.chat_messages, fn msg ->
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
    params = Map.put(params, "user_id", socket.assigns.current_user.id)
    case WorkspaceService.create_workspace(params) do
      {:ok, _workspace} ->
        workspaces = WorkspaceService.list_workspaces(socket.assigns.current_user.id)

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
    workspace = WorkspaceService.get_workspace!(String.to_integer(id), socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:editing_workspace, workspace)
     |> push_event("show_modal", %{id: "edit-workspace-modal"})}
  end

  @impl true
  def handle_event("update_workspace", %{"id" => id, "workspace" => params}, socket) do
    workspace = WorkspaceService.get_workspace!(String.to_integer(id), socket.assigns.current_user.id)

    case WorkspaceService.update_workspace(workspace, params) do
      {:ok, updated_workspace} ->
        workspaces = WorkspaceService.list_workspaces(socket.assigns.current_user.id)

        current_workspace =
          if socket.assigns.current_workspace.id == updated_workspace.id do
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
    workspace = WorkspaceService.get_workspace!(String.to_integer(id), socket.assigns.current_user.id)

    case WorkspaceService.delete_workspace(workspace) do
      {:ok, _} ->
        workspaces = WorkspaceService.list_workspaces(socket.assigns.current_user.id)

        # If we deleted the current workspace, switch to default
        current_workspace =
          if socket.assigns.current_workspace.id == workspace.id do
            WorkspaceService.get_default_workspace(socket.assigns.current_user.id)
          else
            socket.assigns.current_workspace
          end

        # Reload data if workspace changed
        {journal_entries, todos, conversations} =
          if current_workspace.id != socket.assigns.current_workspace.id do
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
    # Always open in expanded mode
    if socket.assigns.ai_chat_expanded do
      # If expanded, close it
      {:noreply,
       socket
       |> assign(:ai_chat_expanded, false)
       |> assign(:show_ai_sidebar, false)}
    else
      # Open in expanded mode, default to conversations view unless we're in an active chat
      new_view =
        if length(socket.assigns.chat_messages) == 0 do
          :conversations
        else
          :chat
        end
      {:noreply,
       socket
       |> assign(:ai_chat_expanded, true)
       |> assign(:show_ai_sidebar, false)
       |> assign(:ai_sidebar_view, new_view)}
    end
  end

  @impl true
  def handle_event("ai_sidebar_show_conversations", _params, socket) do
    {:noreply,
     socket
     |> assign(:ai_sidebar_view, :conversations)
     |> assign(:show_ai_sidebar, false)
     |> assign(:ai_chat_expanded, true)}
  end

  @impl true
  def handle_event("ai_sidebar_show_chat", _params, socket) do
    {:noreply,
     socket
     |> assign(:ai_sidebar_view, :chat)
     |> assign(:show_ai_sidebar, false)
     |> assign(:ai_chat_expanded, true)}
  end

  @impl true
  def handle_event("toggle_ai_chat_expanded", _params, socket) do
    # This handler is now the same as toggle_ai_sidebar since we always use expanded mode
    handle_event("toggle_ai_sidebar", %{}, socket)
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
     |> assign(:deleting_todo_id, nil)
     |> push_event("hide_dropdown", %{id: "tag-dropdown"})}
  end

  @impl true
  def handle_event("clear_tag_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:tag_filter, nil)
     |> assign(:deleting_todo_id, nil)
     |> push_event("hide_dropdown", %{id: "tag-dropdown"})}
  end

  @impl true
  def handle_event("toggle_show_completed", _params, socket) do
    {:noreply, assign(socket, :show_completed, !socket.assigns.show_completed)}
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
    todo = WorkspaceService.get_todo(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:viewing_todo, nil)
     |> assign(:editing_todo, todo)
     |> push_event("hide_modal", %{id: "view-todo-modal"})
     |> push_event("show_modal", %{id: "edit-todo-modal"})}
  end

  @impl true
  def handle_event("view_todo", %{"id" => id}, socket) do
    todo = WorkspaceService.get_todo(String.to_integer(id))

    comments =
      Repo.all(
        from(c in TodoComment, where: c.todo_id == ^todo.id, order_by: [desc: c.inserted_at])
      )
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
  def handle_event(
        "add_todo_comment",
        %{"todo-id" => todo_id, "comment" => comment_params},
        socket
      ) do
    case Repo.insert(
           TodoComment.changeset(
             %TodoComment{},
             Map.put(comment_params, "todo_id", String.to_integer(todo_id))
           )
         ) do
      {:ok, _comment} ->
        # Reload comments for the current viewing todo
        comments =
          Repo.all(
            from(c in TodoComment,
              where: c.todo_id == ^String.to_integer(todo_id),
              order_by: [desc: c.inserted_at]
            )
          )
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
      comments =
        Repo.all(
          from(c in TodoComment,
            where: c.todo_id == ^socket.assigns.viewing_todo.id,
            order_by: [desc: c.inserted_at]
          )
        )
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
    socket =
      if socket.assigns[:viewing_todo] == nil do
        todo = Repo.get!(Todo, todo_id_int) |> Repo.preload(:journal_entry)

        comments =
          Repo.all(
            from(c in TodoComment,
              where: c.todo_id == ^todo_id_int,
              order_by: [desc: c.inserted_at]
            )
          )
          |> Repo.preload([])

        socket
        |> assign(:viewing_todo, todo)
        |> assign(:todo_comments, comments)
      else
        socket
      end

    socket =
      if current_chat_todo == todo_id_int do
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
        messages =
          case conversations do
            [] ->
              []

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

  def handle_event("view_journal_entry", %{"id" => journal_id}, socket) do
    {:noreply, push_navigate(socket, to: "/journal/#{journal_id}")}
  end

  def handle_event("toggle_journal_chat", %{"id" => journal_id}, socket) do
    current_chat_journal = socket.assigns[:chat_journal_id]
    journal_id_int = String.to_integer(journal_id)

    socket =
      if current_chat_journal == journal_id_int do
        # Close chat if it's already open for this journal
        socket
        |> assign(:show_journal_chat, false)
        |> assign(:chat_journal_id, nil)
        |> assign(:journal_chat_messages, [])
        |> assign(:journal_conversations, [])
        |> assign(:current_journal_conversation, nil)
      else
        # Open chat for this journal - load existing conversations
        conversations = ConversationService.list_journal_conversations(journal_id_int)

        # Load messages from most recent conversation if exists
        messages =
          case conversations do
            [] ->
              []

            [conversation | _] ->
              conversation.chat_messages
              |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
          end

        socket
        |> assign(:show_journal_chat, true)
        |> assign(:chat_journal_id, journal_id_int)
        |> assign(:journal_conversations, conversations)
        |> assign(:current_journal_conversation, List.first(conversations))
        |> assign(:journal_chat_messages, messages)
      end

    {:noreply, socket}
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
  def handle_event(
        "send_todo_chat_message",
        %{"todo-id" => todo_id, "message" => message},
        socket
      ) do
    todo_id_int = String.to_integer(todo_id)
    todo = Repo.get!(Todo, todo_id_int) |> Repo.preload(:journal_entry)
    workspace_id = socket.assigns.current_workspace.id

    # Get or create conversation for this todo
    conversation =
      case socket.assigns[:current_todo_conversation] do
        nil ->
          {:ok, conv} =
            ConversationService.get_or_create_todo_conversation(
              todo_id_int,
              workspace_id,
              message
            )

          conv

        conv ->
          conv
      end

    # Save user message
    {:ok, _user_msg} =
      ConversationService.add_message_to_conversation(conversation.id, "user", message)

    # Show user message immediately with loading indicator
    current_messages = socket.assigns[:todo_chat_messages] || []
    loading_message = %{role: "assistant", content: "Thinking...", loading: true}

    messages_with_user_and_loading =
      current_messages ++ [%{role: "user", content: message}, loading_message]

    socket =
      socket
      |> assign(:todo_chat_messages, messages_with_user_and_loading)
      |> assign(:processing_message, true)
      |> push_event("show_modal", %{id: "view-todo-modal"})

    # Start AI processing in background
    parent_pid = self()
    conversation_history = ConversationService.get_conversation_messages_for_ai(conversation.id)

    # Get todo comments for context
    todo_comments =
      Repo.all(
        from(c in TodoComment, where: c.todo_id == ^todo_id_int, order_by: [asc: c.inserted_at])
      )
      |> Repo.preload([])

    # Get all todos for context
    all_todos = WorkspaceService.list_todos(workspace_id)

    Task.start(fn ->
      try do
        case AIHandler.process_todo_message(
               message,
               todo,
               todo_comments,
               all_todos,
               socket.assigns.journal_entries,
               conversation_history,
               workspace_id
             ) do
          {:ok, response, tool_actions} ->
            send(
              parent_pid,
              {:todo_ai_response, response, tool_actions, conversation.id, todo_id_int}
            )

          {:error, error} ->
            send(parent_pid, {:todo_ai_error, error, conversation.id, todo_id_int})
        end
      rescue
        _error ->
          send(
            parent_pid,
            {:todo_ai_error, "Unexpected error occurred", conversation.id, todo_id_int}
          )
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "send_journal_chat_message",
        %{"journal-id" => journal_id, "message" => message},
        socket
      ) do
    journal_id_int = String.to_integer(journal_id)
    journal_entry = Repo.get!(JournalEntry, journal_id_int)
    workspace_id = socket.assigns.current_workspace.id

    # Get or create conversation for this journal entry
    conversation =
      case socket.assigns[:current_journal_conversation] do
        nil ->
          {:ok, conv} =
            ConversationService.get_or_create_journal_conversation(
              journal_id_int,
              workspace_id,
              message
            )

          conv

        conv ->
          conv
      end

    # Save user message
    {:ok, _user_msg} =
      ConversationService.add_message_to_conversation(conversation.id, "user", message)

    # Show user message immediately with loading indicator
    current_messages = socket.assigns[:journal_chat_messages] || []
    loading_message = %{role: "assistant", content: "Thinking...", loading: true}

    messages_with_user_and_loading =
      current_messages ++ [%{role: "user", content: message}, loading_message]

    socket =
      socket
      |> assign(:journal_chat_messages, messages_with_user_and_loading)
      |> assign(:processing_message, true)

    # Start AI processing in background
    parent_pid = self()
    conversation_history = ConversationService.get_conversation_messages_for_ai(conversation.id)

    # Get related todos for context
    related_todos = WorkspaceService.list_journal_todos(journal_id_int)
    all_todos = WorkspaceService.list_todos(workspace_id)

    Task.start(fn ->
      try do
        case AIHandler.process_journal_message(
               message,
               journal_entry,
               related_todos,
               all_todos,
               socket.assigns.journal_entries,
               conversation_history,
               workspace_id
             ) do
          {:ok, response, tool_actions} ->
            send(
              parent_pid,
              {:journal_ai_response, response, tool_actions, conversation.id, journal_id_int}
            )

          {:error, error} ->
            send(parent_pid, {:journal_ai_error, error, conversation.id, journal_id_int})
        end
      rescue
        _error ->
          send(
            parent_pid,
            {:journal_ai_error, "Unexpected error occurred", conversation.id, journal_id_int}
          )
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "switch_journal_conversation",
        %{"journal-id" => _journal_id, "value" => conversation_id},
        socket
      ) do
    conversation_id_int = String.to_integer(conversation_id)
    
    # Load the selected conversation with messages
    conversation = ConversationService.get_conversation_with_messages(conversation_id_int)
    
    if conversation do
      messages = 
        conversation.chat_messages
        |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
      
      socket = 
        socket
        |> assign(:current_journal_conversation, conversation)
        |> assign(:journal_chat_messages, messages)
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "switch_todo_conversation",
        %{"todo-id" => _todo_id, "value" => conversation_id},
        socket
      ) do
    conversation_id_int = String.to_integer(conversation_id)

    # Find the conversation and load its messages
    conversation = ConversationService.get_conversation_with_messages(conversation_id_int)

    messages =
      conversation.chat_messages
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
    {:ok, conversation} =
      ConversationService.create_new_todo_conversation(
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
    {:ok, _assistant_message} =
      ConversationService.add_message_to_conversation(
        conversation_id,
        "assistant",
        response
      )

    # Load fresh messages from database
    conversation_with_messages =
      ConversationService.get_conversation_with_messages(conversation_id)

    display_messages =
      Enum.map(conversation_with_messages.chat_messages, fn msg ->
        %{role: msg.role, content: msg.content}
      end)

    # Execute tool actions for UI updates (tools were already executed in AI handler)
    updated_todos =
      Enum.reduce(tool_actions, socket.assigns.todos, fn action, todos ->
        case action.action do
          :create_todo ->
            # Find the created todo by title (since it was already created in AI handler)
            case Enum.find(WorkspaceService.list_todos(socket.assigns.current_workspace.id), fn todo ->
              todo.title == action.title && todo.ai_generated
            end) do
              nil -> todos  # Todo not found, skip
              todo ->
                todo_with_journal = Repo.preload(todo, :journal_entry)
                [todo_with_journal | todos] |> sort_todos()
            end
            
          :update_todo ->
            # Reload the updated todo
            case Repo.get(Todo, action.id) do
              nil -> todos
              todo ->
                todo_with_journal = Repo.preload(todo, :journal_entry)
                update_todo_in_list(todos, todo_with_journal)
            end
            
          :complete_todo ->
            # Reload the completed todo
            case Repo.get(Todo, action.id) do
              nil -> todos
              todo ->
                todo_with_journal = Repo.preload(todo, :journal_entry)
                update_todo_in_list(todos, todo_with_journal)
            end
            
          :delete_todo ->
            remove_todo_from_list(todos, action.id)
            
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
    messages_without_loading =
      Enum.reject(socket.assigns.chat_messages, &Map.get(&1, :loading, false))

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
      {:ok, _assistant_message} =
        ConversationService.add_message_to_conversation(
          conversation_id,
          "assistant",
          response
        )
    end

    # Remove loading message
    messages_without_loading =
      Enum.reject(socket.assigns[:todo_chat_messages] || [], &Map.get(&1, :loading, false))

    # Only add response message if there's content, otherwise show action confirmation
    updated_messages =
      if String.trim(response) != "" do
        messages_without_loading ++ [%{role: "assistant", content: response}]
      else
        # Show a confirmation message for tool-only responses
        action_summary =
          case tool_actions do
            [] -> "Action completed"
            [%{action: :update_todo}] -> "Todo updated successfully"
            [%{action: :create_todo}] -> "New todo created"
            [%{action: :complete_todo}] -> "Todo marked as complete"
            _ -> "Actions completed"
          end

        messages_without_loading ++ [%{role: "assistant", content: "✓ #{action_summary}"}]
      end

    socket =
      socket
      |> assign(:todo_chat_messages, updated_messages)
      |> assign(:processing_message, false)
      |> push_event("show_modal", %{id: "view-todo-modal"})

    # Execute tool actions for UI updates (tools were already executed in AI handler)
    if length(tool_actions) > 0 do
      updated_socket = execute_todo_tool_actions_for_ui(socket, tool_actions, todo_id)
      {:noreply, updated_socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:todo_ai_error, error, _conversation_id, _todo_id}, socket) do
    # Remove loading message and show error
    messages_without_loading =
      Enum.reject(socket.assigns[:todo_chat_messages] || [], &Map.get(&1, :loading, false))

    error_message = %{role: "assistant", content: "Sorry, I encountered an error: #{error}"}
    updated_messages = messages_without_loading ++ [error_message]

    {:noreply,
     socket
     |> assign(:todo_chat_messages, updated_messages)
     |> assign(:processing_message, false)
     |> push_event("show_modal", %{id: "view-todo-modal"})}
  end

  @impl true
  def handle_info({:journal_ai_response, response, tool_actions, conversation_id, journal_id}, socket) do
    # Only save assistant response to database if there's actual content
    if String.trim(response) != "" do
      {:ok, _assistant_message} =
        ConversationService.add_message_to_conversation(
          conversation_id,
          "assistant",
          response
        )
    end

    # Remove loading message
    messages_without_loading =
      Enum.reject(socket.assigns[:journal_chat_messages] || [], &Map.get(&1, :loading, false))

    # Only add response message if there's content, otherwise show action confirmation
    updated_messages =
      if String.trim(response) != "" do
        messages_without_loading ++ [%{role: "assistant", content: response}]
      else
        # Show a confirmation message for tool-only responses
        action_summary =
          case tool_actions do
            [] -> "Action completed"
            [%{action: :update_todo}] -> "Todo updated successfully"
            [%{action: :create_todo}] -> "New todo created"
            [%{action: :complete_todo}] -> "Todo marked as complete"
            _ -> "Actions completed"
          end

        messages_without_loading ++ [%{role: "assistant", content: "✓ #{action_summary}"}]
      end

    socket =
      socket
      |> assign(:journal_chat_messages, updated_messages)
      |> assign(:processing_message, false)

    # Execute tool actions for UI updates (tools were already executed in AI handler)
    if length(tool_actions) > 0 do
      updated_socket = execute_journal_tool_actions_for_ui(socket, tool_actions, journal_id)
      {:noreply, updated_socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:journal_ai_error, error, _conversation_id, _journal_id}, socket) do
    # Remove loading message and show error
    messages_without_loading =
      Enum.reject(socket.assigns[:journal_chat_messages] || [], &Map.get(&1, :loading, false))

    error_message = %{role: "assistant", content: "Sorry, I encountered an error: #{error}"}
    updated_messages = messages_without_loading ++ [error_message]

    {:noreply,
     socket
     |> assign(:journal_chat_messages, updated_messages)
     |> assign(:processing_message, false)}
  end

  @impl true
  def handle_info({:extracted_todos, todo_actions, workspace_id, journal_entry_id, conversation_messages}, socket) do
    # Only process if we're still in the same workspace
    if socket.assigns.current_workspace.id == workspace_id do
      # If no actions are returned, the enhanced pipeline may have created todos directly
      # In this case, refresh the todos list from the database
      if length(todo_actions) == 0 do
        # Refresh todos from database in case they were created directly by the AI pipeline
        updated_todos = WorkspaceService.list_todos(workspace_id) |> sort_todos()
        
        # Check if any new todos were actually created by comparing with current list
        current_todo_ids = Enum.map(socket.assigns.todos, & &1.id) |> MapSet.new()
        new_todos = Enum.filter(updated_todos, fn todo -> 
          not MapSet.member?(current_todo_ids, todo.id) and todo.ai_generated
        end)
        
        flash_message = case length(new_todos) do
          0 -> "No new todos extracted from journal entry."
          1 -> "1 todo extracted from journal entry."
          n -> "#{n} todos extracted from journal entry."
        end

        # Create conversation for journal entry with the full AI conversation history
        if length(new_todos) > 0 and length(conversation_messages) > 0 do
          # Create the conversation with a descriptive title
          title = "Todo Extraction - #{Date.to_string(Date.utc_today())}"
          {:ok, conversation} = ConversationService.create_conversation(
            title, 
            workspace_id, 
            nil,
            journal_entry_id
          )
          
          # Save all conversation messages except system prompt
          user_and_assistant_messages = Enum.filter(conversation_messages, fn msg ->
            msg.role in ["user", "assistant"]
          end)
          
          Enum.each(user_and_assistant_messages, fn msg ->
            ConversationService.add_message_to_conversation(conversation.id, msg.role, msg.content)
          end)
        end
        
        {:noreply,
         socket
         |> assign(:todos, updated_todos)
         |> assign(:processing_journal_todos, false)
         |> (fn s ->
              if length(new_todos) > 0,
                do: assign(s, :incoming_todos, sort_todos(new_todos)),
                else: s
            end).()
         |> put_flash(:info, flash_message)}
      else
        # Original logic for when actions are returned
        # Process all actions and separate new vs updated todos
        {created_todos, updated_todos} =
          Enum.reduce(todo_actions, {[], socket.assigns.todos}, fn action, {new_acc, todos_acc} ->
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

              {:ok, _deleted_todo} when action.action == :delete_todo ->
                updated_todos_list = remove_todo_from_list(todos_acc, action.id)
                {new_acc, updated_todos_list}

              _ ->
                {new_acc, todos_acc}
            end
          end)

        # Generate appropriate flash message
        flash_message =
          case {length(created_todos), length(todo_actions) - length(created_todos)} do
            {0, 0} ->
              nil

            {new_count, 0} ->
              "Found #{new_count} new todo(s) from your journal entry!"

            {0, updated_count} ->
              "Updated #{updated_count} existing todo(s) based on your journal entry!"

            {new_count, updated_count} ->
              "Found #{new_count} new todo(s) and updated #{updated_count} existing todo(s)!"
          end

        socket =
          socket
          |> assign(:todos, sort_todos(updated_todos))
          |> assign(:processing_journal_todos, false)
          |> (fn s ->
                if length(created_todos) > 0,
                  do: assign(s, :incoming_todos, sort_todos(created_todos)),
                  else: s
              end).()

        # Create conversation for journal entry if any todos were created or updated
        if length(todo_actions) > 0 do
          extraction_summary = "I analyzed your journal entry and made #{length(todo_actions)} todo action(s). You can continue our conversation about this journal entry here."
          ConversationService.create_journal_extraction_conversation(journal_entry_id, workspace_id, extraction_summary)
        end

        if flash_message do
          {:noreply, put_flash(socket, :info, flash_message)}
        else
          {:noreply, socket}
        end
      end
    else
      {:noreply, assign(socket, :processing_journal_todos, false)}
    end
  end
  
  # Fallback pattern for backward compatibility with old format
  @impl true
  def handle_info({:extracted_todos, todo_actions, workspace_id, journal_entry_id}, socket) do
    # Call the main handler with empty conversation messages
    handle_info({:extracted_todos, todo_actions, workspace_id, journal_entry_id, []}, socket)
  end

  defp update_todo_in_list(todos, updated_todo) do
    todos
    |> Enum.map(fn t ->
      if t.id == updated_todo.id, do: updated_todo, else: t
    end)
    |> sort_todos()
  end

  defp remove_todo_from_list(todos, todo_id) do
    todos
    |> Enum.reject(fn t -> t.id == todo_id end)
  end

  defp sort_todos(todos) do
    Enum.sort_by(todos, fn todo ->
      priority_order =
        case todo.priority do
          "high" -> 0
          "medium" -> 1
          "low" -> 2
          _ -> 3
        end

      # Create a datetime for sorting (nil dates go to end)
      due_datetime =
        case {todo.due_date, todo.due_time} do
          # Far future for todos without due dates
          {nil, _} -> ~N[2099-12-31 23:59:59]
          # End of day if no time specified
          {date, nil} -> NaiveDateTime.new!(date, ~T[23:59:59])
          {date, time} -> NaiveDateTime.new!(date, time)
        end

      # Sort by: completed status, then current status (current first), then priority, then due date, then insertion date
      {todo.completed, !todo.current, priority_order, due_datetime, todo.inserted_at}
    end)
  end

  defp process_tags_input(params) do
    case Map.get(params, "tags_input") do
      nil ->
        params

      tags_string when is_binary(tags_string) ->
        tags =
          if String.trim(tags_string) == "" do
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


  # Simple UI update function for todo tool actions  
  defp execute_todo_tool_actions_for_ui(socket, _tool_actions, _todo_id) do
    # Reload todos from database since tools were already executed in AI handler
    updated_todos = WorkspaceService.list_todos(socket.assigns.current_workspace.id) |> sort_todos()

    # Update the viewing_todo if it was modified, or clear it if it was deleted
    {viewing_todo, socket_with_events} =
      case socket.assigns[:viewing_todo] do
        nil ->
          {nil, socket}

        current_todo ->
          # Find the updated todo and ensure it has journal_entry preloaded
          case Enum.find(updated_todos, fn todo -> todo.id == current_todo.id end) do
            nil ->
              # Todo was deleted, close the modal
              {nil, push_event(socket, "hide_modal", %{id: "view-todo-modal"})}
            found_todo ->
              {Repo.preload(found_todo, :journal_entry), socket}
          end
      end

    # Reload todo conversations list since we may have created new todos
    conversations =
      if socket.assigns[:chat_todo_id] do
        ConversationService.list_todo_conversations(socket.assigns.chat_todo_id)
      else
        socket.assigns[:todo_conversations] || []
      end

    socket_with_events
    |> assign(:todos, updated_todos)
    |> assign(:viewing_todo, viewing_todo)
    |> assign(:todo_conversations, conversations)
  end

  defp execute_journal_tool_actions_for_ui(socket, _tool_actions, _journal_id) do
    # Reload todos from database since tools were already executed in AI handler
    updated_todos = WorkspaceService.list_todos(socket.assigns.current_workspace.id) |> sort_todos()

    # Reload journal conversations list since we may have created new todos
    conversations =
      if socket.assigns[:chat_journal_id] do
        ConversationService.list_journal_conversations(socket.assigns.chat_journal_id)
      else
        socket.assigns[:journal_conversations] || []
      end

    socket
    |> assign(:todos, updated_todos)
    |> assign(:journal_conversations, conversations)
  end

  # Helper function to update a checkbox in todo description markdown
  defp update_description_checkbox(description, checkbox_index, checked) do
    if description && String.trim(description) != "" do
      lines = String.split(description, "\n")

      {updated_lines, _} =
        Enum.map_reduce(lines, 0, fn line, checkbox_count ->
          # Only count actual checkboxes ([ ] or [x]), not other patterns like [TEST]
          if String.match?(line, ~r/- \[(x|\s*)\]/i) do
            if checkbox_count == checkbox_index do
              # This is the checkbox we want to update
              updated_line = 
                if checked do
                  # Set to checked - handle both [ ] and [x] cases
                  line
                  |> String.replace(~r/- \[\s*\]/, "- [x]", global: false)
                  |> String.replace(~r/- \[x\]/i, "- [x]", global: false)
                else
                  # Set to unchecked - handle both [ ] and [x] cases  
                  line
                  |> String.replace(~r/- \[x\]/i, "- [ ]", global: false)
                  |> String.replace(~r/- \[\s*\]/, "- [ ]", global: false)
                end
              {updated_line, checkbox_count + 1}
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

  defp perform_vector_search(socket, query) do
    case EmbeddingsService.search_all(query, workspace_id: socket.assigns.current_workspace.id, limit: 15) do
      {:ok, results} ->
        socket
        |> assign(:search_results, results)
        |> assign(:show_search_results, true)
        |> assign(:searching, false)

      {:error, :no_api_key} ->
        socket
        |> assign(:search_results, [])
        |> assign(:show_search_results, false)
        |> assign(:searching, false)
        |> put_flash(:error, "Vector search requires OpenAI API key")

      {:error, reason} ->
        socket
        |> assign(:search_results, [])
        |> assign(:show_search_results, false)
        |> assign(:searching, false)
        |> put_flash(:error, "Search failed: #{inspect(reason)}")
    end
  end
end
