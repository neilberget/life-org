defmodule LifeOrgWeb.Components.ModalComponent do
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  def modal(assigns) do
    size_class = case assigns[:size] do
      "large" -> "max-w-4xl"
      "medium" -> "max-w-2xl"
      _ -> "max-w-md"
    end
    
    z_index_class = case assigns[:z_index] do
      "high" -> "z-60"
      _ -> "z-50"
    end
    
    assigns = assigns
    |> assign(:size_class, size_class)
    |> assign(:z_index_class, z_index_class)
    
    ~H"""
    <div
      id={@id}
      class={"fixed inset-0 #{@z_index_class} overflow-y-auto"}
      style="display: none;"
      phx-click-away={hide_modal(@id)}
    >
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black bg-opacity-50 transition-opacity"></div>
      
      <!-- Modal -->
      <div class="flex min-h-full items-center justify-center p-4">
        <div class={"relative bg-white rounded-lg shadow-xl #{@size_class} w-full"}>
          <!-- Header -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200">
            <h3 class="text-lg font-semibold text-gray-900">
              <%= @title %>
            </h3>
            <button
              type="button"
              phx-click={hide_modal(@id)}
              class="text-gray-400 hover:text-gray-600"
            >
              <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          
          <!-- Content -->
          <div class="p-6">
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_modal(js \\ %JS{}, id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.focus_first(to: "##{id}")
  end

  def hide_modal(js \\ %JS{}, id) do
    js |> JS.hide(to: "##{id}")
  end
end