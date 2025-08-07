defmodule LifeOrgWeb.Components.LinkPreviewComponent do
  use Phoenix.Component
  
  @moduledoc """
  Components for rendering link previews with loading and error states.
  
  These components provide a consistent interface for displaying link previews
  across todos, journal entries, and comments.
  """

  @doc """
  Renders a container for link previews with loading state.
  """
  def link_preview_container(assigns) do
    ~H"""
    <div id={@id} class="link-preview-container" phx-hook="LinkPreviewLoader" data-content={@content}>
      <%= if @loading do %>
        <.loading_preview />
      <% else %>
        <%= Phoenix.HTML.raw(@processed_content) %>
      <% end %>
    </div>
    """
  end

  @doc """
  Loading state for link previews.
  """
  def loading_preview(assigns) do
    ~H"""
    <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 animate-pulse mt-2 mb-2">
      <div class="w-12 h-12 bg-gray-300 rounded flex-shrink-0"></div>
      <div class="flex-1 min-w-0">
        <div class="h-4 bg-gray-300 rounded mb-2"></div>
        <div class="h-3 bg-gray-300 rounded w-3/4 mb-2"></div>
        <div class="h-3 bg-gray-300 rounded w-1/2"></div>
      </div>
    </div>
    """
  end

  @doc """
  Error state for link previews.
  """
  def error_preview(assigns) do
    ~H"""
    <div class="flex items-center gap-2 p-2 text-sm text-gray-500 bg-gray-50 rounded mt-1 mb-1">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z"></path>
      </svg>
      <span>Preview unavailable</span>
    </div>
    """
  end

  @doc """
  Compact link preview for inline display.
  """
  def compact_preview(assigns) do
    assigns = assign_new(assigns, :show_domain, fn -> true end)
    
    ~H"""
    <a href={@url} target="_blank" rel="noopener noreferrer" 
       class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 hover:bg-gray-100 rounded text-sm border transition-colors max-w-sm">
      <svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.102m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
      </svg>
      <span class="truncate font-medium"><%= @title %></span>
      <%= if @show_domain do %>
        <span class="text-xs text-gray-500 flex-shrink-0"><%= @domain %></span>
      <% end %>
    </a>
    """
  end

  @doc """
  Standard link preview card.
  """
  def standard_preview(assigns) do
    assigns = assign_new(assigns, :clickable, fn -> true end)
    
    ~H"""
    <div class={[
      "flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 transition-colors mt-2 mb-2",
      @clickable && "hover:border-gray-300 cursor-pointer"
    ]}
    onclick={@clickable && "window.open('#{@url}', '_blank')"}>
      <%= if @image do %>
        <div class="w-12 h-12 bg-gray-200 rounded flex-shrink-0 overflow-hidden">
          <img src={@image} alt="" class="w-full h-full object-cover" onerror="this.style.display='none'" loading="lazy">
        </div>
      <% else %>
        <div class="w-12 h-12 bg-gray-200 rounded flex-shrink-0 flex items-center justify-center">
          <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.102m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
          </svg>
        </div>
      <% end %>
      <div class="flex-1 min-w-0">
        <h4 class="font-medium text-gray-900 truncate"><%= @title %></h4>
        <%= if @description do %>
          <p class="text-sm text-gray-600 mt-1 line-clamp-2"><%= @description %></p>
        <% end %>
        <div class="flex items-center gap-1 mt-2">
          <span class="text-xs text-gray-500"><%= @domain %><%= if @site_name do %> • <%= @site_name %><% end %></span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Expanded link preview for detailed display.
  """
  def expanded_preview(assigns) do
    ~H"""
    <div class="p-4 bg-white rounded-lg border border-gray-200 shadow-sm hover:shadow-md transition-shadow mt-3 mb-3 max-w-lg">
      <%= if @image do %>
        <div class="w-full h-48 bg-gray-200 rounded-lg overflow-hidden mb-4">
          <img src={@image} alt="" class="w-full h-full object-cover" loading="lazy">
        </div>
      <% end %>
      <div>
        <h3 class="text-lg font-semibold text-gray-900 mb-1"><%= @title %></h3>
        <%= if @description do %>
          <p class="text-gray-600 mt-2"><%= @description %></p>
        <% end %>
        <div class="flex items-center gap-1 mt-3 pt-3 border-t border-gray-100">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.102m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
          </svg>
          <a href={@url} target="_blank" rel="noopener noreferrer" class="text-sm text-gray-500 hover:text-blue-600 transition-colors">
            <%= @domain %><%= if @site_name do %> • <%= @site_name %><% end %>
          </a>
        </div>
      </div>
    </div>
    """
  end
end