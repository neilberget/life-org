defmodule LifeOrgWeb.JournalEntryLive do
  use LifeOrgWeb, :live_view
  alias LifeOrg.{Repo, JournalEntry}

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
        # Preload associated todos if any
        entry = Repo.preload(entry, :todos)
        
        {:ok,
         socket
         |> assign(:entry, entry)
         |> assign(:related_todos, entry.todos)}
    end
  end

  @impl true
  def handle_event("back_to_organizer", _params, socket) do
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <div class="max-w-4xl mx-auto">
        <!-- Header -->
        <div class="mb-6 flex items-center justify-between">
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
            <%= Calendar.strftime(@entry.entry_date, "%A, %B %d, %Y") %>
          </div>
        </div>

        <!-- Journal Entry -->
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6">
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
          <div class="prose max-w-none text-gray-700">
            <%= if String.contains?(@entry.content, "\n") do %>
              <%= for line <- String.split(@entry.content, "\n") do %>
                <p class="mb-2"><%= line %></p>
              <% end %>
            <% else %>
              <p><%= @entry.content %></p>
            <% end %>
          </div>
        </div>

        <!-- Related Todos Section -->
        <%= if length(@related_todos) > 0 do %>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4 flex items-center">
              <svg class="w-5 h-5 mr-2 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
              </svg>
              Related Todos
            </h2>
            
            <p class="text-gray-600 text-sm mb-4">
              These todos were created from this journal entry by AI analysis:
            </p>

            <div class="space-y-3">
              <%= for todo <- @related_todos do %>
                <div class="border border-gray-200 rounded-lg p-4 hover:bg-gray-50 transition-colors">
                  <div class="flex items-start justify-between">
                    <div class="flex-1">
                      <div class="flex items-center mb-2">
                        <%= if todo.completed do %>
                          <span class="inline-flex items-center justify-center w-4 h-4 bg-green-500 rounded-full mr-3">
                            <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                            </svg>
                          </span>
                          <span class="line-through text-gray-500"><%= todo.title %></span>
                        <% else %>
                          <span class="inline-block w-4 h-4 border-2 border-gray-300 rounded-full mr-3"></span>
                          <span class="font-medium text-gray-900"><%= todo.title %></span>
                        <% end %>
                      </div>

                      <%= if todo.description && String.trim(todo.description) != "" do %>
                        <p class="text-sm text-gray-600 ml-7"><%= todo.description %></p>
                      <% end %>

                      <div class="flex items-center mt-2 ml-7 space-x-4">
                        <!-- Priority -->
                        <span class={[
                          "text-xs px-2 py-1 rounded-full font-medium",
                          case todo.priority do
                            "high" -> "bg-red-100 text-red-800"
                            "medium" -> "bg-yellow-100 text-yellow-800"
                            "low" -> "bg-green-100 text-green-800"
                            _ -> "bg-gray-100 text-gray-800"
                          end
                        ]}>
                          <%= String.capitalize(todo.priority || "medium") %>
                        </span>

                        <!-- Due Date -->
                        <%= if todo.due_date do %>
                          <span class="text-xs text-gray-500">
                            Due: <%= todo.due_date %>
                            <%= if todo.due_time, do: " at #{todo.due_time}" %>
                          </span>
                        <% end %>

                        <!-- Tags -->
                        <%= if todo.tags && length(todo.tags) > 0 do %>
                          <div class="flex flex-wrap gap-1">
                            <%= for tag <- todo.tags do %>
                              <span class="text-xs bg-gray-100 text-gray-600 px-2 py-1 rounded">
                                <%= tag %>
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="bg-gray-50 rounded-lg border-2 border-dashed border-gray-300 p-6 text-center">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No related todos</h3>
            <p class="mt-1 text-sm text-gray-500">
              No todos have been created from this journal entry yet.
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end