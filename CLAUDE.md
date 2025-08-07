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
- has_many :todos (reverse reference for todo creation context)

todos:
- id, title, description, completed, priority, due_date, due_time, ai_generated, current, tags (JSON), workspace_id, journal_entry_id (nullable), timestamps
- belongs_to :journal_entry (tracks originating journal entry for AI-created todos)

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
   - Full CRUD operations with modal editing

2. **AI Chat Assistant**
   - Persistent conversation threads
   - Full conversation history sent to AI
   - Context-aware responses using journal entries
   - AI can create and manage todos via tool calls
   - Web search capabilities for current information and resources

3. **Smart Todo Management**
   - Priority-based sorting with current todos at top
   - AI-generated todos from chat conversations
   - Full editing capabilities
   - Due date tracking
   - Start/stop workflow to mark current work items

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
- **Web search integration**: Claude can search the web for current information and resources (120s timeout)
- **Integration System**: Modular decorator pattern for rich link previews (web links, GitHub repos/issues/PRs)

### Integration Architecture
- **Decorator Pattern**: Platform-specific decorators (GitHub, Asana, etc.) provide rich previews for URLs
- **Registry System**: Central registry manages integration discovery and priority-based URL matching
- **Pipeline Processing**: Async content processing with caching to avoid blocking UI
- **JavaScript Hooks**: LinkPreviewLoader handles client-side async loading of processed content
- **Database Caching**: Link metadata cached in MySQL with TTL to reduce API calls
- **Priority System**: Higher priority decorators (GitHub: 10) override generic web decorator (1)
- **OAuth2 Authentication**: Ueberauth-based OAuth2 flows for platform integrations (GitHub, future Asana/Jira)
- **Global User Integrations**: Authentication persists across all workspaces - no re-auth needed per workspace
- **Environment Variables**: Project-specific .env file support with fallback to system environment

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
- Subtle UI elements (icons with badges) preferred over prominent banners
- Bidirectional data relationships enhance user context and navigation
- **Contextual AI Enhancement**: AI systems benefit significantly from prioritizing specific relevant context over generic recent data

## Current Implementation Details

### Todo Management System
- **Manual Todo Creation**: "+" icon button in todo header opens modal form
- **Todo Fields**: title, description, tags (comma-separated), priority (low/medium/high), due_date, due_time
- **Todo Comments**: Each todo supports threaded comments with markdown rendering
- **Tag Filtering**: Filter dropdown allows filtering todos by tags
- **Incoming Todos**: Special section for AI-extracted todos from journal entries (blue banner)
- **Todo Views**: Click todo to view details, hover to see edit/delete buttons
- **Workspace Support**: Todos are scoped to workspaces (default workspace auto-created)
- **Journal Entry References**: Todos created from journal entries maintain bidirectional links for context traceability

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

## Integration System

The application includes a **comprehensive integration system** that automatically enhances content with external information and provides extensibility for future integrations.

### Architecture
- **Multi-Type Integration Support**: Supports decorators (content enhancement), importers (data import), syncers (bidirectional sync), and triggers (automation)
- **Behavior-Based Design**: Uses Elixir behaviors to define contracts for each integration type
- **Registry System**: `LifeOrg.Integrations.Registry` GenServer manages registration and lookup of integrations
- **Link Detection**: `LifeOrg.LinkDetector` extracts URLs from text content using regex patterns
- **Decorator Pipeline**: `LifeOrg.Decorators.Pipeline` processes content asynchronously to inject link previews

### OAuth2 Authentication System (Phase 3 Complete)
- **Ueberauth Integration**: Uses ueberauth and ueberauth_github for OAuth2 flows
- **Global User Integrations**: Auth tokens work across all workspaces (no re-authentication needed)
- **Secure Token Storage**: UserIntegration model stores encrypted credentials and metadata
- **GitHub OAuth2**: Supports private repository access with proper scope management
- **Environment Variables**: Project-specific .env file support using Dotenvy
- **Integration Settings UI**: Web interface for connecting/disconnecting OAuth2 accounts

### GitHub Decorator (Platform Integration)
- **Repository Previews**: Rich cards for GitHub repositories with stars, language, and description
- **Issue/PR Support**: Detailed previews for GitHub issues and pull requests with status badges
- **Private Repository Access**: Uses OAuth2 tokens to access private GitHub repositories
- **Priority-Based Matching**: Higher priority (10) than generic web decorator for GitHub URLs
- **API Rate Limiting**: Proper error handling for GitHub API limits and authentication failures

### Web Link Decorator (Phase 2 Complete)
- **Generic Web Link Support**: Fetches Open Graph, Twitter Card, and standard HTML metadata
- **Caching Layer**: `LifeOrg.LinkFetcher` GenServer provides HTTP fetching with MySQL-backed caching
- **Rich Previews**: Displays title, description, domain, and images in clickable preview cards
- **Real-time Processing**: LiveView triggers async processing when content contains URLs
- **Error Handling**: Graceful fallbacks for failed requests, malformed HTML, or missing metadata

### Key Implementation Details
- **Module Loading**: Uses `Code.ensure_loaded!` to ensure integration modules are available during registration
- **Safe HTML Handling**: Custom `safe_html_escape/1` function handles both raw strings and `{:safe, content}` tuples
- **Prose CSS Override**: Uses `!important` inline styles to override Tailwind prose styling in previews
- **Background Processing**: Uses Phoenix Tasks for async metadata fetching to avoid blocking UI
- **String Slice Compatibility**: Updated to use new Elixir 1.18 syntax (`start..-1//1`)
- **Runtime Configuration**: OAuth2 credentials loaded via runtime.exs after .env file processing

## MCP Server Integration

The application includes a **Model Context Protocol (MCP) server** that enables external AI tools (like Claude Desktop) to interact with the life organizer data.

### Architecture
- **MCP Server**: `LifeOrg.MCPServer` using hermes_mcp library with component-based architecture
- **HTTP Transport**: Accessible at `http://localhost:4000/mcp` via Phoenix endpoint integration
- **Tool Components**:
  - `TodoTools`: Search and filter todos by query, tags, completion status
  - `JournalTools`: Search journal entries by content with mood indicators

### Key Implementation Details
- **Workspace Context**: MCP tools automatically use the default workspace (matches web UI behavior)
- **Response Format**: Uses `{:reply, Response.json(Response.tool(), result), frame}` pattern from hermes_mcp
- **Search-Focused**: Optimized for natural language queries rather than full CRUD operations
- **User-Friendly Output**: Returns formatted text with emojis and visual indicators

### Configuration
```elixir
# Application supervision tree
{LifeOrg.MCPServer, transport: :streamable_http}

# Phoenix endpoint integration
plug Hermes.Server.Transport.StreamableHTTP.Plug,
  server: LifeOrg.MCPServer,
  path: "/mcp"
```

### Usage
External AI tools can connect to query data like "Any Mathler tasks I have listed?" or "Show me recent journal entries about work" and receive properly formatted, contextual responses from the user's actual data.

## Future Enhancement Opportunities

- Search functionality for journal entries (web UI)
- Export capabilities (PDF, markdown)
- Calendar view for journal entries
- Todo recurring tasks
- Mobile responsiveness improvements
- Advanced AI tool calling (calendar integration, reminders)
- MCP server tool expansion (create/update operations, workspace switching)

### Todo-Based AI Chat Architecture
- **Context-Aware AI**: AI knows the specific todo, its comments, related todos, and journal entries
- **Enhanced Context Priority**: For todos created from journal entries, AI receives the full originating journal entry plus recent entries for optimal contextual understanding
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
- **AI Checkbox Support**: AI system prompts are configured to understand GitHub-style markdown checkboxes (`- [ ]`/`- [x]`) in todo descriptions, enabling creation of interactive subtask lists

## Database Constraints & Cascading Deletes
- **Foreign Key Design**: All related entities use `on_delete: :delete_all` for proper cascading
- **Todo Deletion**: Automatically cascades to delete conversations and chat messages
- **Migration Pattern**: When updating constraints in MySQL, use `drop constraint` followed by `modify` (MySQL doesn't support `drop_if_exists` for constraints)
- **Constraint Names**: Follow pattern `{table}_{column}_fkey` (e.g., `chat_messages_conversation_id_fkey`)
- **WorkspaceService**: Relies on database-level cascading rather than manual deletion queries for efficiency