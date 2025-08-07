defmodule LifeOrgWeb.Components.RichTextEditorComponent do
  use Phoenix.Component
  import LifeOrgWeb.CoreComponents

  @moduledoc """
  A reusable rich text editor component using Quill.js with LiveView integration.

  This component provides:
  - Rich text editing with toolbar (bold, italic, lists, links, etc.)
  - HTML to Markdown conversion for clean storage
  - Real-time updates via LiveView
  - Form integration with validation
  - Customizable placeholder and styling
  """

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:value, :string, default: "")
  attr(:placeholder, :string, default: "Write something...")
  attr(:label, :string, default: nil)
  attr(:required, :boolean, default: false)
  attr(:errors, :list, default: [])
  attr(:class, :string, default: "")
  attr(:min_height, :string, default: "200px")
  attr(:rest, :global)

  def rich_text_editor(assigns) do
    ~H"""
    <div class={["rich-text-editor-wrapper", @class]}>
      <%= if @label do %>
        <label for={@id} class="block text-sm font-medium text-gray-700 mb-2">
          {@label}
          <%= if @required do %>
            <span class="text-red-500">*</span>
          <% end %>
        </label>
      <% end %>

      <div
        id={@id}
        phx-hook="RichTextEditor"
        data-field={@name}
        data-placeholder={@placeholder}
        data-initial-content={@value}
        class="rich-text-editor border border-gray-300 rounded-lg focus-within:ring-2 focus-within:ring-blue-500 focus-within:border-blue-500"
        {@rest}
      >
        <div
          class="rich-text-content"
          style={"min-height: #{@min_height}"}
        ></div>

        <!-- Hidden input for form submission -->
        <input type="hidden" name={@name} value={@value} />
      </div>

      <!-- Error display -->
      <div class="rich-text-errors mt-2" style="display: none;"></div>

      <%= if @errors != [] do %>
        <div class="mt-2">
          <.error :for={msg <- @errors}>{msg}</.error>
        </div>
      <% end %>
    </div>
    """
  end
end
