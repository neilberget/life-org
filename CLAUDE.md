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
- id, title, description, completed, priority, due_date, ai_generated, timestamps

conversations:
- id, title, timestamps

chat_messages:
- id, conversation_id, role, content, timestamps
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

## Future Enhancement Opportunities

- Search functionality for journal entries
- Export capabilities (PDF, markdown)
- Calendar view for journal entries
- Todo recurring tasks
- Mobile responsiveness improvements
- Advanced AI tool calling (calendar integration, reminders)