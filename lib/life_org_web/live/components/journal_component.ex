defmodule LifeOrgWeb.Components.JournalComponent do
  use Phoenix.Component
  import LifeOrgWeb.MarkdownHelper
  import LifeOrgWeb.Components.ModalComponent
  import LifeOrgWeb.Components.RichTextEditorComponent

  def journal_column(assigns) do
    ~H"""
    <div class="w-1/2 bg-white border-r border-gray-200 overflow-y-auto" phx-hook="ClearJournalForm" id="journal-column">
      <div class="p-6">
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-2xl font-bold text-gray-800">Journal Entries</h2>
          <button
            phx-click="expand_journal"
            class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
            title="Expand journal view"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"></path>
            </svg>
          </button>
        </div>

        <.journal_form processing_journal_todos={assigns[:processing_journal_todos] || false} />
        <.journal_entries entries={@entries} />

        <!-- Edit Journal Entry Modal -->
        <%= if assigns[:editing_entry] do %>
          <.modal id="edit-journal-modal" title="Edit Journal Entry">
            <.edit_journal_form entry={@editing_entry} />
          </.modal>
        <% end %>
      </div>
    </div>
    """
  end

  def journal_form(assigns) do
    assigns = assign(assigns, :today, Date.utc_today() |> Date.to_string())
    assigns = assign_new(assigns, :processing_journal_todos, fn -> false end)

    ~H"""
    <form id="journal-form" phx-submit="create_journal_entry" class="mb-6">
      <.rich_text_editor
        id="journal-content"
        name="journal_entry[content]"
        placeholder="Write your thoughts..."
        required={true}
        min_height="150px"
        class="mb-3"
      />
      <div class="mt-3 space-y-2">
        <input
          id="journal-date"
          type="date"
          name="journal_entry[entry_date]"
          value={@today}
          class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
        />
        <div class="relative">
          <button type="submit" class="w-full px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors" disabled={@processing_journal_todos}>
            <%= if @processing_journal_todos do %>
              <span class="flex items-center justify-center">
                <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Processing...
              </span>
            <% else %>
              Add Entry
            <% end %>
          </button>
          <%= if @processing_journal_todos do %>
            <div class="mt-2 text-sm text-blue-600 text-center">
              Extracting todos from your journal entry...
            </div>
          <% end %>
        </div>
      </div>
    </form>
    """
  end

  def journal_entries(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= for entry <- @entries do %>
        <.journal_entry_card entry={entry} />
      <% end %>
    </div>
    """
  end

  def journal_entry_card(assigns) do
    ~H"""
    <div class="p-4 bg-gray-50 rounded-lg border border-gray-200 hover:shadow-md transition-shadow">
      <div class="flex justify-between items-start mb-2">
        <span class="text-sm text-gray-500">
          <%= if @entry.entry_date do %>
            <%= Calendar.strftime(@entry.entry_date, "%B %d, %Y") %>
          <% else %>
            <%= Calendar.strftime(@entry.inserted_at, "%B %d, %Y") %>
          <% end %>
        </span>
        <div class="flex gap-2">
          <button
            phx-click="edit_journal_entry"
            phx-value-id={@entry.id}
            class="text-blue-500 hover:text-blue-700"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
            </svg>
          </button>
          <button
            phx-click="delete_journal_entry"
            phx-value-id={@entry.id}
            class="text-red-500 hover:text-red-700"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>
      </div>
      <div class="text-gray-700 prose prose-sm max-w-none">
        <div id={"journal-preview-#{@entry.id}"} class="link-preview-container" phx-hook="LinkPreviewLoader" data-content={Phoenix.HTML.html_escape(@entry.content)}>
          <%= render_markdown(@entry.content) %>
        </div>
      </div>
    </div>
    """
  end

  def edit_journal_form(assigns) do
    entry_date =
      if assigns.entry.entry_date do
        Date.to_string(assigns.entry.entry_date)
      else
        Date.to_string(Date.utc_today())
      end

    assigns = assign(assigns, :entry_date_string, entry_date)

    ~H"""
    <form phx-submit="update_journal_entry" phx-value-id={@entry.id}>
      <div class="space-y-4">
        <div>
          <.rich_text_editor
            id={"edit-journal-content-#{@entry.id}"}
            name="journal_entry[content]"
            label="Content"
            value={@entry.content}
            required={true}
            min_height="150px"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Date</label>
          <input
            type="date"
            name="journal_entry[entry_date]"
            value={@entry_date_string}
            class="w-full p-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            required
          />
        </div>

        <div class="flex justify-end gap-3">
          <button
            type="button"
            phx-click={hide_modal("edit-journal-modal")}
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
end
