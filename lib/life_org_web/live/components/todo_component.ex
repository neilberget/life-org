defmodule LifeOrgWeb.Components.TodoComponent do
  use Phoenix.Component
  import LifeOrgWeb.Components.ModalComponent
  import Phoenix.HTML
  alias LifeOrg.TimezoneHelper

  def todo_column(assigns) do
    unique_tags = get_unique_tags(assigns.all_todos || assigns.todos)
    show_completed = Map.get(assigns, :show_completed, false)
    
    # Filter todos based on show_completed setting
    filtered_todos = if show_completed do
      assigns.todos
    else
      Enum.reject(assigns.todos, & &1.completed)
    end
    
    # Count completed todos
    completed_count = Enum.count(assigns.todos, & &1.completed)

    assigns =
      assign(assigns, :unique_tags, unique_tags)
      |> assign(:show_tag_dropdown, false)
      |> assign(:deleting_todo_id, Map.get(assigns, :deleting_todo_id))
      |> assign(:filtered_todos, filtered_todos)
      |> assign(:show_completed, show_completed)
      |> assign(:completed_count, completed_count)

    ~H"""
    <div class="w-full md:w-1/2 bg-white overflow-y-auto">
      <div class="p-4 md:p-6">
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-3">
            <h2 class="text-2xl font-bold text-gray-800">Todo List</h2>

            <!-- Tag Filter Dropdown -->
            <%= if length(@unique_tags) > 0 do %>
              <div class="relative">
                <button
                  phx-click="toggle_tag_dropdown"
                  class={"p-1.5 rounded-md transition-colors #{if @tag_filter, do: "bg-blue-100 text-blue-600 hover:bg-blue-200", else: "text-gray-500 hover:bg-gray-100"}"}
                  title="Filter by tag"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"></path>
                  </svg>
                </button>

                <!-- Dropdown Menu -->
                <div
                  id="tag-dropdown"
                  class="absolute left-0 mt-2 w-56 bg-white rounded-lg shadow-lg border border-gray-200 z-50 hidden"
                  phx-click-away="hide_tag_dropdown"
                >
                  <div class="p-3">
                    <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Filter by Tag</h3>
                    <div class="space-y-1 max-h-64 overflow-y-auto">
                      <%= for tag <- @unique_tags do %>
                        <button
                          phx-click="filter_by_tag"
                          phx-value-tag={tag}
                          class={"w-full text-left px-3 py-2 text-sm rounded-md transition-colors flex items-center justify-between group #{if @tag_filter == tag, do: "bg-blue-50 text-blue-700", else: "hover:bg-gray-50"}"}
                        >
                          <span class="flex items-center gap-2">
                            <span class="text-blue-500">#</span>
                            <%= tag %>
                          </span>
                          <%= if @tag_filter == tag do %>
                            <svg class="w-4 h-4 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                            </svg>
                          <% end %>
                        </button>
                      <% end %>
                    </div>
                    <%= if @tag_filter do %>
                      <div class="mt-2 pt-2 border-t border-gray-200">
                        <button
                          phx-click="clear_tag_filter"
                          class="w-full text-left px-3 py-2 text-sm text-red-600 hover:bg-red-50 rounded-md transition-colors"
                        >
                          <svg class="w-4 h-4 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                          </svg>
                          Clear filter
                        </button>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @tag_filter do %>
              <div class="flex items-center gap-2">
                <span class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full flex items-center gap-1">
                  #<%= @tag_filter %>
                  <button
                    phx-click="clear_tag_filter"
                    class="ml-1 hover:text-blue-900"
                  >
                    ✕
                  </button>
                </span>
              </div>
            <% end %>
            
            <%= if Map.get(assigns, :project_filter) do %>
              <div class="flex items-center gap-2">
                <span class="text-xs px-2 py-1 bg-green-100 text-green-800 rounded-full flex items-center gap-1">
                  <%= @project_filter %>
                  <button
                    phx-click="clear_project_filter"
                    class="ml-1 hover:text-green-900"
                  >
                    ✕
                  </button>
                </span>
              </div>
            <% end %>
          </div>

          <div class="flex gap-2">
            <%= if @completed_count > 0 do %>
              <button
                phx-click="toggle_show_completed"
                class={"p-2 rounded-lg transition-colors flex items-center gap-1 #{if @show_completed, do: "text-blue-600 hover:text-blue-700 hover:bg-blue-50 bg-blue-50", else: "text-gray-500 hover:text-gray-700 hover:bg-gray-100"}"}
                title={if @show_completed, do: "Hide completed", else: "Show completed"}
              >
                <%= if @show_completed do %>
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"></path>
                  </svg>
                <% else %>
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"></path>
                  </svg>
                <% end %>
                <span class="text-xs font-medium">
                  <%= @completed_count %>
                </span>
              </button>
            <% end %>
            <button
              phx-click="toggle_compact_todo_view"
              class={"p-2 rounded-lg transition-colors #{if Map.get(assigns, :compact_todo_view, true), do: "text-purple-600 hover:text-purple-700 hover:bg-purple-50 bg-purple-50", else: "text-gray-500 hover:text-gray-700 hover:bg-gray-100"}"}
              title={if Map.get(assigns, :compact_todo_view, true), do: "Switch to detailed view", else: "Switch to compact view"}
            >
              <%= if Map.get(assigns, :compact_todo_view, true) do %>
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"></path>
                </svg>
              <% else %>
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                </svg>
              <% end %>
            </button>
            <button
              phx-click="add_todo"
              class="p-2 text-blue-600 hover:text-blue-700 hover:bg-blue-50 rounded-lg transition-colors"
              title="Add new todo"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
              </svg>
            </button>
            <button
              phx-click="expand_todos"
              class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
              title="Expand todos view"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"></path>
              </svg>
            </button>
          </div>
        </div>

        <!-- Incoming Todos Section -->
        <%= if Map.get(assigns, :incoming_todos, []) != [] && length(@incoming_todos) > 0 do %>
          <.incoming_todos_section todos={@incoming_todos} />
        <% end %>

        <.todo_list todos={@filtered_todos} deleting_todo_id={@deleting_todo_id} compact_view={Map.get(assigns, :compact_todo_view, true)} />

        <!-- Edit Todo Modal -->
        <%= if Map.get(assigns, :editing_todo) do %>
          <.modal id="edit-todo-modal" title="Edit Todo" size="large" z_index="high">
            <.edit_todo_form todo={@editing_todo} />
          </.modal>
        <% end %>

        <!-- Add Todo Modal -->
        <%= if Map.get(assigns, :adding_todo, false) do %>
          <.modal id="add-todo-modal" title="Add New Todo" size="large" z_index="high">
            <.add_todo_form />
          </.modal>
        <% end %>

        <!-- View Todo Modal -->
        <%= if Map.get(assigns, :viewing_todo) do %>
          <.modal id="view-todo-modal" title="Todo Details" size="large">
            <.todo_view
              todo={@viewing_todo}
              comments={Map.get(assigns, :todo_comments, [])}
              show_todo_chat={Map.get(assigns, :show_todo_chat, false)}
              chat_todo_id={Map.get(assigns, :chat_todo_id)}
              todo_chat_messages={Map.get(assigns, :todo_chat_messages, [])}
              todo_conversations={Map.get(assigns, :todo_conversations, [])}
              current_todo_conversation={Map.get(assigns, :current_todo_conversation)}
              checkbox_update_trigger={Map.get(assigns, :checkbox_update_trigger, 0)}
            />
          </.modal>
        <% end %>
      </div>
    </div>
    """
  end

  def incoming_todos_section(assigns) do
    ~H"""
    <div class="mb-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-lg font-semibold text-blue-800">
          <svg class="inline w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          New Todos Found (<%= length(@todos) %>)
        </h3>
        <div class="flex space-x-2">
          <button
            phx-click="dismiss_incoming_todos"
            class="text-xs px-3 py-1 text-red-600 bg-red-100 rounded-md hover:bg-red-200 focus:outline-none focus:ring-2 focus:ring-red-500"
            onclick="return confirm('Are you sure you want to delete all these todos?')"
          >
            Delete All
          </button>
          <button
            phx-click="accept_incoming_todos"
            class="text-xs px-3 py-1 text-blue-600 bg-blue-100 rounded-md hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            ✓ Accept All
          </button>
        </div>
      </div>

      <div class="space-y-2">
        <%= for todo <- @todos do %>
          <.incoming_todo_item todo={todo} />
        <% end %>
      </div>

      <p class="text-xs text-blue-600 mt-3">
        These todos were extracted from your journal entry. Review and accept or delete them.
      </p>
    </div>
    """
  end

  def incoming_todo_item(assigns) do
    ~H"""
    <div class="flex items-start gap-3 p-3 bg-white border border-blue-200 rounded-lg">
      <div class="flex-1">
        <div class="flex justify-between items-start">
          <h4 class="font-medium text-gray-800">
            <%= @todo.title %>
          </h4>
          <button
            phx-click="delete_incoming_todo"
            phx-value-id={@todo.id}
            class="text-red-500 hover:text-red-700 transition-colors"
            onclick="return confirm('Delete this todo?')"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>
        <%= if @todo.description && String.trim(@todo.description) != "" do %>
          <div class="text-sm text-gray-600 mt-1">
            <div id={"todo-list-preview-#{@todo.id}"} class="link-preview-container" phx-hook="LinkPreviewLoader" data-content={Phoenix.HTML.html_escape(@todo.description)}>
              <%= raw(render_interactive_description(@todo.description, @todo.id, false)) %>
            </div>
          </div>
        <% end %>
        <div class="flex items-center gap-2 mt-2">
          <%= if @todo.priority do %>
            <span class={"text-xs px-2 py-1 rounded-full #{priority_class(@todo.priority)}"}>
              <%= @todo.priority %>
            </span>
          <% end %>
          <%= if @todo.comment_count && @todo.comment_count > 0 do %>
            <span class="text-xs text-gray-500 flex items-center gap-1">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
              </svg>
              <%= @todo.comment_count %>
            </span>
          <% end %>
          <%= if @todo.tags && length(@todo.tags) > 0 do %>
            <div class="flex flex-wrap gap-1">
              <%= for tag <- @todo.tags do %>
                <button
                  phx-click="filter_by_tag"
                  phx-value-tag={tag}
                  class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full hover:bg-blue-200 transition-colors cursor-pointer"
                  title={"Filter by ##{tag}"}
                >
                  #<%= tag %>
                </button>
              <% end %>
            </div>
          <% end %>
          <%= if @todo.projects && length(@todo.projects) > 0 do %>
            <div class="flex flex-wrap gap-1 mt-1">
              <%= for project <- @todo.projects do %>
                <button
                  phx-click="filter_by_project"
                  phx-value-project={project.name}
                  class="text-xs px-2 py-1 rounded-full hover:opacity-80 transition-opacity cursor-pointer"
                  style={"background-color: #{project.color}20; color: #{project.color}; border: 1px solid #{project.color}40;"}
                  title={"Filter by project: #{project.name}"}
                >
                  <%= if project.favicon_url do %>
                    <img src={project.favicon_url} class="w-3 h-3 inline-block mr-1" alt="" />
                  <% end %>
                  <%= project.name %>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def todo_list(assigns) do
    ~H"""
    <div class="space-y-2" phx-hook="TodoDragDropKeyboard" id="todo-drag-drop">
      <%= for todo <- @todos do %>
        <.todo_item todo={todo} deleting_todo_id={Map.get(assigns, :deleting_todo_id)} compact_view={Map.get(assigns, :compact_view, true)} />
      <% end %>
    </div>
    """
  end

  def todo_item(assigns) do
    is_being_deleted = Map.get(assigns, :deleting_todo_id) == assigns.todo.id
    compact_view = Map.get(assigns, :compact_view, true)
    assigns = assigns
      |> assign(:is_being_deleted, is_being_deleted)
      |> assign(:compact_view, compact_view)

    ~H"""
    <%= if @compact_view do %>
      <!-- Compact View -->
      <div 
        class={"flex items-center gap-2 px-2 py-1.5 hover:bg-gray-50 rounded group #{if @todo.current, do: "bg-green-50 border-l-2 border-green-500", else: ""}"} 
        data-todo-item 
        data-todo-id={@todo.id}
      >
        <input
          type="checkbox"
          checked={@todo.completed}
          phx-click="toggle_todo"
          phx-value-id={@todo.id}
          class="h-4 w-4 text-blue-600 rounded border-gray-300 focus:ring-blue-500 flex-shrink-0 todo-checkbox"
        />
        
        <div class="flex-1 min-w-0">
          <div class="truncate flex items-center">
            <!-- Project prefix if exists -->
            <%= if @todo.projects && length(@todo.projects) > 0 do %>
              <%= for project <- Enum.take(@todo.projects, 1) do %>
                <button
                  phx-click="filter_by_project"
                  phx-value-project={project.name}
                  class="text-xs font-medium px-1.5 py-0.5 rounded hover:opacity-80 transition-opacity cursor-pointer mr-1 flex-shrink-0"
                  style={"background-color: #{project.color}20; color: #{project.color};"}
                  title={"Filter by project: #{project.name}"}
                >
                  <%= if project.favicon_url do %>
                    <img src={project.favicon_url} class="w-3 h-3 inline-block mr-1" alt="" />
                  <% end %>
                  <%= project.name %>
                </button>
              <% end %>
              <%= if length(@todo.projects) > 1 do %>
                <span class="text-xs text-gray-400 mr-1 flex-shrink-0">+<%= length(@todo.projects) - 1 %></span>
              <% end %>
            <% end %>
            
            <span 
              class={"text-sm #{if @todo.completed, do: "line-through text-gray-500", else: "text-gray-800"} cursor-pointer truncate"}
              phx-click="view_todo"
              phx-value-id={@todo.id}
            >
              <%= @todo.title %>
            </span>
            
            <!-- Tags -->
            <%= if @todo.tags && length(@todo.tags) > 0 do %>
              <span class="ml-1 flex-shrink-0">
                <%= for tag <- Enum.take(@todo.tags, 2) do %>
                  <button
                    phx-click="filter_by_tag"
                    phx-value-tag={tag}
                    class="text-xs text-blue-600 hover:text-blue-800 transition-colors cursor-pointer ml-0.5"
                    title={"Filter by ##{tag}"}
                  >
                    #<%= tag %>
                  </button>
                <% end %>
                <%= if length(@todo.tags) > 2 do %>
                  <span class="text-xs text-gray-400 ml-0.5">+<%= length(@todo.tags) - 2 %></span>
                <% end %>
              </span>
            <% end %>
            
            <!-- Other metadata -->
            <span class="text-xs text-gray-500 ml-2 space-x-1 flex-shrink-0">
              <button
                phx-click="cycle_todo_priority"
                phx-value-id={@todo.id}
                class="inline-block hover:scale-125 transition-transform cursor-pointer"
                title={"Priority: #{@todo.priority || "medium"} (click to change)"}
              >
                <span class={"inline-block w-2 h-2 rounded-full #{priority_dot_color(@todo.priority)}"}></span>
              </button>
              <%= if @todo.due_date do %>
                <span>📅</span>
              <% end %>
              <%= if @todo.comment_count && @todo.comment_count > 0 do %>
                <span>💬<%= @todo.comment_count %></span>
              <% end %>
            </span>
          </div>
        </div>

        <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity" onclick="event.stopPropagation()">
          <%= if @todo.current do %>
            <button
              phx-click="stop_todo"
              phx-value-id={@todo.id}
              class="text-orange-500 hover:text-orange-700"
              title="Stop working"
            >
              <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </button>
          <% else %>
            <button
              phx-click="start_todo"
              phx-value-id={@todo.id}
              class="text-green-500 hover:text-green-700"
              title="Start working"
            >
              <svg class="h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd" />
              </svg>
            </button>
          <% end %>

          <%= if @is_being_deleted do %>
            <button
              phx-click="confirm_delete_todo"
              phx-value-id={@todo.id}
              class="text-red-600 hover:text-red-800"
              title="Confirm delete"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
              </svg>
            </button>
            <button
              phx-click="cancel_delete_todo"
              class="text-gray-500 hover:text-gray-700"
              title="Cancel"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
            </button>
          <% else %>
            <button
              phx-click="show_delete_confirmation"
              phx-value-id={@todo.id}
              class="text-red-500 hover:text-red-700"
              title="Delete"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
            </button>
          <% end %>
        </div>
      </div>
    <% else %>
      <!-- Detailed View (Original) -->
      <div 
        class={"flex items-start gap-3 p-3 hover:bg-gray-50 rounded-lg group #{if @todo.current, do: "bg-green-50 border-l-4 border-green-500", else: ""}"} 
        data-todo-item 
        data-todo-id={@todo.id}
      >
        <input
          type="checkbox"
          checked={@todo.completed}
          phx-click="toggle_todo"
          phx-value-id={@todo.id}
          class="mt-1 h-5 w-5 text-blue-600 rounded border-gray-300 focus:ring-blue-500 todo-checkbox"
        />
        <div
          class="flex-1 cursor-pointer"
          phx-click="view_todo"
          phx-value-id={@todo.id}
        >
          <div class="flex justify-between items-start">
            <h4 class={"font-medium #{if @todo.completed, do: "line-through text-gray-500", else: "text-gray-800"}"}>
              <%= @todo.title %>
            </h4>
            <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                onclick={"event.stopPropagation(); navigator.clipboard.writeText(window.location.origin + '/todo/#{@todo.id}').then(() => { 
                  const btn = this;
                  const originalIcon = btn.innerHTML;
                  btn.innerHTML = '<svg class=\"h-4 w-4\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M5 13l4 4L19 7\"></path></svg>';
                  btn.classList.remove('text-gray-500', 'hover:text-gray-700');
                  btn.classList.add('text-green-500');
                  setTimeout(() => {
                    btn.innerHTML = originalIcon;
                    btn.classList.add('text-gray-500', 'hover:text-gray-700');
                    btn.classList.remove('text-green-500');
                  }, 1500);
                }).catch(() => alert('Failed to copy link'));"}
                class="text-gray-500 hover:text-gray-700"
                title="Copy link to todo"
              >
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
                </svg>
              </button>
              <%= if @todo.current do %>
                <button
                  phx-click="stop_todo"
                  phx-value-id={@todo.id}
                  class="text-orange-500 hover:text-orange-700"
                  title="Stop working on this"
                >
                  <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                </button>
              <% else %>
                <button
                  phx-click="start_todo"
                  phx-value-id={@todo.id}
                  class="text-green-500 hover:text-green-700"
                  title="Start working on this"
                >
                  <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd" />
                  </svg>
                </button>
              <% end %>
              <button
                phx-click="edit_todo"
                phx-value-id={@todo.id}
                class="text-blue-500 hover:text-blue-700"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                </svg>
              </button>

              <%= if @is_being_deleted do %>
                <!-- Confirmation buttons when delete is clicked -->
                <div class="flex gap-1 bg-red-50 border border-red-200 rounded px-2 py-1">
                  <button
                    phx-click="confirm_delete_todo"
                    phx-value-id={@todo.id}
                    class="text-red-600 hover:text-red-800 flex items-center gap-1"
                    title="Confirm delete"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                    </svg>
                    <span class="text-xs">Delete</span>
                  </button>
                  <button
                    phx-click="cancel_delete_todo"
                    class="text-gray-500 hover:text-gray-700"
                    title="Cancel delete"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                    </svg>
                  </button>
                </div>
              <% else %>
                <!-- Normal delete button -->
                <button
                  phx-click="show_delete_confirmation"
                  phx-value-id={@todo.id}
                  class="text-red-500 hover:text-red-700"
                  title="Delete todo"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </button>
              <% end %>
            </div>
          </div>
          <%= if @todo.description && String.trim(@todo.description) != "" do %>
            <div class="text-sm text-gray-600 mt-1">
              <div class="truncate">
                <%= truncate_description(@todo.description) %>
              </div>
            </div>
          <% end %>
          <div class="flex items-center gap-2 mt-2">
            <button
              phx-click="cycle_todo_priority"
              phx-value-id={@todo.id}
              class="hover:opacity-80 transition-opacity cursor-pointer"
              title={"Priority: #{@todo.priority || "medium"} (click to change)"}
            >
              <span class={"text-xs px-2 py-1 rounded-full #{priority_class(@todo.priority)}"}>
                <%= @todo.priority %>
              </span>
            </button>
            <%= if @todo.due_date do %>
              <span class="text-xs text-gray-500">
                📅 <%= format_due_datetime(@todo.due_date, @todo.due_time, Map.get(assigns, :user_timezone)) %>
              </span>
            <% end %>
            <%= if @todo.comment_count && @todo.comment_count > 0 do %>
              <span class="text-xs text-gray-500 flex items-center gap-1">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
                <%= @todo.comment_count %>
              </span>
            <% end %>
            <%= if @todo.tags && length(@todo.tags) > 0 do %>
              <div class="flex flex-wrap gap-1">
                <%= for tag <- @todo.tags do %>
                  <button
                    phx-click="filter_by_tag"
                    phx-value-tag={tag}
                    class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full hover:bg-blue-200 transition-colors cursor-pointer"
                    title={"Filter by ##{tag}"}
                  >
                    #<%= tag %>
                  </button>
                <% end %>
              </div>
            <% end %>
            <%= if @todo.projects && length(@todo.projects) > 0 do %>
              <div class="flex flex-wrap gap-1 mt-1">
                <%= for project <- @todo.projects do %>
                  <button
                    phx-click="filter_by_project"
                    phx-value-project={project.name}
                    class="text-xs px-2 py-1 rounded-full hover:opacity-80 transition-opacity cursor-pointer"
                    style={"background-color: #{project.color}20; color: #{project.color}; border: 1px solid #{project.color}40;"}
                    title={"Filter by project: #{project.name}"}
                  >
                    <%= if project.favicon_url do %>
                    <img src={project.favicon_url} class="w-3 h-3 inline-block mr-1" alt="" />
                  <% end %>
                  <%= project.name %>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  def edit_todo_form(assigns) do
    due_date =
      if assigns.todo.due_date do
        Date.to_string(assigns.todo.due_date)
      else
        ""
      end

    due_time =
      if assigns.todo.due_time do
        Time.to_string(assigns.todo.due_time)
      else
        ""
      end

    # Get all unique projects from workspace for autocomplete
    workspace_id = assigns[:workspace_id]
    workspace_projects = if workspace_id do
      # Handle both integer and string workspace_id
      id = if is_binary(workspace_id), do: String.to_integer(workspace_id), else: workspace_id
      LifeOrg.Projects.list_projects(id)
    else
      # Fallback: try to get from todo's workspace_id
      if assigns.todo && assigns.todo.workspace_id do
        LifeOrg.Projects.list_projects(assigns.todo.workspace_id)
      else
        []
      end
    end

    assigns =
      assigns
      |> assign(:due_date_string, due_date)
      |> assign(:due_time_string, due_time)
      |> assign(:workspace_projects, workspace_projects)

    ~H"""
    <form phx-submit="update_todo" phx-value-id={@todo.id}>
      <div class="space-y-6">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Title</label>
          <input
            type="text"
            name="todo[title]"
            value={@todo.title}
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            required
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Description</label>
          <textarea
            name="todo[description]"
            rows="6"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
            placeholder="Optional description... Use - [ ] for checkboxes"
          ><%= @todo.description || "" %></textarea>
          <p class="text-xs text-gray-500 mt-1">Supports markdown. Use <code>- [ ]</code> for unchecked and <code>- [x]</code> for checked items.</p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Tags</label>
          <input
            type="text"
            name="todo[tags_input]"
            value={if @todo.tags, do: Enum.join(@todo.tags, ", "), else: ""}
            placeholder="Enter tags separated by commas (e.g., work, urgent, project1)"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <p class="text-xs text-gray-500 mt-1">Separate multiple tags with commas</p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Projects</label>
          
          <%= if length(@workspace_projects) > 0 do %>
            <div class="mb-3 p-3 bg-gray-50 rounded-lg">
              <p class="text-xs text-gray-600 mb-2">Select existing projects:</p>
              <div class="flex flex-wrap gap-2">
                <%= for project <- @workspace_projects do %>
                  <% is_selected = @todo.projects && Enum.any?(@todo.projects, & &1.id == project.id) %>
                  <label class="flex items-center gap-1.5 cursor-pointer">
                    <input
                      type="checkbox"
                      name={"todo[existing_projects][]"}
                      value={project.name}
                      checked={is_selected}
                      class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm flex items-center gap-1">
                      <span class="w-2 h-2 rounded-full" style={"background-color: #{project.color}"}></span>
                      <%= if project.favicon_url do %>
                    <img src={project.favicon_url} class="w-3 h-3 inline-block mr-1" alt="" />
                  <% end %>
                  <%= project.name %>
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
          
          <input
            type="text"
            name="todo[new_projects]"
            placeholder="Add new projects (comma-separated)"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <p class="text-xs text-gray-500 mt-1">Create new projects by typing their names</p>
        </div>

        <div class="flex gap-4">
          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">Priority</label>
            <select
              name="todo[priority]"
              class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="low" selected={@todo.priority == "low"}>Low</option>
              <option value="medium" selected={@todo.priority == "medium"}>Medium</option>
              <option value="high" selected={@todo.priority == "high"}>High</option>
            </select>
          </div>

          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">Due Date</label>
            <input
              type="date"
              name="todo[due_date]"
              value={@due_date_string}
              class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">Due Time</label>
            <input
              type="time"
              name="todo[due_time]"
              value={@due_time_string}
              class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <button
            type="button"
            phx-click={hide_modal("edit-todo-modal")}
            class="px-4 py-2 text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
          >
            Save Changes
          </button>
        </div>
      </div>
    </form>
    """
  end

  def add_todo_form(assigns) do
    # Get all unique projects from workspace for selection
    workspace_id = assigns[:workspace_id]
    workspace_projects = if workspace_id do
      # Handle both integer and string workspace_id
      id = if is_binary(workspace_id), do: String.to_integer(workspace_id), else: workspace_id
      LifeOrg.Projects.list_projects(id)
    else
      []
    end

    # Extract defaults from assigns
    defaults = Map.get(assigns, :defaults, %{})
    tag_filter = Map.get(defaults, :tag_filter)
    project_filter = Map.get(defaults, :project_filter)

    assigns = assign(assigns, :workspace_projects, workspace_projects)
    |> assign(:tag_filter, tag_filter)
    |> assign(:project_filter, project_filter)
    
    ~H"""
    <form phx-submit="create_todo">
      <div class="space-y-6">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Title</label>
          <input
            type="text"
            name="todo[title]"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            required
            autofocus
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Description</label>
          <textarea
            name="todo[description]"
            rows="6"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
            placeholder="Optional description... Use - [ ] for checkboxes"
          ></textarea>
          <p class="text-xs text-gray-500 mt-1">Supports markdown. Use <code>- [ ]</code> for unchecked and <code>- [x]</code> for checked items.</p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Tags</label>
          <%= if @tag_filter do %>
            <p class="text-xs text-blue-600 mb-1">DEBUG: Tag filter active: <%= @tag_filter %></p>
          <% end %>
          <input
            type="text"
            name="todo[tags_input]"
            value={@tag_filter || ""}
            placeholder="Enter tags separated by commas (e.g., work, urgent, project1)"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <p class="text-xs text-gray-500 mt-1">Separate multiple tags with commas</p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Projects</label>
          <%= if @project_filter do %>
            <p class="text-xs text-green-600 mb-1">DEBUG: Project filter active: <%= @project_filter %></p>
          <% end %>
          
          <%= if length(@workspace_projects) > 0 do %>
            <div class="mb-3 p-3 bg-gray-50 rounded-lg">
              <p class="text-xs text-gray-600 mb-2">Select existing projects:</p>
              <div class="flex flex-wrap gap-2">
                <%= for project <- @workspace_projects do %>
                  <label class="flex items-center gap-1.5 cursor-pointer">
                    <input
                      type="checkbox"
                      name={"todo[existing_projects][]"}
                      value={project.name}
                      checked={@project_filter == project.name}
                      class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm flex items-center gap-1">
                      <span class="w-2 h-2 rounded-full" style={"background-color: #{project.color}"}></span>
                      <%= if project.favicon_url do %>
                    <img src={project.favicon_url} class="w-3 h-3 inline-block mr-1" alt="" />
                  <% end %>
                  <%= project.name %>
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
          
          <input
            type="text"
            name="todo[new_projects]"
            value={if @project_filter && !Enum.any?(@workspace_projects, & &1.name == @project_filter), do: @project_filter, else: ""}
            placeholder="Add new projects (comma-separated)"
            class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <p class="text-xs text-gray-500 mt-1">Create new projects by typing their names</p>
        </div>

        <div class="flex gap-4">
          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">Priority</label>
            <select
              name="todo[priority]"
              class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="medium" selected>Medium</option>
              <option value="low">Low</option>
              <option value="high">High</option>
            </select>
          </div>

          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">Due Date</label>
            <input
              type="date"
              name="todo[due_date]"
              class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">Due Time</label>
            <input
              type="time"
              name="todo[due_time]"
              class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <button
            type="button"
            phx-click={hide_modal("add-todo-modal")}
            class="px-4 py-2 text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
          >
            Create Todo
          </button>
        </div>
      </div>
    </form>
    """
  end

  defp priority_class("high"), do: "bg-red-100 text-red-800"
  defp priority_class("medium"), do: "bg-yellow-100 text-yellow-800"
  defp priority_class("low"), do: "bg-green-100 text-green-800"
  defp priority_class(_), do: "bg-gray-100 text-gray-800"

  defp priority_dot_color("high"), do: "bg-red-400"
  defp priority_dot_color("medium"), do: "bg-yellow-400"
  defp priority_dot_color("low"), do: "bg-green-400"
  defp priority_dot_color(_), do: "bg-yellow-400"

  defp format_due_datetime(date, nil, timezone) do
    if timezone do
      # Convert the date to a datetime at midnight UTC, then to user timezone
      {:ok, datetime} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
      datetime
      |> TimezoneHelper.to_user_timezone(timezone)
      |> DateTime.to_date()
      |> Date.to_string()
    else
      Date.to_string(date)
    end
  end

  defp format_due_datetime(date, time, timezone) when not is_nil(time) do
    if timezone do
      # Combine date and time into UTC datetime, then convert to user timezone
      {:ok, datetime} = DateTime.new(date, time, "Etc/UTC")
      TimezoneHelper.format_datetime(datetime, timezone)
    else
      date_str = Date.to_string(date)
      # Show only HH:MM
      time_str = Time.to_string(time) |> String.slice(0, 5)
      "#{date_str} at #{time_str}"
    end
  end

  def todo_view(assigns) do
    show_chat =
      Map.get(assigns, :show_todo_chat, false) &&
        Map.get(assigns, :chat_todo_id) == assigns.todo.id

    assigns = assign(assigns, :show_chat, show_chat)

    ~H"""
    <div class={"flex gap-6 #{if @show_chat, do: "h-[600px]", else: ""}"}>
      <!-- Left Column: Todo Details -->
      <div class={"#{if @show_chat, do: "w-1/2", else: "w-full"} #{if @show_chat, do: "overflow-y-auto pr-3", else: "space-y-6"}"}>
        <!-- Todo Header -->
        <div class="flex items-start justify-between mb-6">
          <div class="flex-1">
            <h2 class={"text-2xl font-bold #{if @todo.completed, do: "line-through text-gray-500", else: "text-gray-800"}"}>
              <%= @todo.title %>
            </h2>
            <div class="flex items-center gap-3 mt-2">
              <button
                phx-click="cycle_todo_priority"
                phx-value-id={@todo.id}
                class="hover:opacity-80 transition-opacity"
                title="Click to change priority"
              >
                <span class={"px-3 py-1 rounded-full text-sm font-medium #{priority_class(@todo.priority)}"}>
                  <%= String.capitalize(@todo.priority || "medium") %>
                </span>
              </button>
              <%= if @todo.due_date do %>
                <span class="text-gray-600 flex items-center gap-1">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                  </svg>
                  <%= format_due_datetime(@todo.due_date, @todo.due_time, Map.get(assigns, :user_timezone)) %>
                </span>
              <% end %>
              <%= if @todo.completed do %>
                <span class="text-green-600 flex items-center gap-1">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                  </svg>
                  Completed
                </span>
              <% end %>
            </div>
          </div>
          <div class="flex gap-2">
            <button
              phx-click="edit_todo_from_view"
              phx-value-id={@todo.id}
              class="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
              title="Edit Todo"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
              </svg>
            </button>
            <button
              type="button"
              phx-click="toggle_todo_chat"
              phx-value-id={@todo.id}
              class={"p-2 hover:bg-purple-50 rounded-lg transition-colors #{if @show_chat, do: "text-purple-700 bg-purple-100", else: "text-purple-600"}"}
              title={if @show_chat, do: "Close chat", else: "Chat about this todo"}
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
              </svg>
            </button>
          </div>
        </div>

        <!-- Journal Entry Reference -->
        <%= if @todo.journal_entry do %>
          <div class="mb-6">
            <div class="relative inline-block">
              <button
                onclick={"
                  const popup = document.getElementById('journal-ref-popup-#{@todo.id}');
                  popup.classList.toggle('hidden');
                  if (!popup.classList.contains('hidden')) {
                    setTimeout(() => {
                      const clickAway = (e) => {
                        if (!popup.contains(e.target) && !e.target.closest('[onclick*=\"journal-ref-popup-#{@todo.id}\"]')) {
                          popup.classList.add('hidden');
                          document.removeEventListener('click', clickAway);
                        }
                      };
                      document.addEventListener('click', clickAway);
                    }, 0);
                  }
                "}
                class="flex items-center gap-1 px-2 py-1 text-sm text-blue-600 hover:text-blue-800 hover:bg-blue-50 rounded transition-colors"
                title="Created from journal entry"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.746 0 3.332.477 4.5 1.253v13C19.832 18.477 18.246 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path>
                </svg>
                <span class="text-xs bg-blue-100 text-blue-800 px-1.5 py-0.5 rounded-full">1</span>
              </button>

              <!-- Popup -->
              <div
                id={"journal-ref-popup-#{@todo.id}"}
                class="hidden absolute left-0 top-8 z-50 w-80 bg-white rounded-lg shadow-lg border border-gray-200 p-4"
                onclick="event.stopPropagation()"
              >
                <div class="flex items-start gap-3">
                  <div class="flex-shrink-0">
                    <svg class="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.746 0 3.332.477 4.5 1.253v13C19.832 18.477 18.246 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path>
                    </svg>
                  </div>
                  <div class="flex-1">
                    <h4 class="font-medium text-gray-900 mb-1">Created from Journal Entry</h4>
                    <p class="text-gray-600 text-sm mb-3">
                      This todo was created from your journal entry on <%= Calendar.strftime(@todo.journal_entry.entry_date, "%A, %B %d, %Y") %>
                    </p>
                    <a
                      href={"/journal/#{@todo.journal_entry.id}"}
                      class="inline-flex items-center gap-1 text-blue-600 hover:text-blue-800 text-sm font-medium"
                    >
                      View journal entry
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                      </svg>
                    </a>
                  </div>
                </div>

                <!-- Close button -->
                <button
                  onclick={"document.getElementById('journal-ref-popup-#{@todo.id}').classList.add('hidden')"}
                  class="absolute top-2 right-2 text-gray-400 hover:text-gray-600"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Tags -->
        <%= if @todo.tags && length(@todo.tags) > 0 do %>
          <div class="flex flex-wrap gap-2 mb-6">
            <%= for tag <- @todo.tags do %>
              <button
                phx-click="filter_by_tag"
                phx-value-tag={tag}
                class="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm hover:bg-blue-200 transition-colors cursor-pointer"
                title={"Filter by ##{tag}"}
              >
                #<%= tag %>
              </button>
            <% end %>
          </div>
        <% end %>

        <!-- Projects -->
        <%= if @todo.projects && length(@todo.projects) > 0 do %>
          <div class="flex flex-wrap gap-2 mb-6">
            <%= for project <- @todo.projects do %>
              <button
                phx-click="filter_by_project"
                phx-value-project={project.name}
                class="px-3 py-1 rounded-full text-sm hover:opacity-80 transition-opacity cursor-pointer"
                style={"background-color: #{project.color}20; color: #{project.color}; border: 1px solid #{project.color}40;"}
                title={"Filter by project: #{project.name}"}
              >
                <%= if project.favicon_url do %>
                  <img src={project.favicon_url} class="w-3 h-3 inline-block mr-1" alt="" />
                <% end %>
                <%= project.name %>
              </button>
            <% end %>
          </div>
        <% end %>

        <!-- Description -->
        <%= if @todo.description && String.trim(@todo.description) != "" do %>
          <div id={"todo-view-description-#{@todo.id}"} class="bg-gray-50 rounded-lg p-4 mb-6" phx-hook="InteractiveCheckboxes">
            <h3 class="text-lg font-semibold text-gray-800 mb-3">Description</h3>
            <div class="prose prose-sm prose-gray max-w-none">
              <div id={"todo-description-preview-#{@todo.id}"} class="link-preview-container" phx-hook="LinkPreviewLoader" data-content={Phoenix.HTML.html_escape(@todo.description)}>
                <%= raw(render_interactive_description(@todo.description, @todo.id)) %>
              </div>
            </div>
            <!-- Hidden trigger to force re-render when checkboxes change -->
            <span style="display: none;" id={"trigger-#{@todo.id}"}><%= Map.get(assigns, :checkbox_update_trigger, 0) %></span>
          </div>
        <% end %>

        <!-- Comments Section -->
        <div class="border-t pt-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-gray-800">Comments</h3>
            <button
              onclick={"document.getElementById('comment-form-#{@todo.id}').classList.remove('hidden')"}
              class="px-3 py-1 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm"
            >
              Add Comment
            </button>
          </div>

          <!-- Add Comment Form -->
          <div id={"comment-form-#{@todo.id}"} class="mb-4 hidden">
            <form phx-submit="add_todo_comment" phx-value-todo-id={@todo.id}>
              <textarea
                name="comment[content]"
                placeholder="Add a comment..."
                class="w-full p-3 border border-gray-300 rounded-lg resize-none h-20 focus:outline-none focus:ring-2 focus:ring-blue-500"
                required
              ></textarea>
              <div class="flex justify-end gap-2 mt-2">
                <button
                  type="button"
                  phx-click="hide_add_comment_form"
                  class="px-3 py-1 text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-3 py-1 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
                >
                  Add Comment
                </button>
              </div>
            </form>
          </div>

          <!-- Comments List -->
          <div class="space-y-3">
            <%= if length(@comments) == 0 do %>
              <p class="text-gray-500 text-center py-8">No comments yet. Be the first to add one!</p>
            <% else %>
              <%= for comment <- @comments do %>
                <.comment_item comment={comment} />
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Right Column: Chat Interface -->
      <%= if @show_chat do %>
        <div class="w-1/2 border-l pl-6">
          <div class="flex flex-col h-full">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-800">Todo Chat</h3>
              <div class="flex items-center gap-2">
                <%= if length(Map.get(assigns, :todo_conversations, [])) > 1 do %>
                  <button
                    phx-click="create_new_todo_conversation"
                    phx-value-todo-id={@todo.id}
                    class="px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700"
                    title="Start new conversation"
                  >
                    + New
                  </button>
                <% end %>
                <p class="text-sm text-gray-500">Ask questions about this todo</p>
              </div>
            </div>

            <!-- Conversation Selector -->
            <%= if length(Map.get(assigns, :todo_conversations, [])) > 1 do %>
              <div class="mb-3">
                <select
                  phx-change="switch_todo_conversation"
                  phx-value-todo-id={@todo.id}
                  class="w-full p-1 text-xs border border-gray-300 rounded focus:outline-none focus:ring-1 focus:ring-blue-500"
                >
                  <%= for conversation <- Map.get(assigns, :todo_conversations, []) do %>
                    <option
                      value={conversation.id}
                      selected={Map.get(assigns, :current_todo_conversation) && Map.get(assigns, :current_todo_conversation).id == conversation.id}
                    >
                      <%= conversation.title %> (<%= length(conversation.chat_messages) %> messages)
                    </option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <div class="flex-1 bg-gray-50 rounded-lg p-4 overflow-y-auto mb-4">
              <div class="space-y-3">
                <%= if length(Map.get(assigns, :todo_chat_messages, [])) == 0 do %>
                  <p class="text-gray-500 text-center py-8 text-sm">
                    Start a conversation about "<%= @todo.title %>"
                  </p>
                <% else %>
                  <%= for message <- Map.get(assigns, :todo_chat_messages, []) do %>
                    <div class={"flex #{if message.role == "user", do: "justify-end", else: "justify-start"}"}>
                      <div class={"max-w-xs px-3 py-2 rounded-lg text-sm #{if message.role == "user", do: "bg-blue-600 text-white", else: (if Map.get(message, :loading, false), do: "bg-gray-100 text-gray-600 animate-pulse", else: "bg-white text-gray-800 border")}"}>
                        <%= if message.role == "assistant" && !Map.get(message, :loading, false) do %>
                          <div class="prose prose-sm prose-gray max-w-none">
                            <%= raw(Earmark.as_html!(message.content)) %>
                          </div>
                        <% else %>
                          <%= if Map.get(message, :loading, false) do %>
                            <div class="flex items-center gap-1">
                              <div class="flex space-x-1">
                                <div class="w-1 h-1 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0s;"></div>
                                <div class="w-1 h-1 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s;"></div>
                                <div class="w-1 h-1 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s;"></div>
                              </div>
                              <span class="text-xs">Thinking...</span>
                            </div>
                          <% else %>
                            <%= message.content %>
                          <% end %>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <form phx-submit="send_todo_chat_message" phx-value-todo-id={@todo.id} class="flex gap-2">
              <input
                type="text"
                name="message"
                placeholder="Ask about this todo..."
                class="flex-1 p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 text-sm"
                required
              />
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm"
              >
                Send
              </button>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def comment_item(assigns) do
    ~H"""
    <div class="flex gap-3 p-3 bg-white border border-gray-200 rounded-lg">
      <div class="flex-shrink-0 w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
        <svg class="w-4 h-4 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clip-rule="evenodd" />
        </svg>
      </div>
      <div class="flex-1">
        <div class="prose prose-sm prose-gray max-w-none">
          <%= raw(Earmark.as_html!(@comment.content)) %>
        </div>
        <div class="flex items-center justify-between mt-2">
          <span class="text-xs text-gray-500">
            <%= TimezoneHelper.format_datetime(@comment.inserted_at, Map.get(assigns, :user_timezone, "America/Chicago")) %>
          </span>
          <button
            phx-click="delete_todo_comment"
            phx-value-id={@comment.id}
            data-confirm="Delete this comment?"
            class="text-red-500 hover:text-red-700 text-xs"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  def get_unique_tags(todos) do
    todos
    |> Enum.flat_map(fn todo -> todo.tags || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp truncate_description(description) do
    # Strip markdown and HTML, then truncate to one line
    description
    |> String.replace(~r/\*\*(.+?)\*\*/, "\\1")  # Remove bold
    |> String.replace(~r/\*(.+?)\*/, "\\1")      # Remove italic
    |> String.replace(~r/`(.+?)`/, "\\1")        # Remove code
    |> String.replace(~r/#+\s+/, "")             # Remove headers
    |> String.replace(~r/- \[.\] /, "")          # Remove checkbox markdown
    |> String.replace(~r/\n+/, " ")              # Replace newlines with spaces
    |> String.trim()
    |> then(fn text ->
      if String.length(text) > 80 do
        String.slice(text, 0, 80) <> "..."
      else
        text
      end
    end)
  end

  defp render_interactive_description(description, todo_id, interactive \\ true) do
    # Convert markdown to HTML first
    html = Earmark.as_html!(description)

    # Transform checkboxes based on context
    processed_html = make_checkboxes_interactive(html, todo_id, interactive: interactive)

    # Return the processed HTML - link previews are handled by the LinkPreviewLoader hook
    processed_html
  end

  def make_checkboxes_interactive(html, todo_id, opts \\ []) do
    interactive = Keyword.get(opts, :interactive, true)
    lines = String.split(html, "\n")

    {processed_lines, _} =
      Enum.map_reduce(lines, 0, fn line, checkbox_index ->
        cond do
          # Handle any occurrence of [ ] (unchecked checkbox) - anywhere in the line
          String.contains?(line, "[ ]") and not String.contains?(line, "<input") ->
            checkbox_html =
              if interactive do
                "<input type=\"checkbox\" data-todo-checkbox data-todo-id=\"#{todo_id}\" data-checkbox-index=\"#{checkbox_index}\" class=\"mr-2 my-0 align-middle\">"
              else
                "<input type=\"checkbox\" disabled class=\"mr-2 my-0 align-middle checkbox-readonly\">"
              end

            updated_line = String.replace(line, ~r/\[\s*\]/, checkbox_html, global: false)
            {updated_line, checkbox_index + 1}

          # Handle any occurrence of [x] or [X] (checked checkbox) - anywhere in the line
          String.match?(line, ~r/\[x\]/i) and not String.contains?(line, "<input") ->
            checkbox_html =
              if interactive do
                "<input type=\"checkbox\" checked data-todo-checkbox data-todo-id=\"#{todo_id}\" data-checkbox-index=\"#{checkbox_index}\" class=\"mr-2 my-0 align-middle\">"
              else
                "<input type=\"checkbox\" checked disabled class=\"mr-2 my-0 align-middle checkbox-readonly\">"
              end

            updated_line = String.replace(line, ~r/\[x\]/i, checkbox_html, global: false)
            {updated_line, checkbox_index + 1}

          # Handle Unicode checkbox symbols (□ and ☑)
          String.contains?(line, "□") ->
            checkbox_html =
              if interactive do
                "<input type=\"checkbox\" data-todo-checkbox data-todo-id=\"#{todo_id}\" data-checkbox-index=\"#{checkbox_index}\" class=\"mr-2 my-0 align-middle\">"
              else
                "<input type=\"checkbox\" disabled class=\"mr-2 my-0 align-middle checkbox-readonly\">"
              end

            updated_line = String.replace(line, "□", checkbox_html, global: false)
            {updated_line, checkbox_index + 1}

          String.contains?(line, "☑") ->
            checkbox_html =
              if interactive do
                "<input type=\"checkbox\" checked data-todo-checkbox data-todo-id=\"#{todo_id}\" data-checkbox-index=\"#{checkbox_index}\" class=\"mr-2 my-0 align-middle\">"
              else
                "<input type=\"checkbox\" checked disabled class=\"mr-2 my-0 align-middle checkbox-readonly\">"
              end

            updated_line = String.replace(line, "☑", checkbox_html, global: false)
            {updated_line, checkbox_index + 1}

          true ->
            {line, checkbox_index}
        end
      end)

    Enum.join(processed_lines, "\n")
  end
end
