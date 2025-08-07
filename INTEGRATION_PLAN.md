# Life Organizer - Integration System Plan

## Overview

This document outlines the plan for implementing a multi-type integration system for Life Organizer. The system will support multiple integration types including content decorators (rich link previews), content importers (data import from external systems), and future expansion to syncers and automation triggers.

## Integration Types

### 1. Content Decorators
Enhance existing content with rich previews and metadata from external sources.
- **Use Case**: User pastes an Asana link → shows task title, status, assignee inline
- **Automatic**: Works transparently when URLs are detected
- **Non-invasive**: Doesn't modify stored content, only presentation

### 2. Content Importers  
Import data from external systems as todos or journal entries.
- **Use Case**: Import all tasks from an Asana project as todos
- **Manual**: Requires explicit user action
- **One-way**: External → Life Organizer

### 3. Content Syncers (Future)
Two-way synchronization with external systems.
- **Use Case**: Complete a todo → marks Asana task complete
- **Bidirectional**: Changes sync both ways
- **Conflict Resolution**: Required for concurrent edits

### 4. Automation Triggers (Future)
React to external events to create or modify content.
- **Use Case**: New Asana task assigned → creates todo automatically
- **Event-driven**: Webhooks or polling
- **Rule-based**: User-defined conditions and actions

## Implementation Phases

### Phase 1: Integration Framework Foundation ✅

#### Database Schema ✅
```sql
-- Core integration definitions
CREATE TABLE integrations (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  type ENUM('decorator', 'importer', 'syncer', 'trigger') NOT NULL,
  provider VARCHAR(100) NOT NULL, -- asana, jira, github, web
  config JSON, -- API endpoints, features, etc.
  status ENUM('active', 'inactive') DEFAULT 'active',
  inserted_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

-- User-specific integration settings
CREATE TABLE user_integrations (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  workspace_id BIGINT UNSIGNED NOT NULL,
  integration_id BIGINT UNSIGNED NOT NULL,
  credentials TEXT, -- encrypted JSON
  settings JSON, -- preferences, field mappings
  last_sync_at DATETIME,
  status ENUM('active', 'paused', 'error') DEFAULT 'active',
  inserted_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (workspace_id) REFERENCES workspaces(id),
  FOREIGN KEY (integration_id) REFERENCES integrations(id)
);

-- Cached metadata for decorators
CREATE TABLE link_metadata (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  url VARCHAR(2048) NOT NULL,
  integration_id BIGINT UNSIGNED,
  metadata JSON NOT NULL,
  cached_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  INDEX idx_url (url(255)),
  INDEX idx_expires (expires_at),
  FOREIGN KEY (integration_id) REFERENCES integrations(id)
);

-- Import history for importers
CREATE TABLE import_runs (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  integration_id BIGINT UNSIGNED NOT NULL,
  workspace_id BIGINT UNSIGNED NOT NULL,
  type ENUM('manual', 'scheduled') NOT NULL,
  items_imported INT DEFAULT 0,
  status ENUM('pending', 'running', 'completed', 'failed') NOT NULL,
  started_at DATETIME NOT NULL,
  completed_at DATETIME,
  log JSON,
  inserted_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (integration_id) REFERENCES integrations(id),
  FOREIGN KEY (workspace_id) REFERENCES workspaces(id)
);
```

#### Elixir Schemas ✅
- [x] Create `LifeOrg.Integration` schema
- [x] Create `LifeOrg.UserIntegration` schema  
- [x] Create `LifeOrg.LinkMetadata` schema
- [x] Create `LifeOrg.ImportRun` schema

#### Core Behaviors ✅
```elixir
# Base behavior all integrations implement
defmodule LifeOrg.Integrations.Integration do
  @callback name() :: String.t()
  @callback provider() :: atom()
  @callback capabilities() :: [atom()]
  @callback configure(map()) :: {:ok, map()} | {:error, String.t()}
end

# Type-specific behaviors
defmodule LifeOrg.Integrations.Decorator do
  @callback match_url(String.t()) :: boolean()
  @callback fetch_metadata(String.t(), map()) :: {:ok, map()} | {:error, any()}
  @callback render_preview(map(), map()) :: Phoenix.HTML.safe()
end

defmodule LifeOrg.Integrations.Importer do
  @callback list_importable_items(map()) :: {:ok, [map()]} | {:error, any()}
  @callback import_items([map()], map()) :: {:ok, map()} | {:error, any()}
  @callback map_to_local_schema(map(), atom()) :: map()
end
```

#### Integration Registry ✅
```elixir
defmodule LifeOrg.Integrations.Registry do
  # Manages all registered integrations
  def register_integration(module, type)
  def get_decorators_for_url(url)
  def get_available_importers()
  def get_user_integrations(workspace_id, type)
end
```

### Phase 2: Web Link Decorator Implementation ✅ COMPLETE

#### Link Detection ✅
- [x] Create `LifeOrg.LinkDetector` module
- [x] Regex patterns for URL detection
- [x] Extract URLs with positions from markdown

#### Generic Web Decorator ✅
- [x] Create `LifeOrg.Integrations.Decorators.WebLink`
- [x] Fetch Open Graph tags
- [x] Fetch Twitter Card tags
- [x] Fetch standard HTML meta tags
- [x] Parse with Floki (now available in all environments)

#### Link Fetcher Service ⬜
```elixir
defmodule LifeOrg.LinkFetcher do
  use GenServer
  
  def fetch_metadata(url) do
    # Check cache first
    # Fetch if not cached or expired
    # Parse HTML for metadata
    # Store in cache
    # Return metadata
  end
  
  defp extract_metadata(html) do
    # Use Floki to parse OG tags, Twitter cards, etc.
  end
end
```

#### Preview Components ⬜
- [ ] Create base `link_preview.ex` component
- [ ] Create `web_link_preview.ex` for generic links
- [ ] Loading state component
- [ ] Error state component
- [ ] Inline vs expanded view modes

#### LiveView Integration ⬜
- [ ] Update `render_interactive_description` in TodoComponent
- [ ] Update journal entry rendering
- [ ] Update todo comment rendering
- [ ] Add JavaScript hook for async loading
- [ ] Implement async assigns pattern

### Phase 3: Platform Decorators ⬜

#### OAuth2 Framework ⬜
- [ ] Create `LifeOrg.Integrations.Auth.OAuth2`
- [ ] Token storage (encrypted)
- [ ] Refresh token handling
- [ ] Revocation flow

#### Asana Decorator ⬜
- [ ] Create `LifeOrg.Integrations.Decorators.Asana`
- [ ] OAuth2 flow implementation
- [ ] Task/project metadata fetching
- [ ] Custom preview component
- [ ] Error handling for auth failures

#### Jira Decorator ⬜
- [ ] Create `LifeOrg.Integrations.Decorators.Jira`
- [ ] OAuth2/API token support
- [ ] Issue metadata fetching
- [ ] Custom preview with status, type, priority

#### GitHub Decorator ⬜
- [ ] Create `LifeOrg.Integrations.Decorators.GitHub`
- [ ] PR/Issue detection
- [ ] Status badges, labels, assignees
- [ ] Public vs private repo handling

### Phase 4: Content Importers ⬜

#### Importer UI ⬜
- [ ] Settings page for imports
- [ ] List available importers
- [ ] Import preview interface
- [ ] Field mapping configuration
- [ ] Import history view

#### CSV Importer (Proof of Concept) ⬜
- [ ] Create `LifeOrg.Integrations.Importers.CSV`
- [ ] File upload handling
- [ ] Column mapping UI
- [ ] Preview before import
- [ ] Duplicate detection

#### Asana Importer ⬜
- [ ] Create `LifeOrg.Integrations.Importers.Asana`
- [ ] Project/task listing
- [ ] Selective import with filters
- [ ] Field mapping (Asana → Todo)
- [ ] Maintain source references

## Technical Implementation Details

### Decorator Pipeline
```elixir
defmodule LifeOrg.Decorators.Pipeline do
  def process_content(content, workspace_id) do
    content
    |> LinkDetector.extract_urls()
    |> Registry.match_decorators()
    |> parallel_fetch_metadata(workspace_id)
    |> inject_preview_components()
    |> render_final_html()
  end
  
  defp parallel_fetch_metadata(urls_with_decorators, workspace_id) do
    urls_with_decorators
    |> Task.async_stream(&fetch_one/1, timeout: 5000, on_timeout: :kill_task)
    |> Enum.map(&handle_result/1)
  end
end
```

### Import Pipeline
```elixir
defmodule LifeOrg.Importers.Pipeline do
  def run_import(integration, workspace_id, options \\ %{}) do
    with {:ok, items} <- integration.list_importable_items(options),
         {:ok, filtered} <- apply_filters(items, options),
         {:ok, mapped} <- map_items(filtered, integration),
         {:ok, validated} <- validate_items(mapped),
         {:ok, deduped} <- detect_duplicates(validated, workspace_id),
         {:ok, created} <- create_records(deduped, workspace_id) do
      log_import_run(integration, created, workspace_id)
    end
  end
end
```

### Performance Considerations

#### Decorators
- **Async Loading**: Use LiveView async assigns to prevent blocking
- **Batch Fetching**: Group multiple URLs to same domain
- **Caching**: 15-minute TTL for metadata
- **Progressive Enhancement**: Show link immediately, preview when ready
- **Rate Limiting**: Per-domain limits to avoid API throttling

#### Importers
- **Background Jobs**: Use Oban for large imports
- **Chunked Processing**: Process in batches of 100 items
- **Progress Updates**: Phoenix PubSub for real-time progress
- **Memory Management**: Stream processing for large datasets

### Security Considerations

- **URL Validation**: Validate and sanitize all URLs before fetching
- **HTML Sanitization**: Use HtmlSanitizeEx for preview content
- **Credential Encryption**: Use Cloak for encrypting stored tokens
- **Rate Limiting**: Implement per-workspace rate limits
- **Audit Logging**: Log all import activities
- **CSP Headers**: Restrict embedded content sources

## Progress Tracking

### Phase 1 Progress
- [x] Database migrations created
- [x] Elixir schemas implemented
- [x] Core behaviors defined
- [x] Registry module implemented
- [ ] Basic tests written

### Phase 2 Progress ✅
- [x] Link detector implemented
- [x] Web decorator working
- [x] Preview components created
- [x] LiveView integration complete
- [x] Caching implemented

### Phase 3 Progress
- [ ] OAuth2 framework ready
- [ ] Asana decorator complete
- [ ] Jira decorator complete
- [ ] GitHub decorator complete
- [ ] Settings UI for connections

### Phase 4 Progress
- [ ] Import UI created
- [ ] CSV importer working
- [ ] Asana importer complete
- [ ] Import history tracking
- [ ] Duplicate detection working

## Future Expansions

### Content Syncers
- Bidirectional sync framework
- Conflict resolution UI
- Change detection and queuing
- Sync status indicators

### Automation Triggers
- Webhook receiver endpoint
- Event → Action rule engine
- Scheduled polling option
- User-defined conditions

### Additional Decorators
- Slack messages
- Google Docs
- Notion pages
- Linear issues
- Confluence pages

### Additional Importers
- Todoist
- Microsoft To-Do
- Apple Reminders (via file)
- Trello boards
- Monday.com

## Notes

- Start with decorators for immediate value
- Build importer framework in parallel
- Keep authentication modular for reuse
- Design for extensibility from the start
- Maintain clear separation between integration types
- Focus on user experience and performance