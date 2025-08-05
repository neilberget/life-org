defmodule LifeOrgWeb.Components.ChatComponent do
  use Phoenix.Component

  def chat_column(assigns) do
    ~H"""
    <div class="w-1/3 bg-gray-50 flex flex-col">
      <div class="p-6 border-b border-gray-200">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-2xl font-bold text-gray-800">AI Assistant</h2>
          <button
            phx-click="new_conversation"
            class="px-3 py-1 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
          >
            New Chat
          </button>
        </div>
        
        <%= if length(@conversations || []) > 0 do %>
          <.conversation_list conversations={@conversations} current={@current_conversation} />
        <% end %>
      </div>
      
      <.chat_messages messages={@messages} />
      <.chat_input />
    </div>
    """
  end

  def chat_messages(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-6">
      <div class="space-y-4">
        <%= for message <- @messages do %>
          <.chat_message message={message} />
        <% end %>
      </div>
    </div>
    """
  end

  def chat_message(assigns) do
    ~H"""
    <div class={"flex #{if @message.role == "user", do: "justify-end", else: "justify-start"}"}>
      <div class={"max-w-xs p-3 rounded-lg #{if @message.role == "user", do: "bg-blue-600 text-white", else: "bg-white border border-gray-200"}"}>
        <%= if Map.get(@message, :loading, false) do %>
          <div class="flex items-center gap-2">
            <div class="animate-spin rounded-full h-4 w-4 border-2 border-blue-500 border-t-transparent"></div>
            <%= @message.content %>
          </div>
        <% else %>
          <%= @message.content %>
        <% end %>
      </div>
    </div>
    """
  end

  def chat_input(assigns) do
    ~H"""
    <form phx-submit="send_chat_message" class="p-4 border-t border-gray-200">
      <div class="flex gap-2">
        <input
          type="text"
          name="message"
          placeholder="Ask about your journal entries or request todo items..."
          class="flex-1 p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
        />
        <button type="submit" class="px-4 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors">
          Send
        </button>
      </div>
    </form>
    """
  end

  def conversation_list(assigns) do
    ~H"""
    <div class="mb-4">
      <h3 class="text-sm font-semibold text-gray-600 mb-2">Recent Conversations</h3>
      <div class="space-y-1 max-h-32 overflow-y-auto">
        <%= for conversation <- @conversations do %>
          <button
            phx-click="select_conversation"
            phx-value-id={conversation.id}
            class={"block w-full text-left px-3 py-2 text-sm rounded-lg hover:bg-gray-200 #{if @current && @current.id == conversation.id, do: "bg-blue-100 border border-blue-300", else: "bg-white border border-gray-200"}"}
          >
            <%= conversation.title %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end