defmodule LifeOrgWeb.Components.ProjectSelectComponent do
  use Phoenix.Component

  def project_select(assigns) do
    assigns = assign_new(assigns, :value, fn -> "" end)
    assigns = assign_new(assigns, :existing_projects, fn -> [] end)
    assigns = assign_new(assigns, :field_name, fn -> "projects" end)
    assigns = assign_new(assigns, :placeholder, fn -> "Type to search or create projects..." end)
    
    ~H"""
    <div class="relative" phx-click-away="hide_project_dropdown">
      <input
        type="text"
        name={"todo[#{@field_name}]"}
        value={@value}
        placeholder={@placeholder}
        class="w-full p-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
        phx-keyup="search_projects"
        phx-target={@myself}
        phx-debounce="100"
        autocomplete="off"
        id={"project-input-#{@field_name}"}
      />
      
      <div
        id={"project-dropdown-#{@field_name}"}
        class="absolute z-50 w-full mt-1 bg-white rounded-lg shadow-lg border border-gray-200 hidden max-h-60 overflow-y-auto"
        phx-hook="ProjectDropdown"
      >
        <%= if length(@existing_projects) > 0 do %>
          <div class="p-2">
            <div class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2 px-2">
              Existing Projects
            </div>
            <%= for project <- @existing_projects do %>
              <button
                type="button"
                phx-click="select_project"
                phx-value-project={project.name}
                phx-target={@myself}
                class="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-gray-50 flex items-center gap-2 group"
              >
                <%= if project.favicon_url do %>
                  <img src={project.favicon_url} class="w-4 h-4 flex-shrink-0" alt="" />
                <% else %>
                  <div 
                    class="w-3 h-3 rounded-full flex-shrink-0"
                    style={"background-color: #{project.color}"}
                  ></div>
                <% end %>
                <div class="flex-1 min-w-0">
                  <div class="font-medium"><%= project.name %></div>
                  <%= if project.description && project.description != "" do %>
                    <div class="text-xs text-gray-500 truncate"><%= project.description %></div>
                  <% end %>
                </div>
                <span class="text-xs text-gray-400 ml-auto opacity-0 group-hover:opacity-100">
                  Click to add
                </span>
              </button>
            <% end %>
          </div>
          
          <div class="border-t border-gray-100 p-2">
            <div class="text-xs text-gray-500 px-2">
              Type a new name to create a project
            </div>
          </div>
        <% else %>
          <div class="p-3 text-sm text-gray-500">
            No existing projects. Type to create one.
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end