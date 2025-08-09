# Asana Integration Setup

## Overview

The Life Organizer supports rich Asana link previews through OAuth2 authentication. When you paste an Asana task or project URL, the system will automatically fetch and display relevant information.

## Setting Up Asana OAuth

### 1. Create an Asana App

1. Go to the [Asana Developer Console](https://app.asana.com/0/developer-console)
2. Click "Create New App"
3. Choose "OAuth" as the authentication method
4. Fill in the app details:
   - **App Name**: Life Organizer (or your preferred name)
   - **App URL**: http://localhost:4000 (for development)
   - **Redirect URL**: http://localhost:4000/auth/asana/callback

### 2. Configure Environment Variables

Add your Asana OAuth credentials to your `.env` file:

```bash
ASANA_CLIENT_ID=your_client_id_here
ASANA_CLIENT_SECRET=your_client_secret_here
```

### 3. Connect Your Asana Account

1. Start the Phoenix server: `mix phx.server`
2. Navigate to http://localhost:4000
3. Go to Settings > Integrations (or similar)
4. Click "Connect Asana"
5. Authorize the application

## Supported URL Formats

The Asana decorator recognizes the following URL patterns:

- **Tasks**: `https://app.asana.com/0/{project_id}/{task_id}`
- **Projects**: `https://app.asana.com/0/projects/{project_id}`

## Features

### Task Previews
- Task title and description
- Completion status
- Assignee information
- Due date (with overdue highlighting)
- Associated projects
- Tags
- Custom fields (when available)

### Project Previews
- Project name and description
- Current status (with color coding)
- Team and owner information
- Due dates
- Archive status

## Preview Sizes

The decorator supports three preview sizes:
- **Compact**: Minimal inline preview
- **Normal**: Standard preview with key information
- **Expanded**: Full preview with all available details

## Troubleshooting

### Authentication Issues
- Ensure your OAuth credentials are correctly set in the `.env` file
- Verify the redirect URL matches exactly in both Asana and your application
- Check that your Asana app has the necessary scopes enabled

### API Rate Limits
The Asana API has rate limits. If you encounter errors:
- The decorator will gracefully fall back to a basic preview
- Consider implementing caching for frequently accessed tasks/projects

### Private Workspaces
To access private Asana workspaces:
1. Ensure you're authenticated with an account that has access
2. The OAuth token must have the appropriate permissions

## Development Notes

The Asana decorator implementation includes:
- OAuth2 token management via Ueberauth
- Automatic token refresh (when implemented)
- Error handling for various API responses
- HTML-safe rendering of all content
- Support for both light and dark themes (via CSS classes)