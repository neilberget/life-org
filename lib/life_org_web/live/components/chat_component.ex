defmodule LifeOrgWeb.Components.ChatComponent do
  use Phoenix.Component
  import LifeOrgWeb.MarkdownHelper

  def ai_sidebar(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <%= if @view == :conversations do %>
        <.conversation_selection_view
          conversations={@conversations}
          tag_filter={assigns[:tag_filter]}
        />
      <% else %>
        <.chat_view
          messages={@messages}
          current_conversation={@current_conversation}
          tag_filter={assigns[:tag_filter]}
        />
      <% end %>
    </div>
    """
  end

  def conversation_selection_view(assigns) do
    ~H"""
    <!-- Conversations View Header -->
    <div class="p-4 border-b border-gray-200 bg-gray-50">
      <div class="flex justify-between items-center mb-3">
        <h2 class="text-lg font-bold text-gray-800">AI Assistant</h2>
        <button
          phx-click="toggle_ai_sidebar"
          class="p-1 rounded-md hover:bg-gray-200 transition-colors"
          title="Close AI Assistant"
        >
          <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>

      <!-- Tag Filter Warning -->
      <%= if assigns[:tag_filter] do %>
        <div class="mb-3 px-3 py-2 bg-amber-50 border border-amber-200 rounded-lg">
          <div class="flex items-center gap-2">
            <svg class="w-4 h-4 text-amber-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
            </svg>
            <div class="flex-1">
              <p class="text-xs text-amber-800 font-medium">Todo filter active</p>
              <p class="text-xs text-amber-600">
                New chats will only see todos tagged with "<%= @tag_filter %>"
              </p>
            </div>
          </div>
          <button
            phx-click="clear_tag_filter"
            class="mt-2 w-full text-xs text-amber-700 hover:text-amber-900 underline"
          >
            Clear filter to chat about all todos
          </button>
        </div>
      <% end %>

      <button
        phx-click="new_conversation"
        class="w-full px-3 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 transition-colors"
      >
        <svg class="w-4 h-4 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
        </svg>
        New Chat
      </button>
    </div>

    <!-- Conversations List -->
    <div class="flex-1 overflow-y-auto p-4">
      <%= if length(@conversations || []) == 0 do %>
        <div class="text-center text-gray-500 mt-8">
          <div class="w-16 h-16 mx-auto mb-4 bg-gray-100 rounded-full flex items-center justify-center">
            <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
            </svg>
          </div>
          <p class="text-sm font-medium mb-1">No conversations yet</p>
          <p class="text-xs">Start your first chat with the AI assistant</p>
        </div>
      <% else %>
        <div class="space-y-2">
          <h3 class="text-sm font-semibold text-gray-600 mb-3">Recent Conversations</h3>
          <%= for conversation <- @conversations do %>
            <button
              phx-click="select_conversation"
              phx-value-id={conversation.id}
              class="block w-full text-left p-3 bg-gray-50 hover:bg-gray-100 rounded-lg border border-gray-200 transition-colors"
            >
              <div class="font-medium text-sm text-gray-800 truncate">
                <%= conversation.title %>
              </div>
              <div class="text-xs text-gray-500 mt-1">
                <%= Calendar.strftime(conversation.updated_at, "%b %d, %Y") %>
              </div>
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def chat_view(assigns) do
    ~H"""
    <!-- Chat View Header -->
    <div class="p-4 border-b border-gray-200 bg-gray-50">
      <div class="flex items-center gap-3">
        <button
          phx-click="ai_sidebar_show_conversations"
          class="p-1 rounded-md hover:bg-gray-200 transition-colors"
          title="Back to conversations"
        >
          <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"></path>
          </svg>
        </button>

        <h2 class="text-lg font-bold text-gray-800 flex-1 truncate">
          <%= if @current_conversation, do: @current_conversation.title, else: "New Chat" %>
        </h2>

        <button
          phx-click="toggle_ai_sidebar"
          class="p-1 rounded-md hover:bg-gray-200 transition-colors"
          title="Close AI Assistant"
        >
          <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>

      <!-- Tag Filter Indicator -->
      <%= if assigns[:tag_filter] do %>
        <div class="mt-3 px-3 py-2 bg-blue-50 border border-blue-200 rounded-lg">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
              </svg>
              <span class="text-sm text-blue-800 font-medium">AI context filtered by tag:</span>
              <span class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full">
                #<%= @tag_filter %>
              </span>
            </div>
            <button
              phx-click="clear_tag_filter"
              class="text-xs text-blue-600 hover:text-blue-800 underline"
            >
              Clear filter
            </button>
          </div>
          <p class="text-xs text-blue-600 mt-1">
            The AI can only see todos tagged with "<%= @tag_filter %>"
          </p>
        </div>
      <% end %>
    </div>

    <!-- Chat Messages -->
    <.chat_messages messages={@messages} />

    <!-- Chat Input -->
    <.chat_input />
    """
  end

  def chat_messages(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-4">
      <%= if length(@messages || []) == 0 do %>
        <div class="text-center text-gray-500 mt-8">
          <p class="text-sm">Start a conversation with your AI assistant.</p>
          <p class="text-xs mt-2">Ask about your journal entries or request todo items.</p>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for message <- @messages do %>
            <.chat_message message={message} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def chat_message(assigns) do
    ~H"""
    <div class={"flex #{if @message.role == "user", do: "justify-end", else: "justify-start"}"}>
      <div class={"max-w-[280px] p-2 rounded-lg text-sm #{if @message.role == "user", do: "bg-blue-600 text-white", else: "bg-gray-100 text-gray-800"}"}>
        <%= if Map.get(@message, :loading, false) do %>
          <div class="flex items-center gap-2">
            <div class="animate-spin rounded-full h-3 w-3 border-2 border-blue-500 border-t-transparent"></div>
            <span class="text-xs"><%= @message.content %></span>
          </div>
        <% else %>
          <%= if @message.role == "user" do %>
            <div class="prose prose-sm prose-invert max-w-none">
              <%= render_markdown(@message.content) %>
            </div>
          <% else %>
            <div class="prose prose-sm max-w-none prose-headings:text-inherit prose-p:text-inherit prose-strong:text-inherit prose-em:text-inherit prose-code:text-inherit prose-pre:text-inherit prose-a:text-inherit">
              <%= render_markdown(@message.content) %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def chat_input(assigns) do
    ~H"""
    <form phx-submit="send_chat_message" class="p-4 border-t border-gray-200 bg-white">
      <div class="flex gap-2">
        <input
          type="text"
          name="message"
          placeholder="Ask about your journal entries or request todo items..."
          class="flex-1 p-2 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
        />
        <button type="submit" class="px-3 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
          </svg>
        </button>
      </div>
    </form>
    """
  end

  def expanded_chat_view(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <!-- Expanded Chat Header -->
      <div class="p-6 border-b border-gray-200 bg-gray-50">
        <div class="flex items-center justify-between mb-4">
          <h1 class="text-2xl font-bold text-gray-800">AI Assistant</h1>
          <button
            phx-click="toggle_ai_sidebar"
            class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
            title="Close AI Assistant"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
        
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-700">
            <%= if @current_conversation, do: @current_conversation.title, else: "New Chat" %>
          </h2>
          <button
            phx-click="ai_sidebar_show_conversations"
            class="px-3 py-1 text-sm bg-gray-100 text-gray-700 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500"
          >
            Switch Chat
          </button>
        </div>

        <!-- Tag Filter Indicator -->
        <%= if assigns[:tag_filter] do %>
          <div class="mt-4 px-4 py-3 bg-blue-50 border border-blue-200 rounded-lg">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <svg class="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
                </svg>
                <span class="text-sm text-blue-800 font-medium">AI context filtered by tag:</span>
                <span class="text-sm px-3 py-1 bg-blue-100 text-blue-800 rounded-full">
                  #<%= @tag_filter %>
                </span>
              </div>
              <button
                phx-click="clear_tag_filter"
                class="text-sm text-blue-600 hover:text-blue-800 underline"
              >
                Clear filter
              </button>
            </div>
            <p class="text-sm text-blue-600 mt-2">
              The AI can only see todos tagged with "<%= @tag_filter %>"
            </p>
          </div>
        <% end %>
      </div>

      <!-- Expanded Chat Messages -->
      <.expanded_chat_messages messages={@messages} />

      <!-- Expanded Chat Input -->
      <.expanded_chat_input />
    </div>
    """
  end

  def expanded_chat_messages(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-6">
      <%= if length(@messages || []) == 0 do %>
        <div class="text-center text-gray-500 mt-16">
          <div class="w-24 h-24 mx-auto mb-6 bg-gray-100 rounded-full flex items-center justify-center">
            <svg class="w-12 h-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
            </svg>
          </div>
          <p class="text-lg font-medium mb-2">Start a conversation with your AI assistant</p>
          <p class="text-sm">Ask about your journal entries, request todo items, or get help with organizing your life.</p>
        </div>
      <% else %>
        <div class="max-w-4xl mx-auto space-y-6">
          <%= for message <- @messages do %>
            <.expanded_chat_message message={message} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def expanded_chat_message(assigns) do
    ~H"""
    <div class={"flex #{if @message.role == "user", do: "justify-end", else: "justify-start"}"}>
      <div class={"max-w-3xl p-4 rounded-lg #{if @message.role == "user", do: "bg-blue-600 text-white", else: "bg-gray-100 text-gray-800"}"}>
        <%= if Map.get(@message, :loading, false) do %>
          <div class="flex items-center gap-3">
            <div class="animate-spin rounded-full h-4 w-4 border-2 border-blue-500 border-t-transparent"></div>
            <span class="text-sm"><%= @message.content %></span>
          </div>
        <% else %>
          <%= if @message.role == "user" do %>
            <div class="prose prose-invert max-w-none">
              <%= render_markdown(@message.content) %>
            </div>
          <% else %>
            <div class="prose max-w-none prose-headings:text-inherit prose-p:text-inherit prose-strong:text-inherit prose-em:text-inherit prose-code:text-inherit prose-pre:text-inherit prose-a:text-inherit">
              <%= render_markdown(@message.content) %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def expanded_chat_input(assigns) do
    ~H"""
    <form phx-submit="send_chat_message" class="p-6 border-t border-gray-200 bg-white">
      <div class="max-w-4xl mx-auto">
        <div class="flex gap-3">
          <input
            type="text"
            name="message"
            placeholder="Ask about your journal entries or request todo items..."
            class="flex-1 p-3 text-base border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            required
          />
          <button type="submit" class="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
            </svg>
          </button>
        </div>
      </div>
    </form>
    """
  end

  def expanded_conversation_view(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <!-- Expanded Conversations Header -->
      <div class="p-6 border-b border-gray-200 bg-gray-50">
        <div class="flex items-center justify-between mb-4">
          <h1 class="text-2xl font-bold text-gray-800">AI Assistant</h1>
          <button
            phx-click="toggle_ai_sidebar"
            class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
            title="Close AI Assistant"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
        
        <!-- Tag Filter Warning -->
        <%= if assigns[:tag_filter] do %>
          <div class="mb-4 px-4 py-3 bg-amber-50 border border-amber-200 rounded-lg">
            <div class="flex items-center gap-2">
              <svg class="w-5 h-5 text-amber-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
              </svg>
              <div class="flex-1">
                <p class="text-sm text-amber-800 font-medium">Todo filter active</p>
                <p class="text-sm text-amber-600">
                  New chats will only see todos tagged with "<%= @tag_filter %>"
                </p>
              </div>
            </div>
            <button
              phx-click="clear_tag_filter"
              class="mt-3 w-full text-sm text-amber-700 hover:text-amber-900 underline"
            >
              Clear filter to chat about all todos
            </button>
          </div>
        <% end %>

        <button
          phx-click="new_conversation"
          class="w-full px-4 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          <svg class="w-5 h-5 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
          </svg>
          New Chat
        </button>
      </div>

      <!-- Expanded Conversations List -->
      <div class="flex-1 overflow-y-auto p-6">
        <%= if length(@conversations || []) == 0 do %>
          <div class="text-center text-gray-500 mt-16">
            <div class="w-24 h-24 mx-auto mb-6 bg-gray-100 rounded-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
              </svg>
            </div>
            <p class="text-lg font-medium mb-2">No conversations yet</p>
            <p class="text-sm">Start your first chat with the AI assistant to get help organizing your life.</p>
          </div>
        <% else %>
          <div class="max-w-4xl mx-auto">
            <h3 class="text-lg font-semibold text-gray-700 mb-6">Recent Conversations</h3>
            <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              <%= for conversation <- @conversations do %>
                <button
                  phx-click="select_conversation"
                  phx-value-id={conversation.id}
                  class="block w-full text-left p-4 bg-white hover:bg-gray-50 rounded-lg border border-gray-200 shadow-sm hover:shadow-md transition-all"
                >
                  <div class="font-medium text-base text-gray-800 mb-2 line-clamp-2">
                    <%= conversation.title %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <%= Calendar.strftime(conversation.updated_at, "%b %d, %Y at %I:%M %p") %>
                  </div>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
