defmodule LifeOrgWeb.JournalEntryLive do
  use LifeOrgWeb, :live_view
  
  alias LifeOrg.{
    Repo, 
    JournalEntry, 
    ConversationService, 
    AIHandler, 
    WorkspaceService
  }
  
  import LifeOrgWeb.MarkdownHelper

  on_mount {LifeOrgWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Repo.get(JournalEntry, String.to_integer(id)) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Journal entry not found")
         |> redirect(to: "/")}

      entry ->
        # Preload associated todos and workspace
        entry = Repo.preload(entry, [:todos, :workspace])
        
        # Load conversations for this journal entry
        conversations = ConversationService.list_journal_conversations(entry.id)
        
        # Load messages from most recent conversation if exists
        {current_conversation, messages} = 
          case conversations do
            [] ->
              {nil, []}
            [conversation | _] ->
              messages = conversation.chat_messages
              |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)
              {conversation, messages}
          end
        
        {:ok,
         socket
         |> assign(:entry, entry)
         |> assign(:related_todos, entry.todos)
         |> assign(:journal_conversations, conversations)
         |> assign(:current_journal_conversation, current_conversation)
         |> assign(:journal_chat_messages, messages)
         |> assign(:processing_message, false)}
    end
  end

  @impl true
  def handle_event("back_to_organizer", _params, socket) do
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def handle_event(
        "send_journal_chat_message",
        %{"message" => message},
        socket
      ) do
    journal_entry = socket.assigns.entry
    workspace_id = journal_entry.workspace_id

    # Get or create conversation for this journal entry
    conversation =
      case socket.assigns[:current_journal_conversation] do
        nil ->
          {:ok, conv} =
            ConversationService.get_or_create_journal_conversation(
              journal_entry.id,
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
      |> assign(:current_journal_conversation, conversation)
      |> assign(:processing_message, true)

    # Start AI processing in background
    parent_pid = self()
    conversation_history = ConversationService.get_conversation_messages_for_ai(conversation.id)

    # Get related todos and all todos for context
    related_todos = WorkspaceService.list_journal_todos(journal_entry.id)
    all_todos = WorkspaceService.list_todos(workspace_id)
    
    # Get all journal entries for context
    journal_entries = WorkspaceService.list_journal_entries(workspace_id)

    Task.start(fn ->
      try do
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
            send(
              parent_pid,
              {:journal_ai_response, response, tool_actions, conversation.id, journal_entry.id}
            )

          {:error, error} ->
            send(parent_pid, {:journal_ai_error, error, conversation.id, journal_entry.id})
        end
      rescue
        _error ->
          send(
            parent_pid,
            {:journal_ai_error, "Unexpected error occurred", conversation.id, journal_entry.id}
          )
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "switch_journal_conversation",
        %{"value" => conversation_id},
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
  def handle_info({:journal_ai_response, response, tool_actions, conversation_id, _journal_id}, socket) do
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

    # Only add response message if there's content
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

    # Execute tool actions for UI updates
    if length(tool_actions) > 0 do
      # Reload related todos since tools may have created/updated them
      entry = Repo.preload(socket.assigns.entry, :todos, force: true)
      
      socket = socket |> assign(:entry, entry) |> assign(:related_todos, entry.todos)
      
      {:noreply, socket}
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
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="flex items-center justify-between">
          <button
            phx-click="back_to_organizer"
            class="inline-flex items-center text-blue-600 hover:text-blue-800 font-medium"
          >
            <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
            Back to Organizer
          </button>
          
          <div class="text-sm text-gray-600">
            <%= if @entry.entry_date do %>
              <%= Calendar.strftime(@entry.entry_date, "%A, %B %d, %Y") %>
            <% else %>
              <%= Calendar.strftime(@entry.inserted_at, "%A, %B %d, %Y") %>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Left Column: Journal Entry -->
        <div class="w-1/2 bg-white border-r border-gray-200 overflow-y-auto p-6">
          <h1 class="text-2xl font-bold text-gray-900 mb-4">Journal Entry</h1>
          
          <!-- Tags -->
          <%= if @entry.tags && length(@entry.tags) > 0 do %>
            <div class="mb-4">
              <%= for tag <- @entry.tags do %>
                <span class="inline-block bg-blue-100 text-blue-800 text-xs px-2 py-1 rounded-full mr-1 mb-1">
                  <%= tag %>
                </span>
              <% end %>
            </div>
          <% end %>

          <!-- Content -->
          <div class="prose max-w-none text-gray-700 mb-6">
            <%= render_markdown(@entry.content) %>
          </div>

          <!-- Related Todos Section -->
          <%= if length(@related_todos) > 0 do %>
            <div class="border-t border-gray-200 pt-6">
              <h2 class="text-xl font-semibold text-gray-900 mb-4 flex items-center">
                <svg class="w-5 h-5 mr-2 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
                </svg>
                Related Todos
              </h2>
              
              <div class="space-y-3">
                <%= for todo <- @related_todos do %>
                  <div class="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 transition-colors">
                    <div class="flex items-start">
                      <%= if todo.completed do %>
                        <span class="inline-flex items-center justify-center w-4 h-4 bg-green-500 rounded-full mr-3 mt-0.5">
                          <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                          </svg>
                        </span>
                        <span class="line-through text-gray-500"><%= todo.title %></span>
                      <% else %>
                        <span class="inline-block w-4 h-4 border-2 border-gray-300 rounded-full mr-3 mt-0.5"></span>
                        <div class="flex-1">
                          <span class="font-medium text-gray-900"><%= todo.title %></span>
                          <%= if todo.description && String.trim(todo.description) != "" do %>
                            <p class="text-sm text-gray-600 mt-1"><%= todo.description %></p>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Right Column: Chat -->
        <div class="w-1/2 bg-white flex flex-col overflow-hidden">
          <div class="p-6 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900 flex items-center">
              <svg class="w-5 h-5 mr-2 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
              </svg>
              Journal Chat
            </h2>
            
            <!-- Conversation Selector (if multiple conversations exist) -->
            <%= if length(@journal_conversations) > 1 do %>
              <div class="mt-4">
                <label class="block text-sm font-medium text-gray-700 mb-2">Conversation:</label>
                <select
                  phx-change="switch_journal_conversation"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-purple-500"
                  value={if @current_journal_conversation, do: @current_journal_conversation.id, else: ""}
                >
                  <%= for conversation <- @journal_conversations do %>
                    <option value={conversation.id}>
                      <%= conversation.title %> (<%= length(conversation.chat_messages) %> messages)
                    </option>
                  <% end %>
                </select>
              </div>
            <% end %>
          </div>

          <!-- Chat Messages -->
          <div class="flex-1 overflow-y-auto p-6 bg-gray-50">
            <%= if length(@journal_chat_messages) == 0 do %>
              <div class="text-center text-gray-500 py-8">
                <svg class="w-12 h-12 mx-auto mb-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
                <p>Start a conversation about this journal entry</p>
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for message <- @journal_chat_messages do %>
                  <div class={"flex #{if message.role == "user", do: "justify-end", else: "justify-start"}"}>
                    <div class={"max-w-xs lg:max-w-md xl:max-w-lg px-4 py-2 rounded-lg #{if message.role == "user", do: "bg-purple-600 text-white", else: "bg-white border border-gray-200"}"}>
                      <%= if Map.get(message, :loading, false) do %>
                        <div class="flex items-center">
                          <svg class="animate-spin -ml-1 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          <%= message.content %>
                        </div>
                      <% else %>
                        <div class="prose prose-sm max-w-none">
                          <%= render_markdown(message.content) %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <!-- Chat Input -->
          <div class="border-t border-gray-200 p-4 bg-white">
            <form phx-submit="send_journal_chat_message" class="flex gap-2">
              <input
                type="text"
                name="message"
                placeholder="Ask about this journal entry..."
                class="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-purple-500"
                required
                autocomplete="off"
                disabled={@processing_message}
              />
              <button
                type="submit"
                class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-purple-500 disabled:opacity-50"
                disabled={@processing_message}
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
                </svg>
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end