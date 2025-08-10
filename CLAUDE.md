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
users:
- id, email, hashed_password, confirmed_at, timestamps
- has_many :workspaces (user isolation)

workspaces:
- id, name, description, color, is_default, user_id, timestamps
- belongs_to :user (ensures data isolation)
- unique constraint on (user_id, name)

journal_entries:
- id, content (text), mood, entry_date, tags (JSON), workspace_id, timestamps
- belongs_to :workspace, has_many :todos

todos:
- id, title, description, completed, priority, due_date, due_time, ai_generated, current, tags (JSON), workspace_id, journal_entry_id (nullable), timestamps
- belongs_to :workspace, belongs_to :journal_entry

conversations:
- id, title, workspace_id, todo_id (nullable), journal_entry_id (nullable), timestamps
- belongs_to :workspace, belongs_to :todo, belongs_to :journal_entry

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
   - **Dedicated Journal Entry Views**: Individual journal entries accessible via `/journal/:id` with two-column layout
   - **Journal Chat Integration**: Each journal entry supports AI chat conversations in dedicated right-column interface
   - **Todo Extraction Conversations**: Todo extraction process creates first conversation with full AI interaction history

2. **AI Chat Assistant**
   - Persistent conversation threads
   - Full conversation history sent to AI
   - Context-aware responses using journal entries
   - AI can create, update, complete, and delete todos via tool calls
   - Web search capabilities for current information and resources
   - Real-time UI synchronization when AI modifies data

3. **Smart Todo Management**
   - Priority-based sorting with current todos at top
   - AI-generated todos from chat conversations
   - Full editing capabilities including AI-driven CRUD operations
   - Due date tracking
   - Start/stop workflow to mark current work items
   - Real-time UI updates when AI tools modify todos
   - Individual todo routing (`/todo/:id`) with direct linking
   - Copy-to-clipboard functionality for sharing todo links

4. **Modern UI/UX**
   - Three-column responsive layout
   - Clean modal interfaces
   - Hover interactions
   - Real-time updates

## Authentication & User Isolation

### User Authentication System
- **Phoenix Generated Auth**: Uses `mix phx.gen.auth` with bcrypt password hashing
- **No Public Registration**: Registration disabled, users created via `mix user.create <email> <password>` task
- **Session-based**: Standard Phoenix session authentication with remember_me functionality
- **LiveView Integration**: Uses `on_mount {LifeOrgWeb.UserAuth, :ensure_authenticated}` for protected LiveViews
- **Password Requirements**: Minimum 8 characters for local development

### Workspace Scoping & Data Isolation
- **User-Scoped Workspaces**: Each user can only access their own workspaces
- **Automatic Default Workspace**: New users automatically get a "Personal" workspace
- **Complete Data Isolation**: All entities (journal entries, todos, conversations) are scoped to user's workspaces
- **Service Layer Updates**: WorkspaceService functions require user_id parameter for proper scoping
- **Database Constraints**: Foreign key relationships ensure data integrity and cascading deletes

### Mix Tasks for User Management
```bash
mix user.create <email> <password>    # Create and confirm new user with default workspace
mix user.list                         # List all users with confirmation status
mix user.delete <email>               # Delete user and all associated data
```

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
- **AI Chat Prominence**: Dual-mode AI interface - compact 400px sidebar for quick access, expandable to full-screen view for intensive AI interactions

### API Integration
- **Environment configuration**: API keys managed through environment variables
- **Async processing**: Long-running AI requests handled in background tasks
- **Comprehensive logging**: Detailed logging for debugging API interactions
- **Tool calling**: AI can execute actions (create/complete todos) via structured responses
- **Web search integration**: Claude can search the web for current information and resources (120s timeout)
- **Integration System**: Modular decorator pattern for rich link previews (web links, GitHub repos/issues/PRs)
- **Retry Mechanism**: Automatic retry with exponential backoff for API timeout errors (up to 2 retries, 2s/4s delays)

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
- **Compact Overview Design**: Overview columns use truncated content to maximize information density
  - Todo descriptions limited to single line with 80-character truncation
  - Journal entries limited to 4 lines with CSS line-clamp for preview
  - Full content accessible via click-to-view interaction pattern
- **Live Search Experience**: Instant dropdown search with debounced queries
  - SearchDropdownComponent provides live results as user types
  - Keyboard navigation with arrow keys and Enter
  - Direct navigation to items without page reload
  - Content type indicators (icons and labels) for clarity

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
- **Completed Todo Visibility**: Completed todos hidden by default with toggle button showing count, auto-clears "current" status when marking complete
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
- **SearchDropdownComponent** (`search_dropdown_component.ex`): Live search with dropdown results
  - Debounced search (300ms) to reduce API calls
  - Parent LiveView handles search execution via `handle_info` callbacks
  - Results formatted as maps with type, id, content, and metadata fields
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

### OAuth2 Authentication System
- **Ueberauth Integration**: Uses ueberauth with provider-specific strategies (GitHub, Asana)
- **Global User Integrations**: Auth tokens work across all workspaces (no re-authentication needed)
- **Secure Token Storage**: UserIntegration model stores encrypted credentials and metadata
- **Environment Variables**: Project-specific .env file support using Dotenvy
- **Integration Settings UI**: Web interface for connecting/disconnecting OAuth2 accounts
- **Provider Support**: GitHub (private repos), Asana (tasks/projects), with extensible framework for more

### Platform Decorators
- **GitHub Decorator**: Repository, issue, and PR previews with OAuth2 support for private repos
- **Asana Decorator**: Task and project previews with assignee, due dates, completion status
- **Web Link Decorator**: Generic Open Graph/Twitter Card metadata for fallback
- **Priority System**: Platform decorators (priority 10) override generic web decorator (priority 1)
- **Multiple Preview Sizes**: Compact, normal, and expanded rendering modes

### Key Implementation Details
- **Module Loading**: Uses `Code.ensure_loaded!` to ensure integration modules are available during registration
- **Safe HTML Handling**: Custom `safe_html_escape/1` function handles both raw strings and `{:safe, content}` tuples
- **Background Processing**: Uses Phoenix Tasks for async metadata fetching to avoid blocking UI
- **Runtime Configuration**: OAuth2 credentials loaded via runtime.exs after .env file processing
- **Error Handling**: Graceful fallbacks for failed requests, API limits, and missing authentication

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
- **Multi-Step Tool Execution**: AI can perform complex operations requiring multiple tool calls in sequence (e.g., fetch todo data, then update based on that data)
- **Recursive Tool Processing**: The system recursively handles AI responses containing additional tools until a final text response is received
- **Modal State Management**: Critical to use `push_event("show_modal")` after state changes to prevent modal closing
- **Two-Column Layout**: Todo details (left) and chat interface (right) when chat is active
- **Specialized Tools**: `create_related_todo`, `update_current_todo`, `complete_current_todo`, `get_todo_by_id` for focused todo operations
- **Flexible ID Support**: `get_todo_by_id` tool accepts both numeric IDs ("42") and full URLs ("http://localhost:4000/todo/42")
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
- **AI Tool UI Synchronization**: All AI tool actions (create, update, complete, delete) must update the LiveView assigns to trigger real-time UI updates - handled in three locations: general chat, journal extraction, and todo-specific chat
- **Multi-Step Tool Execution Bug**: Fixed critical issue where general chat AI tool execution would fail on multi-step tool calls (when AI makes follow-up responses containing additional tools). The `execute_tools_and_continue` function now includes recursive tool handling matching the todo-specific chat implementation

## Admin & Monitoring

### API Usage Logging
- **ApiLog Schema**: Comprehensive logging of all AI API interactions (request_data, response_data, tokens, duration)
- **Decimal Handling**: Database returns Decimal types for aggregated fields - helper functions convert safely to integers/floats
- **Admin Interface**: `/admin/api_usage` provides dual-view API call inspection:
  - **Conversation View**: Human-friendly display of system prompts, messages, and responses with proper styling
  - **Raw JSON View**: Complete request/response data for debugging
- **Visual Design**: Role-based styling with icons (👤 User, 🤖 Assistant, ⚙️ System) and color-coded backgrounds

## Vector Search & Embeddings

### Architecture
- **OpenAI Integration**: Uses `openai_ex` library with text-embedding-3-small model for generating 1536-dimensional embeddings
- **AI Search Tool**: `search_content` tool enables AI to perform semantic searches with content type, date range, and status filtering
- **Background Processing**: `EmbeddingsWorker` GenServer continuously processes content without embeddings (batch size: 5, interval: 30s)
- **Conditional Startup**: Worker only starts when OPENAI_API_KEY environment variable is present
- **Database Storage**: Embeddings stored as JSON arrays in MySQL with `embedding` and `embedding_generated_at` columns

### Search Implementation
- **Semantic Search**: Cosine similarity calculation for vector distance comparison
- **Unified Search**: Searches across both journal entries and todos simultaneously
- **Real-time UI**: Search overlay with similarity scores and type indicators
- **Workspace Scoping**: All searches respect workspace boundaries
- **Performance**: Indexed `embedding_generated_at` columns for efficient querying of unprocessed content

### Key Technical Decisions
- **DateTime Handling**: Must use `DateTime.truncate(:second)` for MySQL compatibility with :utc_datetime fields
- **Pattern Matching**: OpenAI API returns string keys in maps (e.g., `%{"data" => ...}` not `%{data: ...}`)
- **Error Resilience**: Graceful fallback when API key missing - search functionality disabled but app continues working
- **Processing Pipeline**: Two-step process - generate embedding via API, then store with proper timestamp truncation

### AI System Prompt Optimization
- **Context Reduction Strategy**: Dramatically reduced baseline context sent to AI by replacing full content with summary statistics
- **General Chat Optimization**: Changed from sending 5 full journal entries + all todos (~3000 tokens) to summary statistics + priority items only (~800 tokens)
- **Todo Chat Optimization**: Reduced from all related todos + recent entries (~2000 tokens) to originating entry only + search instructions (~1000 tokens)
- **Semantic Search Integration**: AI uses `search_content` tool to pull relevant context on-demand instead of receiving everything upfront
- **Performance Impact**: ~60% reduction in prompt tokens while maintaining AI capability through intelligent search functionality

## Database Constraints & Cascading Deletes
- **Foreign Key Design**: All related entities use `on_delete: :delete_all` for proper cascading
- **Todo Deletion**: Automatically cascades to delete conversations and chat messages
- **Migration Pattern**: When updating constraints in MySQL, use `drop constraint` followed by `modify` (MySQL doesn't support `drop_if_exists` for constraints)
- **Constraint Names**: Follow pattern `{table}_{column}_fkey` (e.g., `chat_messages_conversation_id_fkey`)
- **WorkspaceService**: Relies on database-level cascading rather than manual deletion queries for efficiency

## Enhanced Journal-to-Todos Pipeline

The journal extraction system was enhanced with **vector search integration** to create more sophisticated, context-aware todo extraction.

### Pipeline Architecture
- **Multi-Round Tool Processing**: `execute_tools_and_extract_final_actions/8` handles AI responses that require multiple rounds of tool execution
- **Context Discovery Phase**: AI first uses `search_content` tool to find semantically similar past entries and todos before creating new todos
- **Pattern Recognition**: System analyzes historical completion patterns, priorities, and relationships for better todo creation
- **Smart Deduplication**: Uses semantic similarity rather than exact string matching to avoid duplicate todos

### Key Implementation Details
- **Tool Result Processing**: Enhanced `format_tool_result/2` to handle search results, todo creation/updates, and Ecto.Changeset errors
- **Error Handling**: Robust handling of changeset validation errors with proper error message formatting using `Ecto.Changeset.traverse_errors`
- **Tags Validation**: Ensures tags are always converted to string lists to prevent validation failures
- **Multi-Phase Extraction**: AI can execute search tools, then create todos based on discovered context, then potentially execute more tools

### System Prompt Enhancement
- **Context-Aware Instructions**: AI receives detailed instructions on using search tools before creating todos
- **Historical Pattern Analysis**: Prompts guide AI to consider past patterns, priorities, and tag usage
- **Relationship Building**: Encourages AI to update existing todos and create related todos when appropriate
- **Deduplication Strategy**: Instructs AI to use semantic similarity, not just exact matches, for avoiding duplicates

### Error Patterns & Solutions
- **"Search error:" Formatting**: Fixed tool result formatting to distinguish between actual errors and successful results
- **Changeset Validation Errors**: Added proper handling for Ecto.Changeset protocol errors with meaningful error messages
- **Tags Type Safety**: Ensured tags are always strings to prevent JSON serialization issues
- **Empty Actions Handling**: System properly handles cases where AI executes tools directly without returning explicit actions

### Performance Considerations
- **Background Processing**: All AI processing remains asynchronous to avoid blocking UI
- **UI State Management**: LiveView assigns are updated based on database changes rather than relying solely on returned actions
- **Tool Execution Caching**: Results from search tools are formatted and cached for the AI conversation context

### Conversation History Integration
- **Full Conversation Capture**: The extraction pipeline now captures the complete AI conversation history (system prompts, user messages, tool results, assistant responses)
- **Database Integration**: Extraction conversations are automatically saved to the conversations table with proper journal_entry_id linking
- **UI Consistency**: Extracted todos maintain "incoming todos" UI behavior with accept/dismiss buttons
- **Chat Continuity**: Users can view the complete extraction conversation when opening journal chat, providing full context for follow-up interactions

This enhanced pipeline creates significantly more comprehensive and contextually relevant todos by leveraging the full workspace history through semantic search, while maintaining robust error handling and performance characteristics.