// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import RichTextEditor from "./hooks/rich_text_editor";

let Hooks = {};

// Rich text editor hook
Hooks.RichTextEditor = RichTextEditor;

// Workspace persistence hook
Hooks.WorkspacePersistence = {
  mounted() {
    // Send the saved workspace ID to the server on mount
    const savedWorkspaceId = localStorage.getItem("selectedWorkspaceId");
    if (savedWorkspaceId) {
      this.pushEvent("load_saved_workspace", { workspace_id: savedWorkspaceId });
    }

    // Listen for workspace changes to save them
    this.handleEvent("workspace_changed", ({ workspace_id }) => {
      localStorage.setItem("selectedWorkspaceId", workspace_id);
    });
  }
};

// Timeline navigation hook for j/k shortcuts
Hooks.TimelineNavigation = {
  mounted() {
    this.handleKeyPress = (event) => {
      // Only handle j/k when not in an input field
      if (event.target.tagName.toLowerCase() === 'input' ||
          event.target.tagName.toLowerCase() === 'textarea' ||
          event.target.contentEditable === 'true') {
        return;
      }

      if (event.key === 'j' || event.key === 'k') {
        event.preventDefault();
        this.pushEvent("navigate_timeline", { key: event.key });
      }
    };

    // Handle scroll to entry event from server
    this.handleEvent("scroll_to_entry", ({ entry_id }) => {
      // Small delay to allow DOM to update after content expansion/collapse
      setTimeout(() => {
        const entryElement = document.querySelector(`[phx-value-id="${entry_id}"]`);
        if (entryElement) {
          entryElement.scrollIntoView({ 
            behavior: 'smooth', 
            block: 'center',
            inline: 'nearest'
          });
        }
      }, 100);
    });

    // Handle scroll to entry on mount (for direct journal/:id URLs)
    this.handleEvent("scroll_to_entry_on_mount", ({ entry_id }) => {
      // Larger delay on mount to ensure DOM is fully loaded
      setTimeout(() => {
        const entryElement = document.querySelector(`[phx-value-id="${entry_id}"]`);
        if (entryElement) {
          entryElement.scrollIntoView({ 
            behavior: 'instant', 
            block: 'center',
            inline: 'nearest'
          });
        }
      }, 200);
    });

    document.addEventListener("keydown", this.handleKeyPress);
  },

  beforeDestroy() {
    if (this.handleKeyPress) {
      document.removeEventListener("keydown", this.handleKeyPress);
    }
  }
};

// Global modal and UI event handlers
Hooks.GlobalEvents = {
  mounted() {
    this.handleEvent("show_modal", ({ id }) => {
      const modal = document.getElementById(id);
      if (modal) modal.style.display = "block";
    });

    this.handleEvent("hide_modal", ({ id }) => {
      const modal = document.getElementById(id);
      if (modal) modal.style.display = "none";
    });

    this.handleEvent("toggle_dropdown", ({ id }) => {
      const dropdown = document.getElementById(id);
      if (dropdown) {
        dropdown.classList.toggle("hidden");
      }
    });

    this.handleEvent("hide_dropdown", ({ id }) => {
      const dropdown = document.getElementById(id);
      if (dropdown) {
        dropdown.classList.add("hidden");
      }
    });

    this.handleEvent("show_comment_form", ({ todo_id }) => {
      setTimeout(() => {
        const form = document.getElementById(`comment-form-${todo_id}`);
        if (form) {
          form.classList.remove("hidden");
        }
      }, 10);
    });

    this.handleEvent("hide_comment_form", () => {
      const forms = document.querySelectorAll('[id^="comment-form-"]');
      forms.forEach(form => form.classList.add("hidden"));
    });

    this.handleEvent("clear_comment_form", ({ todo_id }) => {
      const form = document.getElementById(`comment-form-${todo_id}`);
      if (form) {
        const textarea = form.querySelector('textarea[name="comment[content]"]');
        if (textarea) textarea.value = '';
        form.classList.add("hidden");
      }
    });

    this.handleEvent("clear_timeline_journal_form", () => {
      const form = document.getElementById("timeline-journal-form");
      if (form) {
        const textarea = form.querySelector('textarea[name="journal_entry[content]"]');
        const dateInput = form.querySelector('input[name="journal_entry[entry_date]"]');
        if (textarea) textarea.value = '';
        if (dateInput) dateInput.value = new Date().toISOString().split('T')[0]; // Reset to today
      }
    });

    this.handleEvent("show_todo_chat", ({ todo_id }) => {
      const chat = document.getElementById(`todo-chat-${todo_id}`);
      if (chat) {
        chat.classList.remove("hidden");
      }
    });

    this.handleEvent("hide_todo_chat", ({ todo_id }) => {
      const chat = document.getElementById(`todo-chat-${todo_id}`);
      if (chat) {
        chat.classList.add("hidden");
      }
    });
  }
};

Hooks.ClearJournalForm = {
  mounted() {
    this.handleEvent("clear_journal_form", () => {
      // Clear the rich text editor
      const richTextEditor = document.getElementById("journal-content");
      if (richTextEditor) {
        // Try to find the Quill instance and clear it
        const quillContainer = richTextEditor.querySelector('.ql-editor');
        if (quillContainer) {
          quillContainer.innerHTML = '<p><br></p>'; // Clear Quill content
        }
        // Also clear the hidden input
        const hiddenInput = richTextEditor.querySelector('input[type="hidden"]');
        if (hiddenInput) {
          hiddenInput.value = '';
        }
      }

      // Clear the mood field (if it exists)
      const moodField = document.getElementById("journal-mood");
      if (moodField) moodField.value = "";

      // Reset date to today
      const dateField = document.getElementById("journal-date");
      if (dateField) {
        const today = new Date().toISOString().split('T')[0];
        dateField.value = today;
      }
    });
  }
};

// Interactive checkbox handler for todo descriptions
Hooks.InteractiveCheckboxes = {
  mounted() {
    this.setupCheckboxListeners();

    // Listen for custom event from LinkPreviewLoader to re-setup listeners
    this.el.addEventListener('checkbox-setup-needed', () => {
      this.setupCheckboxListeners();
    });

    // Handle the completion event from server
    this.handleEvent("checkbox_toggle_complete", ({ todo_id, checkbox_index, checked }) => {
      // Confirm the checkbox state matches what server says
      const checkbox = this.el.querySelector(`input[data-todo-id="${todo_id}"][data-checkbox-index="${checkbox_index}"]`);
      if (checkbox) {
        checkbox.checked = checked;
        checkbox.setAttribute('data-current-state', checked);
      }
    });
  },

  updated() {
    // Only re-setup if we don't have listeners
    this.setupCheckboxListeners();
  },

  setupCheckboxListeners() {
    const checkboxes = this.el.querySelectorAll('input[type="checkbox"][data-todo-checkbox]');

    checkboxes.forEach(checkbox => {
      // Only attach if not already attached (avoid duplicates)
      if (checkbox.hasAttribute('data-listener-attached')) {
        return;
      }

      // Store initial state
      checkbox.setAttribute('data-current-state', checkbox.checked);
      checkbox.setAttribute('data-listener-attached', 'true');

      // Add click listener with proper cleanup
      const clickHandler = (event) => {
        // Prevent all propagation
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();

        const todoId = checkbox.getAttribute('data-todo-id');
        const checkboxIndex = checkbox.getAttribute('data-checkbox-index');

        // Toggle state
        const wasChecked = checkbox.getAttribute('data-current-state') === 'true';
        const isChecked = !wasChecked;

        // Update visual state immediately (optimistic update)
        checkbox.checked = isChecked;
        checkbox.setAttribute('data-current-state', isChecked);

        // Send update to server
        this.pushEvent("toggle_description_checkbox", {
          "todo-id": todoId,
          "checkbox-index": checkboxIndex,
          "checked": isChecked.toString()
        });
      };

      checkbox.addEventListener('click', clickHandler, true);
      
      // Store handler reference for potential cleanup
      checkbox._checkboxHandler = clickHandler;
    });
  }
};

// Link preview loader hook
Hooks.LinkPreviewLoader = {
  mounted() {
    this.loadPreviews();
  },

  updated() {
    this.loadPreviews();
  },

  loadPreviews() {
    const content = this.el.getAttribute('data-content');
    if (!content) return;

    // Check if content has changed since last processing
    const lastContent = this.el.getAttribute('data-last-content');
    if (lastContent === content && this.el.getAttribute('data-processed') === 'true') {
      return; // Skip if content hasn't changed
    }

    // Only process if there are actual URLs to process
    if (!content.match(/https?:\/\/[^\s]+/)) {
      // No URLs found, just mark as processed without server call
      this.el.setAttribute('data-processed', 'true');
      this.el.setAttribute('data-last-content', content);
      return;
    }

    // Mark as processed and store the content we're processing
    this.el.setAttribute('data-processed', 'true');
    this.el.setAttribute('data-last-content', content);
    
    // Store the current HTML (with interactive checkboxes) as a fallback
    const currentHTML = this.el.innerHTML;
    
    // Show loading state
    this.el.innerHTML = this.getLoadingHTML();
    
    // Process content with link previews, sending current HTML to preserve checkboxes
    this.pushEvent("process_link_previews", { content: content, html: currentHTML }, (reply) => {
      if (reply.processed_content) {
        this.el.innerHTML = reply.processed_content;
        // After replacing content, trigger any parent InteractiveCheckboxes hook to re-setup listeners
        this.triggerParentCheckboxSetup();
      } else if (reply.error) {
        console.warn("Link preview processing failed:", reply.error);
        // Use the current HTML (with checkboxes) as fallback instead of raw content
        this.el.innerHTML = currentHTML;
      }
    });
  },

  getLoadingHTML() {
    return `
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 animate-pulse mt-2 mb-2">
        <div class="w-12 h-12 bg-gray-300 rounded flex-shrink-0"></div>
        <div class="flex-1 min-w-0">
          <div class="h-4 bg-gray-300 rounded mb-2"></div>
          <div class="h-3 bg-gray-300 rounded w-3/4 mb-2"></div>
          <div class="h-3 bg-gray-300 rounded w-1/2"></div>
        </div>
      </div>
    `;
  },

  triggerParentCheckboxSetup() {
    // Find the parent element with InteractiveCheckboxes hook and trigger it to re-setup listeners
    let parent = this.el.parentElement;
    while (parent) {
      if (parent.getAttribute && parent.getAttribute('phx-hook') && 
          parent.getAttribute('phx-hook').includes('InteractiveCheckboxes')) {
        // Use a custom event to trigger the hook to re-setup
        const event = new CustomEvent('checkbox-setup-needed');
        parent.dispatchEvent(event);
        break;
      }
      parent = parent.parentElement;
    }
  }
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", _info => topbar.show(300));
window.addEventListener("phx:page-loading-stop", _info => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

