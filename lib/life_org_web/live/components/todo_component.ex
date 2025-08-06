defmodule LifeOrgWeb.Components.TodoComponent do
  use Phoenix.Component
  import LifeOrgWeb.Components.ModalComponent
  import Phoenix.HTML

  def todo_column(assigns) do
    unique_tags = get_unique_tags(assigns.all_todos || assigns.todos)
    assigns = assign(assigns, :unique_tags, unique_tags)
    |> assign(:show_tag_dropdown, false)
    
    ~H"""
    <div class="w-1/2 bg-white overflow-y-auto">
      <div class="p-6">
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
          </div>
          
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
        
        <!-- Incoming Todos Section -->
        <%= if Map.get(assigns, :incoming_todos, []) != [] && length(@incoming_todos) > 0 do %>
          <.incoming_todos_section todos={@incoming_todos} />
        <% end %>
        
        <.todo_list todos={@todos} />
        
        <!-- Edit Todo Modal -->
        <%= if Map.get(assigns, :editing_todo) do %>
          <.modal id="edit-todo-modal" title="Edit Todo" z_index="high">
            <.edit_todo_form todo={@editing_todo} />
          </.modal>
        <% end %>
        
        <!-- View Todo Modal -->
        <%= if Map.get(assigns, :viewing_todo) do %>
          <.modal id="view-todo-modal" title="Todo Details" size="large">
            <.todo_view todo={@viewing_todo} comments={Map.get(assigns, :todo_comments, [])} />
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
          <p class="text-sm text-gray-600 mt-1"><%= @todo.description %></p>
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
                <span class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full">
                  #<%= tag %>
                </span>
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
    <div class="space-y-2">
      <%= for todo <- @todos do %>
        <.todo_item todo={todo} />
      <% end %>
    </div>
    """
  end

  def todo_item(assigns) do
    ~H"""
    <div class="flex items-start gap-3 p-3 hover:bg-gray-50 rounded-lg group">
      <input
        type="checkbox"
        checked={@todo.completed}
        phx-click="toggle_todo"
        phx-value-id={@todo.id}
        class="mt-1 h-5 w-5 text-blue-600 rounded border-gray-300 focus:ring-blue-500"
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
              phx-click="edit_todo"
              phx-value-id={@todo.id}
              class="text-blue-500 hover:text-blue-700"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
              </svg>
            </button>
            <button
              phx-click="delete_todo"
              phx-value-id={@todo.id}
              data-confirm="Delete this todo?"
              class="text-red-500 hover:text-red-700"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
            </button>
          </div>
        </div>
        <%= if @todo.description && String.trim(@todo.description) != "" do %>
          <p class="text-sm text-gray-600 mt-1"><%= @todo.description %></p>
        <% end %>
        <div class="flex items-center gap-2 mt-2">
          <%= if @todo.priority do %>
            <span class={"text-xs px-2 py-1 rounded-full #{priority_class(@todo.priority)}"}>
              <%= @todo.priority %>
            </span>
          <% end %>
          <%= if @todo.due_date do %>
            <span class="text-xs text-gray-500">
              📅 <%= format_due_datetime(@todo.due_date, @todo.due_time) %>
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
                <span class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full">
                  #<%= tag %>
                </span>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def edit_todo_form(assigns) do
    due_date = if assigns.todo.due_date do
      Date.to_string(assigns.todo.due_date)
    else
      ""
    end
    
    due_time = if assigns.todo.due_time do
      Time.to_string(assigns.todo.due_time)
    else
      ""
    end
    
    assigns = assigns
    |> assign(:due_date_string, due_date)
    |> assign(:due_time_string, due_time)
    
    ~H"""
    <form phx-submit="update_todo" phx-value-id={@todo.id}>
      <div class="space-y-4">
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
            class="w-full p-3 border border-gray-300 rounded-lg resize-none h-20 focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Optional description..."
          ><%= @todo.description || "" %></textarea>
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

  defp priority_class("high"), do: "bg-red-100 text-red-800"
  defp priority_class("medium"), do: "bg-yellow-100 text-yellow-800"
  defp priority_class("low"), do: "bg-green-100 text-green-800"
  defp priority_class(_), do: "bg-gray-100 text-gray-800"
  
  defp format_due_datetime(date, nil) do
    Date.to_string(date)
  end
  
  defp format_due_datetime(date, time) do
    date_str = Date.to_string(date)
    time_str = Time.to_string(time) |> String.slice(0, 5)  # Show only HH:MM
    "#{date_str} at #{time_str}"
  end
  
  def todo_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Todo Header -->
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <h2 class={"text-2xl font-bold #{if @todo.completed, do: "line-through text-gray-500", else: "text-gray-800"}"}>
            <%= @todo.title %>
          </h2>
          <div class="flex items-center gap-3 mt-2">
            <span class={"px-3 py-1 rounded-full text-sm font-medium #{priority_class(@todo.priority)}"}>
              <%= String.capitalize(@todo.priority || "medium") %>
            </span>
            <%= if @todo.due_date do %>
              <span class="text-gray-600 flex items-center gap-1">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                </svg>
                <%= format_due_datetime(@todo.due_date, @todo.due_time) %>
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
            phx-click="toggle_todo_chat"
            phx-value-id={@todo.id}
            class="p-2 text-purple-600 hover:bg-purple-50 rounded-lg transition-colors"
            title="Chat about this todo"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
            </svg>
          </button>
        </div>
      </div>
      
      <!-- Tags -->
      <%= if @todo.tags && length(@todo.tags) > 0 do %>
        <div class="flex flex-wrap gap-2">
          <%= for tag <- @todo.tags do %>
            <span class="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">
              #<%= tag %>
            </span>
          <% end %>
        </div>
      <% end %>
      
      <!-- Description -->
      <%= if @todo.description && String.trim(@todo.description) != "" do %>
        <div class="bg-gray-50 rounded-lg p-4">
          <h3 class="text-lg font-semibold text-gray-800 mb-3">Description</h3>
          <div class="prose prose-sm prose-gray max-w-none">
            <%= raw(Earmark.as_html!(@todo.description)) %>
          </div>
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
      
      <!-- Chat Interface (always rendered but hidden with CSS) -->
      <div id={"todo-chat-#{@todo.id}"} class="border-t pt-6 hidden">
          <h3 class="text-lg font-semibold text-gray-800 mb-4">Chat about this Todo</h3>
          <div class="bg-gray-50 rounded-lg p-4 h-64 overflow-y-auto mb-3">
            <div class="space-y-3">
              <%= for message <- Map.get(assigns, :todo_chat_messages, []) do %>
                <div class={"flex #{if message.role == "user", do: "justify-end", else: "justify-start"}"}>
                  <div class={"max-w-xs px-3 py-2 rounded-lg #{if message.role == "user", do: "bg-blue-600 text-white", else: "bg-white text-gray-800"}"}>
                    <%= message.content %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          <form phx-submit="send_todo_chat_message" phx-value-todo-id={@todo.id} class="flex gap-2">
            <input
              type="text"
              name="message"
              placeholder="Ask about this todo..."
              class="flex-1 p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              required
            />
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
            >
              Send
            </button>
          </form>
      </div>
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
            <%= Calendar.strftime(@comment.inserted_at, "%B %d, %Y at %I:%M %p") %>
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
end