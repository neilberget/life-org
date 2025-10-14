# Life Organizer API Documentation

## Quick Reference

**Development URL:** `http://localhost:4000`
**Production URL:** `https://lifeorg.kestrel.home`

**API Base Path:** `/api/v1`

**Authentication:** Bearer token (generate at `/users/settings`)

---

## Authentication

All API requests require authentication using Bearer tokens. Generate tokens via the web interface at `/users/settings`.

### Using Your API Token

Include your token in the `Authorization` header:

```bash
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Base URL

All API endpoints are prefixed with `/api/v1`

## Endpoints

### Workspaces

#### List All Workspaces

```bash
curl -X GET http://localhost:4000/api/v1/workspaces \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### Get Single Workspace

```bash
curl -X GET http://localhost:4000/api/v1/workspaces/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Journal Entries

#### List All Journal Entries

```bash
# All entries across all workspaces
curl -X GET http://localhost:4000/api/v1/journal_entries \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by single workspace ID
curl -X GET "http://localhost:4000/api/v1/journal_entries?workspace_id=1" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by multiple workspace IDs (comma-separated)
curl -X GET "http://localhost:4000/api/v1/journal_entries?workspace_id=1,2" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by single workspace name
curl -X GET "http://localhost:4000/api/v1/journal_entries?workspace=Personal" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by multiple workspace names (comma-separated)
curl -X GET "http://localhost:4000/api/v1/journal_entries?workspace=Personal,Work" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by date range
curl -X GET "http://localhost:4000/api/v1/journal_entries?start_date=2025-01-01&end_date=2025-12-31" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by tags
curl -X GET "http://localhost:4000/api/v1/journal_entries?tags=work,personal" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Search in content
curl -X GET "http://localhost:4000/api/v1/journal_entries?q=meeting" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### Get Single Journal Entry

```bash
curl -X GET http://localhost:4000/api/v1/journal_entries/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### Create Journal Entry

```bash
curl -X POST http://localhost:4000/api/v1/journal_entries \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "journal_entry": {
      "content": "Today was productive. Finished the API implementation.",
      "entry_date": "2025-10-14",
      "tags": ["work", "programming"],
      "workspace_id": 1
    }
  }'
```

#### Update Journal Entry

```bash
curl -X PUT http://localhost:4000/api/v1/journal_entries/1 \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "journal_entry": {
      "content": "Updated content with more details.",
      "tags": ["work", "programming", "api"]
    }
  }'
```

#### Delete Journal Entry

```bash
curl -X DELETE http://localhost:4000/api/v1/journal_entries/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Todos

#### List All Todos

```bash
# All todos across all workspaces
curl -X GET http://localhost:4000/api/v1/todos \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by single workspace ID
curl -X GET "http://localhost:4000/api/v1/todos?workspace_id=1" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by multiple workspace IDs (comma-separated)
curl -X GET "http://localhost:4000/api/v1/todos?workspace_id=1,2" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by single workspace name
curl -X GET "http://localhost:4000/api/v1/todos?workspace=Personal" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by multiple workspace names (comma-separated)
curl -X GET "http://localhost:4000/api/v1/todos?workspace=Personal,Work" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by completion status
curl -X GET "http://localhost:4000/api/v1/todos?completed=false" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by single priority
curl -X GET "http://localhost:4000/api/v1/todos?priority=high" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by multiple priorities (comma-separated)
curl -X GET "http://localhost:4000/api/v1/todos?priority=high,medium" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by tags
curl -X GET "http://localhost:4000/api/v1/todos?tags=urgent,work" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Get overdue todos
curl -X GET "http://localhost:4000/api/v1/todos?overdue=true" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Get current todo
curl -X GET "http://localhost:4000/api/v1/todos?current=true" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Search in title/description
curl -X GET "http://localhost:4000/api/v1/todos?q=implement" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by single project
curl -X GET "http://localhost:4000/api/v1/todos?project=API%20Development" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by multiple projects (comma-separated)
curl -X GET "http://localhost:4000/api/v1/todos?project=API%20Development,Frontend%20Work" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Order by due date ascending (nulls last)
curl -X GET "http://localhost:4000/api/v1/todos?order_by=due_date_asc" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Order by priority descending
curl -X GET "http://localhost:4000/api/v1/todos?order_by=priority_desc" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Limit to 10 todos per workspace (useful when filtering multiple workspaces)
curl -X GET "http://localhost:4000/api/v1/todos?workspace=Personal,Work&per_workspace_limit=10" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Combine filters with ordering and per-workspace limiting
curl -X GET "http://localhost:4000/api/v1/todos?project=API%20Development,Frontend%20Work&order_by=due_date_asc&per_workspace_limit=5" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Order By Options:**
- `due_date_asc` - Due date ascending (nulls last)
- `due_date_desc` - Due date descending (nulls last)
- `priority_asc` - Priority ascending (low → medium → high)
- `priority_desc` - Priority descending (high → medium → low)
- `position_asc` - Custom position ascending (respects drag-and-drop ordering)
- `position_desc` - Custom position descending (respects drag-and-drop ordering)
- `inserted_at_asc` - Creation date ascending
- `inserted_at_desc` - Creation date descending
- `updated_at_asc` - Last updated ascending
- `updated_at_desc` - Last updated descending
- `title_asc` - Title alphabetically A-Z
- `title_desc` - Title alphabetically Z-A

Default ordering (when `order_by` is not specified): Current todos first, then by priority (high → medium → low), then by insertion time (oldest first).

**Per-Workspace Limiting:**

The `per_workspace_limit` parameter allows you to limit the number of todos returned from each workspace. This is particularly useful when querying multiple workspaces or projects:

- When filtering 2 projects with `per_workspace_limit=10`, you'll get up to 20 todos (10 from each)
- When filtering 3 workspaces with `per_workspace_limit=5`, you'll get up to 15 todos (5 from each)
- The limit is applied after filtering and ordering, so you get the top N todos per workspace based on your filters

#### Get Single Todo

```bash
curl -X GET http://localhost:4000/api/v1/todos/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### Create Todo

```bash
curl -X POST http://localhost:4000/api/v1/todos \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "todo": {
      "title": "Implement authentication",
      "description": "Add Bearer token authentication to API",
      "priority": "high",
      "due_date": "2025-10-20",
      "tags": ["api", "security"],
      "projects": ["API Development"],
      "workspace_id": 1
    }
  }'
```

#### Update Todo

```bash
curl -X PUT http://localhost:4000/api/v1/todos/1 \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "todo": {
      "completed": true,
      "description": "Bearer token auth completed and tested"
    }
  }'
```

#### Delete Todo

```bash
curl -X DELETE http://localhost:4000/api/v1/todos/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Response Format

### Success Response

All successful responses follow this format:

```json
{
  "data": {
    "id": 1,
    "title": "Example Todo",
    ...
  }
}
```

For list endpoints:

```json
{
  "data": [
    {
      "id": 1,
      ...
    },
    {
      "id": 2,
      ...
    }
  ]
}
```

### Error Responses

#### 401 Unauthorized

```json
{
  "errors": {
    "detail": "Invalid or missing API token"
  }
}
```

#### 404 Not Found

```json
{
  "errors": {
    "detail": "Not Found"
  }
}
```

#### 422 Unprocessable Entity

```json
{
  "errors": {
    "title": ["can't be blank"],
    "workspace_id": ["can't be blank"]
  }
}
```

## Data Models

### Workspace

```json
{
  "id": 1,
  "name": "Personal",
  "description": "My personal workspace",
  "color": "#3B82F6",
  "is_default": true,
  "inserted_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

### Journal Entry

```json
{
  "id": 1,
  "content": "Today was a great day...",
  "entry_date": "2025-10-14",
  "tags": ["personal", "reflection"],
  "workspace_id": 1,
  "inserted_at": "2025-10-14T12:00:00Z",
  "updated_at": "2025-10-14T12:00:00Z"
}
```

### Todo

```json
{
  "id": 1,
  "title": "Complete API documentation",
  "description": "Write comprehensive API docs with examples",
  "completed": false,
  "priority": "high",
  "due_date": "2025-10-20",
  "due_time": "17:00:00",
  "current": false,
  "ai_generated": false,
  "tags": ["documentation", "api"],
  "position": 1000,
  "workspace_id": 1,
  "journal_entry_id": null,
  "projects": [
    {
      "id": 1,
      "name": "API Development",
      "color": "#10B981",
      "url": "https://github.com/user/project",
      "favicon_url": "https://github.com/favicon.ico"
    }
  ],
  "inserted_at": "2025-10-14T12:00:00Z",
  "updated_at": "2025-10-14T12:00:00Z"
}
```

## Rate Limiting

Currently, there are no rate limits on API requests. This may be added in future versions.

## Token Security

- API tokens are hashed before storage
- Tokens are only displayed once upon creation
- Tokens never expire unless you set an expiration date
- Delete tokens immediately if compromised
- Each token tracks last usage time for security auditing

## Best Practices

1. **Store tokens securely**: Never commit tokens to version control
2. **Use environment variables**: Store tokens in environment variables or secure vaults
3. **Create specific tokens**: Generate separate tokens for different applications/purposes
4. **Monitor token usage**: Check last_used_at timestamps regularly
5. **Rotate tokens**: Periodically delete and recreate tokens for security
6. **Use descriptive names**: Name tokens based on their purpose (e.g., "Mobile App", "CI/CD Pipeline")

## Example: Python Integration

```python
import requests

API_BASE = "http://localhost:4000/api/v1"
API_TOKEN = "your_api_token_here"

headers = {
    "Authorization": f"Bearer {API_TOKEN}",
    "Content-Type": "application/json"
}

# Get all todos
response = requests.get(f"{API_BASE}/todos", headers=headers)
todos = response.json()["data"]

# Create a new todo
new_todo = {
    "todo": {
        "title": "Review pull requests",
        "priority": "medium",
        "workspace_id": 1
    }
}
response = requests.post(f"{API_BASE}/todos", headers=headers, json=new_todo)
created_todo = response.json()["data"]

# Update a todo
update_data = {"todo": {"completed": True}}
response = requests.put(f"{API_BASE}/todos/{created_todo['id']}",
                       headers=headers, json=update_data)
```

## Example: JavaScript/Node.js Integration

```javascript
const axios = require('axios');

const API_BASE = 'http://localhost:4000/api/v1';
const API_TOKEN = 'your_api_token_here';

const headers = {
  'Authorization': `Bearer ${API_TOKEN}`,
  'Content-Type': 'application/json'
};

// Get all journal entries
async function getJournalEntries() {
  try {
    const response = await axios.get(`${API_BASE}/journal_entries`, { headers });
    return response.data.data;
  } catch (error) {
    console.error('Error fetching journal entries:', error.response.data);
  }
}

// Create a new journal entry
async function createJournalEntry(content, date, workspaceId) {
  try {
    const response = await axios.post(
      `${API_BASE}/journal_entries`,
      {
        journal_entry: {
          content: content,
          entry_date: date,
          workspace_id: workspaceId
        }
      },
      { headers }
    );
    return response.data.data;
  } catch (error) {
    console.error('Error creating journal entry:', error.response.data);
  }
}
```

## Support

For issues or questions, please refer to the main application documentation or create an issue in the project repository.
