# Life Organizer - Project Documentation

## Project Overview

A Phoenix LiveView application that helps organize life with journal entries, AI-powered chat assistance, and smart todo management. Built with clean, modern design principles and a focus on user experience.

## Technology Stack

- **Backend**: Elixir/Phoenix LiveView with MySQL database
- **Frontend**: Phoenix LiveView with Tailwind CSS
- **AI Integration**: Anthropic Claude API (claude-sonnet-4-0 model)
- **Database**: MySQL with Ecto ORM
- **Real-time**: Phoenix LiveView for interactive UI

## Architecture & Code Organization

### Component-Based Architecture
- **Modular Components**: Each major feature (Journal, Chat, Todo) has its own component module
- **Reusable Components**: Modal system used across features for consistency
- **Clean Separation**: LiveView handles state management, components handle presentation

### Database Design
```
journal_entries:
- id, content (text), mood, entry_date, tags (JSON), timestamps

todos:
- id, title, description, completed, priority, due_date, due_time, ai_generated, tags (JSON), workspace_id, timestamps

conversations:
- id, title, workspace_id, todo_id (nullable), timestamps

chat_messages:
- id, conversation_id, role, content, timestamps

todo_comments:
- id, todo_id, content, timestamps
```

### Key Features

1. **Journal Management**
   - Markdown support with live rendering
   - Date picker defaulting to today
   - Mood tracking
   - Full CRUD operations with modal editing

2. **AI Chat Assistant**
   - Persistent conversation threads
   - Full conversation history sent to AI
   - Context-aware responses using journal entries
   - AI can create and manage todos via tool calls

3. **Smart Todo Management**
   - Priority-based sorting
   - AI-generated todos from chat conversations
   - Full editing capabilities
   - Due date tracking

4. **Modern UI/UX**
   - Three-column responsive layout
   - Clean modal interfaces
   - Hover interactions
   - Real-time updates

## User's Coding & Architecture Preferences

### Code Organization
- **Component separation**: Prefers breaking complex LiveViews into focused components
- **Clean file structure**: Templates separated from logic (`.html.heex` files)
- **Modular services**: Business logic extracted into service modules (e.g., `ConversationService`)
- **No unnecessary comments**: Code should be self-documenting

### Database & Backend
- **MySQL preference**: Chose MySQL over PostgreSQL for this project
- **Proper migrations**: Always create migrations for schema changes
- **Ecto best practices**: Uses changesets, validations, and associations properly
- **Error handling**: Comprehensive error handling with user-friendly messages

### Frontend & Design
- **Tailwind CSS**: Heavy use of utility classes for styling
- **Clean, modern design**: Professional appearance without unnecessary elements
- **Responsive layout**: Full-screen utilization without default Phoenix headers
- **Interactive elements**: Hover states, loading indicators, smooth transitions

### API Integration
- **Environment configuration**: API keys managed through environment variables
- **Async processing**: Long-running AI requests handled in background tasks
- **Comprehensive logging**: Detailed logging for debugging API interactions
- **Tool calling**: AI can execute actions (create/complete todos) via structured responses

### Development Workflow
- **Fix warnings immediately**: Prefers clean compilation with zero warnings
- **Task-oriented development**: Uses todo tracking to manage feature development
- **Incremental improvements**: Build features iteratively with immediate testing
- **User feedback**: Implements loading states and success/error messages

### UI/UX Philosophy
- **Minimal cognitive load**: Remove unnecessary elements (e.g., "AI Generated" tags)
- **Contextual actions**: Edit buttons appear on hover to reduce visual clutter
- **Consistent interactions**: Reusable modal patterns across features
- **Form usability**: Smart defaults (today's date), proper validation, clear labels

## Development Setup

### Prerequisites
- Elixir 1.14+
- MySQL running (via Docker recommended)
- Node.js for asset compilation

### Environment Variables
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

### Database Configuration
MySQL connection configured for:
- Host: 127.0.0.1 (Docker)
- Username: root
- Password: root
- Database: life_org_dev

### Commands
```bash
# Install dependencies
mix deps.get
cd assets && npm install

# Setup database
mix ecto.create
mix ecto.migrate

# Start server
mix phx.server
```

## Architecture Decisions

### Why LiveView?
- Real-time interactivity without complex JavaScript
- Server-side rendering with rich client-side interactions
- Phoenix ecosystem integration

### Why Component-Based Structure?
- Maintainable code organization
- Reusable UI patterns
- Clear separation of concerns
- Easy testing and debugging

### Why Persistent Conversations?
- Better AI context and memory
- User can return to previous discussions
- Enables complex multi-turn conversations
- Audit trail of AI interactions

### Why MySQL over PostgreSQL?
- User's preference for this project
- Adequate for the data model
- JSON support for flexible fields (tags)

## Key Learning Points

- User prefers clean, professional interfaces over feature-heavy designs
- Component architecture is highly valued for maintainability
- Real-time feedback (loading states, success messages) is essential
- AI integration should feel natural and contextual
- Code should compile without warnings
- Database schema should be thoughtfully designed from the start
- Modal interfaces provide excellent UX for editing operations

## Current Implementation Details

### Todo Management System
- **Manual Todo Creation**: "+" icon button in todo header opens modal form
- **Todo Fields**: title, description, tags (comma-separated), priority (low/medium/high), due_date, due_time
- **Todo Comments**: Each todo supports threaded comments with markdown rendering
- **Tag Filtering**: Filter dropdown allows filtering todos by tags
- **Incoming Todos**: Special section for AI-extracted todos from journal entries (blue banner)
- **Todo Views**: Click todo to view details, hover to see edit/delete buttons
- **Workspace Support**: Todos are scoped to workspaces (default workspace auto-created)

### LiveView Event Handlers (organizer_live.ex)
- `add_todo`: Opens the add todo modal
- `create_todo`: Creates new todo with form data
- `edit_todo`: Opens edit modal for existing todo
- `update_todo`: Updates existing todo
- `delete_todo`: Deletes a todo
- `toggle_todo`: Marks todo as complete/incomplete
- `view_todo`: Opens detailed view modal
- `add_todo_comment`: Adds comment to todo
- `filter_by_tag`: Filters todos by selected tag
- `accept_incoming_todos`: Accepts AI-extracted todos
- `dismiss_incoming_todos`: Deletes all incoming todos
- `toggle_description_checkbox`: Handles interactive checkbox toggling in todo descriptions

### Component Architecture
- **TodoComponent** (`todo_component.ex`): Handles all todo UI rendering with interactive markdown checkboxes
- **Modal System**: Reusable modal component for forms and views
- **Form Components**: `add_todo_form`, `edit_todo_form` with consistent styling
- **Priority Classes**: Visual distinction with colors (red=high, yellow=medium, green=low)
- **JavaScript Hooks**: `InteractiveCheckboxes` for checkbox interactions, `WorkspacePersistence` for localStorage

### Database Schema Extensions
- **todos table**: workspace_id, due_time, tags (JSON array)
- **todo_comments table**: Links comments to todos
- **conversations table**: Added todo_id for todo-specific conversations
- **Workspace scoping**: All entities (todos, journal, conversations) belong to workspaces

### Workspace Persistence
- **localStorage Integration**: Selected workspace persists across sessions using localStorage
- **JavaScript Hook**: `WorkspacePersistence` hook manages localStorage read/write
- **LiveView Events**: 
  - `load_saved_workspace`: Loads persisted workspace on mount
  - `workspace_changed`: Pushed to client to trigger localStorage save
- **WorkspaceService Functions**:
  - `get_workspace/1`: Safe workspace lookup (returns nil if not found)
  - `get_workspace!/1`: Raises if workspace not found

### Journal Todo Extraction Processing State
- **Background Processing**: Journal entries are processed by AI in background tasks to extract todos
- **Non-blocking UI**: Processing state is tracked with `processing_journal_todos` assign
- **Visual Indicators**: 
  - Submit button shows spinner and "Processing..." text during extraction
  - Button is disabled to prevent duplicate submissions
  - Helpful message appears: "Extracting todos from your journal entry..."
- **State Management**:
  - Set to `true` when journal entry is created and background task starts
  - Set to `false` when `handle_info({:extracted_todos, ...})` completes
  - Handled in both success and failure cases to prevent stuck states

### Interactive Markdown Checkboxes in Todo Descriptions
- **GitHub-style Syntax**: Supports `- [ ]` (unchecked) and `- [x]` (checked) markdown syntax
- **Real-time Interactivity**: Checkboxes are clickable and update the todo description in real-time
- **JavaScript Hook**: `InteractiveCheckboxes` hook manages checkbox interactions and prevents modal closing
- **Backend Processing**: 
  - `toggle_description_checkbox` event handler updates markdown in database
  - `update_description_checkbox/3` function handles markdown parsing and checkbox state toggling
  - Optimistic updates with server confirmation via `checkbox_toggle_complete` event
- **Modal State Preservation**: Special handling to keep todo view modal open during checkbox updates
- **Markdown Rendering**: Custom `render_interactive_description/2` function converts markdown checkboxes to interactive HTML inputs

## Future Enhancement Opportunities

- Search functionality for journal entries
- Export capabilities (PDF, markdown)
- Calendar view for journal entries
- Todo recurring tasks
- Mobile responsiveness improvements
- Advanced AI tool calling (calendar integration, reminders)

### Todo-Based AI Chat Architecture
- **Context-Aware AI**: AI knows the specific todo, its comments, related todos, and recent journal entries
- **Conversation Persistence**: Each todo can have multiple persistent chat conversations
- **Tool Integration**: AI can directly modify todos (update fields, complete tasks, create related todos)
- **Modal State Management**: Critical to use `push_event("show_modal")` after state changes to prevent modal closing
- **Two-Column Layout**: Todo details (left) and chat interface (right) when chat is active
- **Specialized Tools**: `create_related_todo`, `update_current_todo`, `complete_current_todo` for focused todo operations
- **Empty Response Handling**: Tool-only AI responses (no text) require special handling to avoid database validation errors

### Modal System Best Practices
- **Click-away behavior**: Temporarily disabled during complex interactions to prevent unexpected modal closing
- **State preservation**: Always ensure `viewing_todo` assign is maintained across state changes
- **Loading states**: Show immediate feedback with loading indicators for all async operations
- **Error resilience**: Handle both AI errors and tool execution failures gracefully
- **Modal Sizing**: Todo form modals use "large" size (max-w-4xl) to provide adequate space for longer descriptions
- **Form UX**: Description textareas are tall (h-40) and vertically resizable to accommodate varying content lengths

## Development Notes
- I'm always running mix phx.server in another tab
- No compiler warnings should be present
- Forms handle empty optional fields gracefully (converted to nil)
- Tags are processed from comma-separated input into JSON arrays
- **AI responses**: Use Earmark for markdown rendering, handle empty responses for tool-only calls
- **Background tasks**: All AI processing happens asynchronously to avoid blocking the UI
- **Interactive Checkboxes**: Use `push_event("show_modal")` after checkbox updates to prevent modal from closing
- **Checkbox State Management**: JavaScript maintains `data-current-state` attributes to handle optimistic updates
- **Event Handling**: Checkbox clicks use `preventDefault()` and `stopPropagation()` to prevent unwanted interactions