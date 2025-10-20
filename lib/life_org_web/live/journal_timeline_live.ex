defmodule LifeOrgWeb.JournalTimelineLive do
  use LifeOrgWeb, :live_view

  on_mount {LifeOrgWeb.UserAuth, :ensure_authenticated}

  alias LifeOrg.WorkspaceService
  alias LifeOrg.AIHandler
  alias LifeOrg.ConversationService
  alias LifeOrg.AttachmentService
  alias LifeOrg.Repo
  alias LifeOrg.JournalEntry

  @impl true
  def handle_params(params, _url, socket) do
    # Skip if we haven't finished mounting yet
    if !Map.has_key?(socket.assigns, :journal_entries) do
      {:noreply, socket}
    else
      # Handle URL parameter changes when navigating
      requested_entry_id = case params["id"] do
        nil -> nil
        id_str -> String.to_integer(id_str)
      end

      # If we have a specific entry ID and it's different from current selection
      if requested_entry_id && (!socket.assigns[:selected_entry] || socket.assigns.selected_entry.id != requested_entry_id) do
        # Find and select the entry
        case Enum.find(socket.assigns.journal_entries, &(&1.id == requested_entry_id)) do
        nil ->
          {:noreply, socket}
        entry ->
          # Load the entry's data
          related_todos = WorkspaceService.list_journal_todos(entry.id)
          conversations = ConversationService.list_journal_conversations(entry.id)
          messages =
            case conversations do
              [] -> []
              [conversation | _] ->
                conversation.chat_messages
                |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
            end
          
          {:noreply,
           socket
           |> assign(:selected_entry, entry)
           |> assign(:related_todos, related_todos)
           |> assign(:show_todos_section, false)
           |> assign(:todos_section_journal_id, nil)
           |> assign(:show_journal_chat, true)
           |> assign(:chat_journal_id, entry.id)
           |> assign(:chat_journal_entry, entry)
           |> assign(:journal_conversations, conversations)
           |> assign(:current_journal_conversation, List.first(conversations))
           |> assign(:journal_chat_messages, messages)
           |> push_event("scroll_to_entry", %{entry_id: entry.id})}
        end
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def mount(params, _session, socket) do
    current_user = socket.assigns.current_user
    
    {:ok, _} = WorkspaceService.ensure_default_workspace(current_user)
    
    current_workspace = WorkspaceService.get_default_workspace(current_user.id)
    workspaces = WorkspaceService.list_workspaces(current_user.id)
    journal_entries = WorkspaceService.list_journal_entries(current_workspace.id)

    # Check if a specific journal ID was provided in params
    requested_entry_id = case params["id"] do
      nil -> nil
      id_str -> String.to_integer(id_str)
    end

    # Auto-select requested entry or first entry if any exist and load its chat
    {selected_entry, related_todos, chat_data, should_scroll} = 
      case {requested_entry_id, journal_entries} do
        {nil, []} -> 
          {nil, [], {false, nil, nil, [], [], nil}, false}
        {nil, [first_entry | _]} -> 
          todos = WorkspaceService.list_journal_todos(first_entry.id)
          conversations = ConversationService.list_journal_conversations(first_entry.id)
          messages =
            case conversations do
              [] -> []
              [conversation | _] ->
                conversation.chat_messages
                |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
            end
          {first_entry, todos, {true, first_entry.id, first_entry, conversations, List.first(conversations), messages}, false}
        {id, entries} ->
          # Find the requested entry
          case Enum.find(entries, &(&1.id == id)) do
            nil -> 
              # Entry not found, fall back to first entry
              case entries do
                [] -> {nil, [], {false, nil, nil, [], [], nil}, false}
                [first_entry | _] -> 
                  todos = WorkspaceService.list_journal_todos(first_entry.id)
                  conversations = ConversationService.list_journal_conversations(first_entry.id)
                  messages =
                    case conversations do
                      [] -> []
                      [conversation | _] ->
                        conversation.chat_messages
                        |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
                    end
                  {first_entry, todos, {true, first_entry.id, first_entry, conversations, List.first(conversations), messages}, false}
              end
            entry ->
              todos = WorkspaceService.list_journal_todos(entry.id)
              conversations = ConversationService.list_journal_conversations(entry.id)
              messages =
                case conversations do
                  [] -> []
                  [conversation | _] ->
                    conversation.chat_messages
                    |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
                end
              {entry, todos, {true, entry.id, entry, conversations, List.first(conversations), messages}, true}
          end
      end
    
    {show_chat, chat_journal_id, chat_journal_entry, conversations, current_conversation, chat_messages} = chat_data
    
    socket =
      socket
      |> assign(:current_workspace, current_workspace)
      |> assign(:workspaces, workspaces)
      |> assign(:journal_entries, journal_entries)
      |> assign(:selected_entry, selected_entry)
      |> assign(:related_todos, related_todos)
      |> assign(:user_timezone, current_user.timezone || "America/Chicago")
      |> assign(:show_add_form, false)
      |> assign(:processing_journal_todos, false)
      |> assign(:show_journal_chat, show_chat)
      |> assign(:chat_journal_id, chat_journal_id)
      |> assign(:chat_journal_entry, chat_journal_entry)
      |> assign(:journal_chat_messages, chat_messages || [])
      |> assign(:journal_conversations, conversations || [])
      |> assign(:current_journal_conversation, current_conversation)
      |> assign(:show_todos_section, false)
      |> assign(:todos_section_journal_id, nil)
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 10,
        max_file_size: 5_000_000
      )
    
    # If we loaded a specific entry, scroll to it after mount
    socket = if should_scroll && selected_entry do
      push_event(socket, "scroll_to_entry_on_mount", %{entry_id: selected_entry.id})
    else
      socket
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, !socket.assigns.show_add_form)}
  end

  @impl true
  def handle_event("create_journal_entry", %{"journal_entry" => params}, socket) do
    case WorkspaceService.create_journal_entry(params, socket.assigns.current_workspace.id) do
      {:ok, entry} ->
        # Refresh journal entries to include the new one
        journal_entries = WorkspaceService.list_journal_entries(socket.assigns.current_workspace.id)
        
        # Extract todos from journal entry in background
        parent_pid = self()
        workspace_id = socket.assigns.current_workspace.id
        existing_todos = WorkspaceService.list_todos(workspace_id)
        
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
         |> assign(:journal_entries, journal_entries)
         |> assign(:show_add_form, false)
         |> assign(:processing_journal_todos, true)
         |> push_event("clear_timeline_journal_form", %{})
         |> put_flash(:info, "Journal entry created successfully")}
         
      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply, put_flash(socket, :error, "Error creating journal entry")}
    end
  end

  @impl true
  def handle_event("select_entry", %{"id" => id}, socket) do
    entry_id = String.to_integer(id)
    selected_entry = Enum.find(socket.assigns.journal_entries, &(&1.id == entry_id))
    
    # Get todos extracted from this journal entry
    related_todos = WorkspaceService.list_journal_todos(entry_id)
    
    # Automatically load chat for the selected entry
    conversations = ConversationService.list_journal_conversations(entry_id)
    messages =
      case conversations do
        [] ->
          []
        [conversation | _] ->
          conversation.chat_messages
          |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
      end
    
    {:noreply,
     socket
     |> assign(:selected_entry, selected_entry)
     |> assign(:related_todos, related_todos)
     |> assign(:show_todos_section, false)
     |> assign(:todos_section_journal_id, nil)
     |> assign(:show_journal_chat, true)
     |> assign(:chat_journal_id, entry_id)
     |> assign(:chat_journal_entry, selected_entry)
     |> assign(:journal_conversations, conversations)
     |> assign(:current_journal_conversation, List.first(conversations))
     |> assign(:journal_chat_messages, messages)
     |> push_event("scroll_to_entry", %{entry_id: entry_id})
     |> push_patch(to: "/journal/#{entry_id}")}
  end

  @impl true
  def handle_event("navigate_timeline", %{"key" => "j"}, socket) do
    # Navigate to next entry
    case get_next_entry(socket.assigns.journal_entries, socket.assigns.selected_entry) do
      nil ->
        {:noreply, socket}
      
      next_entry ->
        related_todos = WorkspaceService.list_journal_todos(next_entry.id)
        
        # Load chat for the new entry
        conversations = ConversationService.list_journal_conversations(next_entry.id)
        messages =
          case conversations do
            [] ->
              []
            [conversation | _] ->
              conversation.chat_messages
              |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
          end
        
        {:noreply,
         socket
         |> assign(:selected_entry, next_entry)
         |> assign(:related_todos, related_todos)
         |> assign(:show_todos_section, false)
         |> assign(:todos_section_journal_id, nil)
         |> assign(:show_journal_chat, true)
         |> assign(:chat_journal_id, next_entry.id)
         |> assign(:chat_journal_entry, next_entry)
         |> assign(:journal_conversations, conversations)
         |> assign(:current_journal_conversation, List.first(conversations))
         |> assign(:journal_chat_messages, messages)
         |> push_event("scroll_to_entry", %{entry_id: next_entry.id})
         |> push_patch(to: "/journal/#{next_entry.id}")}
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
        
        # Load chat for the new entry
        conversations = ConversationService.list_journal_conversations(prev_entry.id)
        messages =
          case conversations do
            [] ->
              []
            [conversation | _] ->
              conversation.chat_messages
              |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
          end
        
        {:noreply,
         socket
         |> assign(:selected_entry, prev_entry)
         |> assign(:related_todos, related_todos)
         |> assign(:show_todos_section, false)
         |> assign(:todos_section_journal_id, nil)
         |> assign(:show_journal_chat, true)
         |> assign(:chat_journal_id, prev_entry.id)
         |> assign(:chat_journal_entry, prev_entry)
         |> assign(:journal_conversations, conversations)
         |> assign(:current_journal_conversation, List.first(conversations))
         |> assign(:journal_chat_messages, messages)
         |> push_event("scroll_to_entry", %{entry_id: prev_entry.id})
         |> push_patch(to: "/journal/#{prev_entry.id}")}
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

  @impl true
  def handle_event("toggle_journal_chat", %{"id" => journal_id}, socket) do
    journal_id_int = String.to_integer(journal_id)
    
    # Always open chat for this journal entry and clear todos section
    journal_entry = Repo.get!(JournalEntry, journal_id_int)
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
    
    socket =
      socket
      |> assign(:show_todos_section, false)
      |> assign(:todos_section_journal_id, nil)
      |> assign(:show_journal_chat, true)
      |> assign(:chat_journal_id, journal_id_int)
      |> assign(:chat_journal_entry, journal_entry)
      |> assign(:journal_conversations, conversations)
      |> assign(:current_journal_conversation, List.first(conversations))
      |> assign(:journal_chat_messages, messages)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_todos_section", _params, socket) do
    selected_entry = socket.assigns.selected_entry
    
    {:noreply,
     socket
     |> assign(:show_todos_section, true)
     |> assign(:todos_section_journal_id, if(selected_entry, do: selected_entry.id, else: nil))
     |> assign(:show_journal_chat, false)
     |> assign(:chat_journal_id, nil)
     |> assign(:chat_journal_entry, nil)
     |> assign(:journal_chat_messages, [])
     |> assign(:journal_conversations, [])
     |> assign(:current_journal_conversation, nil)}
  end

  @impl true
  def handle_event("send_journal_chat_message", %{"journal-id" => journal_id, "message" => message}, socket) do
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
    
    Task.start(fn ->
      # Get current todos and journal entries for AI context
      all_todos = WorkspaceService.list_todos(workspace_id)
      related_todos = WorkspaceService.list_journal_todos(journal_id_int)
      journal_entries = WorkspaceService.list_journal_entries(workspace_id)
      
      case AIHandler.process_journal_message(
             message,
             journal_entry,
             related_todos,
             all_todos,
             journal_entries,
             conversation_history,
             workspace_id
           ) do
        {:ok, response, tool_actions} ->
          send(parent_pid, {:journal_ai_response, response, tool_actions, conversation.id, journal_id_int})
        {:error, reason} ->
          send(parent_pid, {:journal_ai_response, "I'm sorry, I encountered an error: #{reason}", [], conversation.id, journal_id_int})
      end
    end)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_journal_conversation", %{"journal-id" => _journal_id, "value" => conversation_id}, socket) do
    conversation_id_int = String.to_integer(conversation_id)
    # Find the conversation and load its messages
    conversation = ConversationService.get_conversation_with_messages(conversation_id_int)

    messages =
      conversation.chat_messages
      |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)

    {:noreply,
     socket
     |> assign(:current_journal_conversation, conversation)
     |> assign(:journal_chat_messages, messages)}
  end

  @impl true
  def handle_event("upload_image_base64", %{"filename" => filename, "content_type" => content_type, "size" => size, "data" => base64_data}, socket) do
    user_id = socket.assigns.current_user.id
    require Logger
    Logger.info("Received base64 image upload: #{filename}, type: #{content_type}, size: #{size}")

    try do
      # Decode the base64 data (remove data URL prefix if present)
      base64_content = case String.split(base64_data, ",", parts: 2) do
        [_prefix, data] -> data
        [data] -> data
      end

      binary_data = Base.decode64!(base64_content)

      # Create a temporary file
      temp_path = Path.join(System.tmp_dir!(), "upload_#{:erlang.unique_integer()}_#{filename}")
      File.write!(temp_path, binary_data)

      # Save using AttachmentService
      case AttachmentService.save_upload(user_id, %{path: temp_path, filename: filename}) do
        {:ok, saved_filename} ->
          # Create attachment record
          {:ok, attachment} = AttachmentService.create_attachment(%{
            user_id: user_id,
            filename: saved_filename,
            original_filename: filename,
            content_type: content_type,
            file_size: byte_size(binary_data)
          })

          # Clean up temp file
          File.rm(temp_path)

          # Return URL to client
          url = AttachmentService.get_url_path(user_id, saved_filename)
          Logger.info("Image saved successfully: #{url}")

          {:noreply, push_event(socket, "images_uploaded", %{files: [%{url: url, filename: saved_filename, id: attachment.id}]})}

        {:error, reason} ->
          Logger.error("Failed to save image: #{inspect(reason)}")
          File.rm(temp_path)
          {:noreply, socket}
      end
    rescue
      e ->
        Logger.error("Error processing base64 upload: #{inspect(e)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    # Just validate, don't consume yet
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_image", _params, socket) do
    user_id = socket.assigns.current_user.id
    require Logger
    Logger.info("Upload image event received for user #{user_id}")

    # Check if there are any completed uploads ready to consume
    uploaded_files =
      consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
        Logger.info("Processing uploaded file: #{entry.client_name}, type: #{entry.client_type}")

        # Save the file to disk
        case AttachmentService.save_upload(user_id, %{path: path, filename: entry.client_name}) do
          {:ok, filename} ->
            # Get file info
            %{size: file_size} = File.stat!(path)
            Logger.info("File saved successfully: #{filename}, size: #{file_size}")

            # Create attachment record (not linked to any entry yet)
            {:ok, attachment} =
              AttachmentService.create_attachment(%{
                user_id: user_id,
                filename: filename,
                original_filename: entry.client_name,
                content_type: entry.client_type,
                file_size: file_size
              })

            # Return the markdown syntax for the image
            url = AttachmentService.get_url_path(user_id, filename)
            Logger.info("Image URL generated: #{url}")
            {:ok, %{url: url, filename: filename, id: attachment.id}}

          {:error, reason} ->
            Logger.error("Failed to save upload: #{inspect(reason)}")
            {:postpone, reason}
        end
      end)

    Logger.info("Uploaded files count: #{length(uploaded_files)}")
    Logger.info("Files: #{inspect(uploaded_files)}")

    # Only send event if files were actually uploaded
    socket = if length(uploaded_files) > 0 do
      Logger.info("Pushing images_uploaded event with #{length(uploaded_files)} files")
      push_event(socket, "images_uploaded", %{files: uploaded_files})
    else
      Logger.warning("No files were uploaded")
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_info({:journal_ai_response, response, _tool_actions, conversation_id, journal_id}, socket) do
    # Only save assistant response to database if there's actual content
    if String.trim(response) != "" do
      {:ok, _assistant_message} =
        ConversationService.add_message_to_conversation(
          conversation_id,
          "assistant",
          response
        )
    end
    
    # Only update if this is for the current journal chat
    if socket.assigns[:chat_journal_id] == journal_id do
      # Load fresh messages from database
      conversation_with_messages =
        ConversationService.get_conversation_with_messages(conversation_id)
      
      display_messages = 
        conversation_with_messages.chat_messages
        |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
      
      {:noreply,
       socket
       |> assign(:journal_chat_messages, display_messages)
       |> assign(:processing_message, false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:extracted_todos, _todo_actions, workspace_id, _journal_entry_id, _conversation_messages}, socket) do
    # Only update if this is for the current workspace
    if workspace_id == socket.assigns.current_workspace.id do
      {:noreply, assign(socket, :processing_journal_todos, false)}
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