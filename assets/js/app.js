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
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

// Global modal and UI event handlers
Hooks.GlobalEvents = {
  mounted() {
    this.handleEvent("show_modal", ({id}) => {
      const modal = document.getElementById(id)
      if (modal) modal.style.display = "block"
    })
    
    this.handleEvent("hide_modal", ({id}) => {
      const modal = document.getElementById(id)
      if (modal) modal.style.display = "none"
    })
    
    this.handleEvent("toggle_dropdown", ({id}) => {
      const dropdown = document.getElementById(id)
      if (dropdown) {
        dropdown.classList.toggle("hidden")
      }
    })
    
    this.handleEvent("hide_dropdown", ({id}) => {
      const dropdown = document.getElementById(id)
      if (dropdown) {
        dropdown.classList.add("hidden")
      }
    })
    
    this.handleEvent("show_comment_form", ({todo_id}) => {
      setTimeout(() => {
        const form = document.getElementById(`comment-form-${todo_id}`)
        if (form) {
          form.classList.remove("hidden")
        }
      }, 10)
    })
    
    this.handleEvent("hide_comment_form", () => {
      const forms = document.querySelectorAll('[id^="comment-form-"]')
      forms.forEach(form => form.classList.add("hidden"))
    })
    
    this.handleEvent("clear_comment_form", ({todo_id}) => {
      const form = document.getElementById(`comment-form-${todo_id}`)
      if (form) {
        const textarea = form.querySelector('textarea[name="comment[content]"]')
        if (textarea) textarea.value = ''
        form.classList.add("hidden")
      }
    })
    
    this.handleEvent("show_todo_chat", ({todo_id}) => {
      const chat = document.getElementById(`todo-chat-${todo_id}`)
      if (chat) {
        chat.classList.remove("hidden")
      }
    })
    
    this.handleEvent("hide_todo_chat", ({todo_id}) => {
      const chat = document.getElementById(`todo-chat-${todo_id}`)
      if (chat) {
        chat.classList.add("hidden")
      }
    })
  }
}

Hooks.ClearJournalForm = {
  mounted() {
    this.handleEvent("clear_journal_form", () => {
      // Clear the textarea
      const contentField = document.getElementById("journal-content")
      if (contentField) contentField.value = ""
      
      // Clear the mood field
      const moodField = document.getElementById("journal-mood")
      if (moodField) moodField.value = ""
      
      // Reset date to today
      const dateField = document.getElementById("journal-date")
      if (dateField) {
        const today = new Date().toISOString().split('T')[0]
        dateField.value = today
      }
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

