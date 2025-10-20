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
      class={"fixed inset-0 #{@z_index_class}"}
      style="display: none; overflow-y: auto; -webkit-overflow-scrolling: touch;"
    >
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black opacity-60"></div>

      <!-- Modal Container -->
      <div class="relative z-10 min-h-full flex items-start sm:items-center justify-center p-0 sm:p-4">
        <div class={"relative bg-white rounded-none sm:rounded-lg shadow-2xl #{@size_class} w-full min-h-screen sm:min-h-0 sm:max-h-[95vh] overflow-y-auto"}>
          <!-- Header -->
          <div class="flex items-center justify-between p-3 sm:p-6 border-b border-gray-200 sticky top-0 bg-white z-20 shadow-sm">
            <h3 class="text-base sm:text-lg font-semibold text-gray-900">
              <%= @title %>
            </h3>
            <button
              type="button"
              phx-click={hide_modal(@id)}
              class="text-gray-400 hover:text-gray-600 flex-shrink-0 p-2 -mr-2"
            >
              <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Content -->
          <div class="p-3 sm:p-6">
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