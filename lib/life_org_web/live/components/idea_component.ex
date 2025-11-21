defmodule LifeOrgWeb.Components.IdeaComponent do
  use Phoenix.Component
  import LifeOrgWeb.Components.ModalComponent
  import Phoenix.HTML
  alias LifeOrg.Idea

  def idea_section(assigns) do
    unique_categories = get_unique_categories(assigns.ideas)

    assigns =
      assign(assigns, :unique_categories, unique_categories)
      |> assign(:deleting_idea_id, Map.get(assigns, :deleting_idea_id))

    ~H"""
    <div class="h-1/2 bg-white overflow-y-auto border-t-2 border-gray-200">
      <div class="p-4 md:p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <h2 class="text-2xl font-bold text-gray-800">Ideas</h2>

            <!-- Category Filter Dropdown -->
            <%= if length(@unique_categories) > 0 do %>
              <div class="relative">
                <button
                  phx-click="toggle_category_dropdown"
                  class={"p-1.5 rounded-md transition-colors #{if @category_filter, do: "bg-purple-100 text-purple-600 hover:bg-purple-200", else: "text-gray-500 hover:bg-gray-100"}"}
                  title="Filter by category"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
                  </svg>
                </button>

                <!-- Dropdown Menu -->
                <div
                  id="category-dropdown"
                  class="absolute left-0 mt-2 w-56 bg-white rounded-lg shadow-lg border border-gray-200 z-50 hidden"
                  phx-click-away="hide_category_dropdown"
                >
                  <div class="p-3">
                    <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Filter by Category</h3>
                    <div class="space-y-1 max-h-64 overflow-y-auto">
                      <%= for category <- @unique_categories do %>
                        <button
                          phx-click="filter_by_category"
                          phx-value-category={category}
                          class={"w-full text-left px-3 py-2 text-sm rounded-md transition-colors flex items-center justify-between #{if @category_filter == category, do: "bg-purple-50 text-purple-700", else: "hover:bg-gray-50"}"}
                        >
                          <span><%= category %></span>
                          <%= if @category_filter == category do %>
                            <svg class="w-4 h-4 text-purple-600" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                            </svg>
                          <% end %>
                        </button>
                      <% end %>
                    </div>
                    <%= if @category_filter do %>
                      <div class="mt-2 pt-2 border-t border-gray-200">
                        <button
                          phx-click="clear_category_filter"
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

            <%= if @category_filter do %>
              <div class="flex items-center gap-2">
                <span class="text-xs px-2 py-1 bg-purple-100 text-purple-800 rounded-full flex items-center gap-1">
                  <%= @category_filter %>
                  <button
                    phx-click="clear_category_filter"
                    class="ml-1 hover:text-purple-900"
                  >
                    ✕
                  </button>
                </span>
              </div>
            <% end %>

            <!-- Timeframe Filter -->
            <%= if @timeframe_filter do %>
              <div class="flex items-center gap-2">
                <span class="text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded-full flex items-center gap-1">
                  <%= format_timeframe(@timeframe_filter) %>
                  <button
                    phx-click="clear_timeframe_filter"
                    class="ml-1 hover:text-blue-900"
                  >
                    ✕
                  </button>
                </span>
              </div>
            <% end %>
          </div>

          <button
            phx-click="add_idea"
            class="p-2 rounded-lg text-purple-600 hover:bg-purple-50 transition-colors"
            title="Add new idea"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
            </svg>
          </button>
        </div>

        <%= if Map.get(assigns, :incoming_ideas, []) != [] and !Map.get(assigns, :incoming_ideas_dismissed, false) do %>
          <div class="mb-4 bg-purple-50 border border-purple-200 rounded-lg p-4">
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2">
                <svg class="w-5 h-5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>
                </svg>
                <h3 class="font-semibold text-purple-900">AI Extracted Ideas</h3>
                <span class="text-xs px-2 py-0.5 bg-purple-200 text-purple-800 rounded-full">
                  <%= length(@incoming_ideas) %>
                </span>
              </div>
              <button
                phx-click="dismiss_incoming_ideas"
                class="text-purple-600 hover:text-purple-800"
                title="Dismiss all"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>
            <div class="space-y-2 mb-3">
              <%= for idea <- @incoming_ideas do %>
                <div class="bg-white p-3 rounded border border-purple-200">
                  <div class="font-medium text-gray-900"><%= idea.title %></div>
                  <%= if idea.description do %>
                    <div class="text-sm text-gray-600 mt-1 line-clamp-2"><%= idea.description %></div>
                  <% end %>
                  <div class="flex gap-2 mt-2">
                    <%= if idea.category do %>
                      <span class="text-xs px-2 py-0.5 bg-purple-100 text-purple-700 rounded"><%= idea.category %></span>
                    <% end %>
                    <%= if idea.timeframe do %>
                      <span class="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded"><%= format_timeframe(idea.timeframe) %></span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
            <button
              phx-click="accept_incoming_ideas"
              class="w-full py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors font-medium"
            >
              Accept All Ideas
            </button>
          </div>
        <% end %>

        <div id="idea-list" phx-hook="SortableIdeas" data-list-id="ideas" class="space-y-2">
          <%= for idea <- filter_ideas(@ideas, @category_filter, @timeframe_filter) do %>
            <.idea_item idea={idea} deleting_idea_id={@deleting_idea_id} />
          <% end %>
        </div>

        <%= if length(filter_ideas(@ideas, @category_filter, @timeframe_filter)) == 0 do %>
          <div class="text-center py-12 text-gray-400">
            <svg class="w-16 h-16 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>
            </svg>
            <p class="text-lg">No ideas yet</p>
            <p class="text-sm mt-1">Capture your future thoughts and possibilities</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def idea_item(assigns) do
    ~H"""
    <div
      class="group bg-white border border-gray-200 rounded-lg p-3 hover:border-purple-300 hover:shadow-sm transition-all cursor-pointer"
      data-idea-id={@idea.id}
      phx-click="view_idea"
      phx-value-id={@idea.id}
    >
      <div class="flex items-start justify-between gap-2">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1">
            <%= if @idea.category do %>
              <span class="text-xs px-2 py-0.5 bg-purple-100 text-purple-700 rounded font-medium flex-shrink-0">
                <%= @idea.category %>
              </span>
            <% end %>
            <%= if @idea.timeframe do %>
              <span class="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded flex-shrink-0">
                <%= format_timeframe(@idea.timeframe) %>
              </span>
            <% end %>
            <%= if @idea.status == "converted" do %>
              <span class="text-xs px-2 py-0.5 bg-green-100 text-green-700 rounded flex-shrink-0">
                ✓ Converted
              </span>
            <% end %>
          </div>
          <h3 class="font-semibold text-gray-900 mb-1"><%= @idea.title %></h3>
          <%= if @idea.description do %>
            <p class="text-sm text-gray-600 line-clamp-2"><%= @idea.description %></p>
          <% end %>
          <%= if @idea.tags && length(@idea.tags) > 0 do %>
            <div class="flex flex-wrap gap-1 mt-2">
              <%= for tag <- @idea.tags do %>
                <span class="text-xs px-2 py-0.5 bg-gray-100 text-gray-600 rounded">
                  #<%= tag %>
                </span>
              <% end %>
            </div>
          <% end %>
        </div>
        <div class="flex flex-col gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
          <button
            phx-click="edit_idea"
            phx-value-id={@idea.id}
            class="p-1.5 text-purple-600 hover:bg-purple-50 rounded transition-colors"
            title="Edit"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
            </svg>
          </button>
          <%= if @deleting_idea_id == @idea.id do %>
            <div class="flex flex-col gap-1">
              <button
                phx-click="confirm_delete_idea"
                phx-value-id={@idea.id}
                class="p-1.5 text-white bg-red-600 hover:bg-red-700 rounded transition-colors text-xs"
                title="Confirm delete"
              >
                ✓
              </button>
              <button
                phx-click="cancel_delete_idea"
                class="p-1.5 text-gray-600 hover:bg-gray-100 rounded transition-colors text-xs"
                title="Cancel"
              >
                ✕
              </button>
            </div>
          <% else %>
            <button
              phx-click="delete_idea"
              phx-value-id={@idea.id}
              class="p-1.5 text-red-600 hover:bg-red-50 rounded transition-colors"
              title="Delete"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
              </svg>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def idea_view(assigns) do
    ~H"""
    <.modal id="idea-view" show={true} on_cancel={JS.push("close_idea_view")} size="large">
      <div class="flex flex-col h-[80vh]">
        <div class="flex items-center justify-between mb-4 pb-4 border-b border-gray-200">
          <h2 class="text-2xl font-bold text-gray-900"><%= @idea.title %></h2>
          <div class="flex gap-2">
            <%= if @idea.status != "converted" do %>
              <button
                phx-click="convert_idea_to_todo"
                phx-value-id={@idea.id}
                class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors flex items-center gap-2"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"></path>
                </svg>
                Convert to Todo
              </button>
            <% end %>
            <button
              phx-click="edit_idea"
              phx-value-id={@idea.id}
              class="p-2 text-purple-600 hover:bg-purple-50 rounded-lg transition-colors"
              title="Edit idea"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
              </svg>
            </button>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto prose max-w-none">
          <div class="flex flex-wrap gap-2 mb-4">
            <%= if @idea.category do %>
              <span class="text-sm px-3 py-1 bg-purple-100 text-purple-700 rounded-full font-medium">
                <%= @idea.category %>
              </span>
            <% end %>
            <%= if @idea.timeframe do %>
              <span class="text-sm px-3 py-1 bg-blue-100 text-blue-700 rounded-full">
                <%= format_timeframe(@idea.timeframe) %>
              </span>
            <% end %>
            <%= if @idea.status do %>
              <span class="text-sm px-3 py-1 bg-gray-100 text-gray-700 rounded-full">
                Status: <%= String.capitalize(@idea.status) %>
              </span>
            <% end %>
          </div>

          <%= if @idea.description do %>
            <div class="text-gray-700 whitespace-pre-wrap mb-4">
              <%= @idea.description %>
            </div>
          <% end %>

          <%= if @idea.tags && length(@idea.tags) > 0 do %>
            <div class="mt-4 pt-4 border-t border-gray-200">
              <h3 class="text-sm font-semibold text-gray-600 mb-2">Tags</h3>
              <div class="flex flex-wrap gap-2">
                <%= for tag <- @idea.tags do %>
                  <span class="text-sm px-2 py-1 bg-gray-100 text-gray-600 rounded">
                    #<%= tag %>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @idea.journal_entry do %>
            <div class="mt-4 pt-4 border-t border-gray-200">
              <h3 class="text-sm font-semibold text-gray-600 mb-2">From Journal Entry</h3>
              <a
                href={"/journal/#{@idea.journal_entry_id}"}
                class="text-blue-600 hover:text-blue-800 text-sm"
              >
                View original journal entry →
              </a>
            </div>
          <% end %>
        </div>
      </div>
    </.modal>
    """
  end

  def add_idea_form(assigns) do
    ~H"""
    <.modal id="add-idea" show={true} on_cancel={JS.push("close_add_idea")} size="large">
      <h2 class="text-2xl font-bold mb-6">New Idea</h2>
      <form phx-submit="create_idea" class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Title *</label>
          <input
            type="text"
            name="idea[title]"
            required
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            placeholder="Your idea..."
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
          <textarea
            name="idea[description]"
            rows="8"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent resize-y"
            placeholder="Describe your idea in detail..."
          ></textarea>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Category</label>
            <input
              type="text"
              name="idea[category]"
              class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
              placeholder="e.g., Gift Ideas, Projects, Life"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Timeframe</label>
            <select
              name="idea[timeframe]"
              class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            >
              <option value="">Select timeframe...</option>
              <option value="someday">Someday</option>
              <option value="next_year">Next Year</option>
              <option value="distant_future">Distant Future</option>
            </select>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Tags</label>
          <input
            type="text"
            name="idea[tags]"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            placeholder="Comma-separated tags..."
          />
        </div>

        <div class="flex justify-end gap-3 pt-4">
          <button
            type="button"
            phx-click="close_add_idea"
            class="px-4 py-2 text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors"
          >
            Create Idea
          </button>
        </div>
      </form>
    </.modal>
    """
  end

  def edit_idea_form(assigns) do
    ~H"""
    <.modal id="edit-idea" show={true} on_cancel={JS.push("close_edit_idea")} size="large">
      <h2 class="text-2xl font-bold mb-6">Edit Idea</h2>
      <form phx-submit="update_idea" class="space-y-4">
        <input type="hidden" name="idea[id]" value={@idea.id} />

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Title *</label>
          <input
            type="text"
            name="idea[title]"
            value={@idea.title}
            required
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
          <textarea
            name="idea[description]"
            rows="8"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent resize-y"
          ><%= @idea.description %></textarea>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Category</label>
            <input
              type="text"
              name="idea[category]"
              value={@idea.category}
              class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Timeframe</label>
            <select
              name="idea[timeframe]"
              class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            >
              <option value="">Select timeframe...</option>
              <option value="someday" selected={@idea.timeframe == "someday"}>Someday</option>
              <option value="next_year" selected={@idea.timeframe == "next_year"}>Next Year</option>
              <option value="distant_future" selected={@idea.timeframe == "distant_future"}>Distant Future</option>
            </select>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Tags</label>
          <input
            type="text"
            name="idea[tags]"
            value={Enum.join(@idea.tags || [], ", ")}
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Status</label>
          <select
            name="idea[status]"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <%= for status <- Idea.status_options() do %>
              <option value={status} selected={@idea.status == status}>
                <%= String.capitalize(status) %>
              </option>
            <% end %>
          </select>
        </div>

        <div class="flex justify-end gap-3 pt-4">
          <button
            type="button"
            phx-click="close_edit_idea"
            class="px-4 py-2 text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors"
          >
            Save Changes
          </button>
        </div>
      </form>
    </.modal>
    """
  end

  # Helper functions
  defp get_unique_categories(ideas) do
    ideas
    |> Enum.map(& &1.category)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filter_ideas(ideas, category_filter, timeframe_filter) do
    ideas
    |> Enum.reject(& &1.status == "converted")
    |> then(fn ideas ->
      if category_filter do
        Enum.filter(ideas, & &1.category == category_filter)
      else
        ideas
      end
    end)
    |> then(fn ideas ->
      if timeframe_filter do
        Enum.filter(ideas, & &1.timeframe == timeframe_filter)
      else
        ideas
      end
    end)
  end

  defp format_timeframe(nil), do: ""
  defp format_timeframe("someday"), do: "Someday"
  defp format_timeframe("next_year"), do: "Next Year"
  defp format_timeframe("distant_future"), do: "Distant Future"
  defp format_timeframe(other), do: String.capitalize(other)
end
