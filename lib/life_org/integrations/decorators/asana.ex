defmodule LifeOrg.Integrations.Decorators.Asana do
  @moduledoc """
  Asana decorator for fetching task and project metadata.
  
  Provides rich previews for Asana URLs including:
  - Task information (title, description, assignee, status, due date)
  - Project details (name, description, status)
  
  Supports both public and private workspaces with OAuth2 authentication.
  """

  @behaviour LifeOrg.Integrations.Integration
  @behaviour LifeOrg.Integrations.Decorator
  require Logger

  # Asana API base URL
  @asana_api_base "https://app.asana.com/api/1.0"
  @asana_user_agent "LifeOrg/1.0"

  # Integration behavior callbacks
  @impl true
  def name, do: "Asana"
  
  @impl true
  def provider, do: :asana
  
  @impl true
  def capabilities, do: [:fetch_metadata, :render_preview, :requires_auth]
  
  @impl true
  def configure(config), do: {:ok, config}
  
  @impl true
  def type, do: :decorator
  
  @impl true
  def validate_settings(settings) do
    case Map.get(settings, "token") do
      nil -> {:ok, settings}
      token when is_binary(token) and byte_size(token) > 0 -> {:ok, settings}
      _ -> {:error, "Asana token must be a valid string"}
    end
  end

  # Decorator behavior callbacks
  @impl true
  def priority, do: 10  # Higher priority than generic web decorator
  
  @impl true
  def match_url(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when host in ["app.asana.com", "asana.com"] ->
        # Match task and project URLs with any digit prefix
        path != nil and (
          Regex.match?(~r|^/\d+/\d+/\d+|, path) or                        # task: /<digit>/projectid/taskid
          Regex.match?(~r|^/\d+/projects/\d+|, path) or                   # project: /<digit>/projects/projectid
          Regex.match?(~r|^/\d+/.*/project/.*/task/\d+|, path) or        # new format task
          Regex.match?(~r|^/\d+/.*/project/\d+|, path)                   # new format project
        )
      _ -> false
    end
  end

  @impl true
  def fetch_metadata(url, credentials \\ %{}) do
    Logger.debug("Fetching Asana metadata for URL: #{url}")
    
    case parse_asana_url(url) do
      {:ok, asana_info} ->
        # Try to get OAuth2 token for authenticated access
        enhanced_credentials = enhance_credentials_with_oauth(credentials)
        fetch_asana_data(asana_info, enhanced_credentials)
      
      {:error, reason} ->
        Logger.warning("Failed to parse Asana URL #{url}: #{reason}")
        {:error, reason}
    end
  end

  @impl true
  def render_preview(metadata, opts \\ %{}) do
    size = Map.get(opts, :size, :normal)
    
    case metadata.type do
      "task" -> render_task_preview(metadata, size)
      "project" -> render_project_preview(metadata, size)
      _ -> render_generic_asana_preview(metadata, size)
    end
  end

  ## Private Functions

  defp parse_asana_url(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when host in ["app.asana.com", "asana.com"] ->
        parse_asana_path(path, url)
      
      _ ->
        {:error, :invalid_asana_url}
    end
  end

  defp parse_asana_path(path, original_url) do
    parts = String.split(path, "/", trim: true)
    
    case parts do
      # Format: /<digit>/projectid/taskid or /<digit>/workspace/project/project_id/task/task_id
      [first | rest] ->
        if Regex.match?(~r/^\d+$/, first) do
          parse_asana_path_with_digit_prefix(rest, original_url)
        else
          {:error, :unsupported_asana_path}
        end
      
      _ ->
        {:error, :unsupported_asana_path}
    end
  end
  
  defp parse_asana_path_with_digit_prefix(rest, original_url) do
    case rest do
      # Simple format: projectid/taskid
      [_project_id, task_id] ->
        if Regex.match?(~r/^\d+$/, task_id) do
          {:ok, %{
            type: :task,
            id: task_id,
            url: original_url
          }}
        else
          # Try other patterns
          parse_asana_path_with_digit_prefix_extended(rest, original_url)
        end
      
      # Simple format: projects/projectid
      ["projects", project_id | _] ->
        {:ok, %{
          type: :project,
          id: project_id,
          url: original_url
        }}
      
      _ ->
        parse_asana_path_with_digit_prefix_extended(rest, original_url)
    end
  end
  
  defp parse_asana_path_with_digit_prefix_extended(rest, original_url) do
    case rest do
      # New format: workspace_id/project/project_id/task/task_id
      [_workspace_id, "project", _project_id, "task", task_id | _] ->
        {:ok, %{
          type: :task,
          id: task_id,
          url: original_url
        }}
      
      # New format: workspace_id/project/project_id
      [_workspace_id, "project", project_id | _] ->
        {:ok, %{
          type: :project,
          id: project_id,
          url: original_url
        }}
      
      _ ->
        {:error, :unsupported_asana_path}
    end
  end

  defp fetch_asana_data(asana_info, credentials) do
    headers = build_headers(credentials)
    
    case asana_info.type do
      :task ->
        fetch_task_data(asana_info, headers)
      
      :project ->
        fetch_project_data(asana_info, headers)
    end
  end

  defp build_headers(credentials) do
    base_headers = [
      {"User-Agent", @asana_user_agent},
      {"Accept", "application/json"}
    ]
    
    case Map.get(credentials, "token") do
      token when is_binary(token) and byte_size(token) > 0 ->
        [{"Authorization", "Bearer #{token}"} | base_headers]
      
      _ ->
        base_headers
    end
  end

  defp fetch_task_data(%{id: task_id, url: url}, headers) do
    api_url = "#{@asana_api_base}/tasks/#{task_id}"
    
    # Request additional fields for rich preview
    query_params = [
      opt_fields: "name,notes,completed,due_on,due_at,assignee.name,assignee.email,projects.name,memberships.project.name,memberships.section.name,custom_fields,tags.name,created_at,modified_at"
    ]
    
    case Req.get(api_url, headers: headers, params: query_params, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => task_data}}} ->
        {:ok, process_task_data(task_data, url)}
      
      {:ok, %{status: 401}} ->
        {:error, :authentication_required}
      
      {:ok, %{status: 404}} ->
        {:error, :task_not_found}
      
      {:ok, %{status: status}} ->
        Logger.warning("Asana API returned status #{status} for #{api_url}")
        {:error, {:asana_api_error, status}}
      
      {:error, reason} ->
        Logger.warning("Failed to fetch Asana task data: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_project_data(%{id: project_id, url: url}, headers) do
    api_url = "#{@asana_api_base}/projects/#{project_id}"
    
    # Request additional fields for rich preview
    query_params = [
      opt_fields: "name,notes,color,current_status.text,current_status.color,owner.name,team.name,due_date,start_on,created_at,modified_at,archived"
    ]
    
    case Req.get(api_url, headers: headers, params: query_params, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => project_data}}} ->
        {:ok, process_project_data(project_data, url)}
      
      {:ok, %{status: 401}} ->
        {:error, :authentication_required}
      
      {:ok, %{status: 404}} ->
        {:error, :project_not_found}
      
      {:ok, %{status: status}} ->
        Logger.warning("Asana API returned status #{status} for #{api_url}")
        {:error, {:asana_api_error, status}}
      
      {:error, reason} ->
        Logger.warning("Failed to fetch Asana project data: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp process_task_data(task_data, url) do
    %{
      type: "task",
      url: url,
      title: task_data["name"] || "Untitled Task",
      description: truncate_text(task_data["notes"], 150),
      completed: task_data["completed"] || false,
      due_date: parse_date(task_data["due_on"] || task_data["due_at"]),
      assignee: extract_assignee(task_data["assignee"]),
      projects: extract_projects(task_data),
      section: extract_section(task_data),
      tags: extract_tags(task_data["tags"]),
      custom_fields: extract_custom_fields(task_data["custom_fields"]),
      created_at: task_data["created_at"],
      modified_at: task_data["modified_at"],
      raw: task_data
    }
  end

  defp process_project_data(project_data, url) do
    %{
      type: "project",
      url: url,
      title: project_data["name"] || "Untitled Project",
      description: truncate_text(project_data["notes"], 150),
      color: project_data["color"],
      status: extract_project_status(project_data["current_status"]),
      owner: extract_owner(project_data["owner"]),
      team: extract_team(project_data["team"]),
      due_date: parse_date(project_data["due_date"]),
      start_date: parse_date(project_data["start_on"]),
      archived: project_data["archived"] || false,
      created_at: project_data["created_at"],
      modified_at: project_data["modified_at"],
      raw: project_data
    }
  end

  defp extract_assignee(nil), do: nil
  defp extract_assignee(assignee) do
    %{
      name: assignee["name"],
      email: assignee["email"]
    }
  end

  defp extract_projects(task_data) do
    projects = task_data["projects"] || []
    memberships = task_data["memberships"] || []
    
    if length(projects) > 0 do
      Enum.map(projects, fn project ->
        %{name: project["name"] || "Unknown Project"}
      end)
    else
      Enum.map(memberships, fn membership ->
        %{name: get_in(membership, ["project", "name"]) || "Unknown Project"}
      end)
    end
  end

  defp extract_section(task_data) do
    memberships = task_data["memberships"] || []
    
    case List.first(memberships) do
      nil -> nil
      membership -> get_in(membership, ["section", "name"])
    end
  end

  defp extract_tags(nil), do: []
  defp extract_tags(tags) when is_list(tags) do
    Enum.map(tags, fn tag ->
      %{name: tag["name"] || ""}
    end)
  end

  defp extract_custom_fields(nil), do: []
  defp extract_custom_fields(fields) when is_list(fields) do
    fields
    |> Enum.filter(fn field -> field["display_value"] != nil end)
    |> Enum.map(fn field ->
      %{
        name: field["name"],
        value: field["display_value"]
      }
    end)
  end

  defp extract_project_status(nil), do: nil
  defp extract_project_status(status) do
    %{
      text: status["text"],
      color: status["color"]
    }
  end

  defp extract_owner(nil), do: nil
  defp extract_owner(owner) do
    %{name: owner["name"]}
  end

  defp extract_team(nil), do: nil
  defp extract_team(team) do
    %{name: team["name"]}
  end

  defp parse_date(nil), do: nil
  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> date_string
    end
  end

  defp truncate_text(nil, _), do: nil
  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  ## Preview Rendering

  defp render_task_preview(metadata, size) do
    case size do
      :compact -> render_compact_task_preview(metadata)
      :expanded -> render_expanded_task_preview(metadata)
      _ -> render_normal_task_preview(metadata)
    end
  end

  defp render_project_preview(metadata, size) do
    case size do
      :compact -> render_compact_project_preview(metadata)
      :expanded -> render_expanded_project_preview(metadata)
      _ -> render_normal_project_preview(metadata)
    end
  end

  defp render_generic_asana_preview(metadata, _size) do
    title = safe_html_escape(metadata.title || "Asana Link")
    url = safe_html_escape(metadata.url)
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        <div class="w-12 h-12 bg-gradient-to-br from-red-500 to-pink-500 rounded flex-shrink-0 flex items-center justify-center">
          #{asana_icon()}
        </div>
        <div class="flex-1 min-w-0">
          <h4 class="font-medium text-gray-900 truncate">#{title}</h4>
          <span class="text-xs text-gray-500">app.asana.com</span>
        </div>
      </div>
    </a>
    """)
  end

  # Task Previews
  defp render_compact_task_preview(metadata) do
    title = safe_html_escape(metadata.title)
    url = safe_html_escape(metadata.url)
    status_icon = if metadata.completed, do: "✅", else: "⭕"
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" 
       class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 hover:bg-gray-100 rounded text-sm border transition-colors max-w-sm">
      <span>#{status_icon}</span>
      <span class="truncate font-medium">#{title}</span>
    </a>
    """)
  end

  defp render_normal_task_preview(metadata) do
    title = safe_html_escape(metadata.title)
    url = safe_html_escape(metadata.url)
    completed_class = if metadata.completed, do: "line-through text-gray-500", else: "text-gray-900"
    status_badge = if metadata.completed do
      "<span class=\"text-xs px-2 py-1 bg-green-100 text-green-800 rounded\">Completed</span>"
    else
      "<span class=\"text-xs px-2 py-1 bg-yellow-100 text-yellow-800 rounded\">In Progress</span>"
    end
    
    description_html = if metadata.description do
      description = safe_html_escape(metadata.description)
      "<p class=\"text-sm text-gray-600 mt-1\">#{description}</p>"
    else
      ""
    end

    assignee_html = if metadata.assignee do
      name = safe_html_escape(metadata.assignee.name)
      "<span class=\"text-xs text-gray-600\">👤 #{name}</span>"
    else
      ""
    end

    due_date_html = if metadata.due_date do
      due_date = format_date(metadata.due_date)
      overdue = is_overdue?(metadata.due_date) && !metadata.completed
      date_class = if overdue, do: "text-red-600", else: "text-gray-600"
      "<span class=\"text-xs #{date_class}\">📅 #{due_date}</span>"
    else
      ""
    end

    projects_html = render_projects_html(metadata.projects)
    tags_html = render_tags_html(metadata.tags)

    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        <div class="w-12 h-12 bg-gradient-to-br from-red-500 to-pink-500 rounded flex-shrink-0 flex items-center justify-center">
          #{asana_icon()}
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-start gap-2 mb-1">
            <h4 class="font-medium #{completed_class} flex-1">#{title}</h4>
            #{status_badge}
          </div>
          #{description_html}
          <div class="flex items-center gap-3 mt-2 flex-wrap">
            #{assignee_html}
            #{due_date_html}
            #{projects_html}
          </div>
          #{tags_html}
        </div>
      </div>
    </a>
    """)
  end

  defp render_expanded_task_preview(metadata) do
    # Similar to normal but with custom fields and more details
    render_normal_task_preview(metadata)
  end

  # Project Previews
  defp render_compact_project_preview(metadata) do
    title = safe_html_escape(metadata.title)
    url = safe_html_escape(metadata.url)
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" 
       class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 hover:bg-gray-100 rounded text-sm border transition-colors max-w-sm">
      #{asana_icon("w-3 h-3")}
      <span class="truncate font-medium">#{title}</span>
    </a>
    """)
  end

  defp render_normal_project_preview(metadata) do
    title = safe_html_escape(metadata.title)
    url = safe_html_escape(metadata.url)
    
    description_html = if metadata.description do
      description = safe_html_escape(metadata.description)
      "<p class=\"text-sm text-gray-600 mt-1\">#{description}</p>"
    else
      ""
    end

    status_html = if metadata.status do
      status_text = safe_html_escape(metadata.status.text)
      status_color = get_status_color(metadata.status.color)
      "<span class=\"text-xs px-2 py-1 rounded\" style=\"background-color: #{status_color}; color: white;\">#{status_text}</span>"
    else
      ""
    end

    team_html = if metadata.team do
      team = safe_html_escape(metadata.team.name)
      "<span class=\"text-xs text-gray-600\">🏢 #{team}</span>"
    else
      ""
    end

    owner_html = if metadata.owner do
      owner = safe_html_escape(metadata.owner.name)
      "<span class=\"text-xs text-gray-600\">👤 #{owner}</span>"
    else
      ""
    end

    archived_badge = if metadata.archived do
      "<span class=\"text-xs px-2 py-1 bg-gray-100 text-gray-600 rounded\">Archived</span>"
    else
      ""
    end

    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        <div class="w-12 h-12 bg-gradient-to-br from-red-500 to-pink-500 rounded flex-shrink-0 flex items-center justify-center">
          #{asana_icon()}
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-start gap-2 mb-1">
            <h4 class="font-medium text-gray-900 flex-1">#{title}</h4>
            <div class="flex gap-1">
              #{status_html}
              #{archived_badge}
            </div>
          </div>
          #{description_html}
          <div class="flex items-center gap-3 mt-2 flex-wrap">
            #{team_html}
            #{owner_html}
          </div>
        </div>
      </div>
    </a>
    """)
  end

  defp render_expanded_project_preview(metadata) do
    # Similar to normal but with more details
    render_normal_project_preview(metadata)
  end

  ## Helper Functions

  defp render_projects_html([]), do: ""
  defp render_projects_html(projects) when is_list(projects) do
    projects_text = projects
    |> Enum.map(fn project -> project.name end)
    |> Enum.join(", ")
    |> safe_html_escape()
    
    if projects_text != "" do
      "<span class=\"text-xs text-gray-600\">📁 #{projects_text}</span>"
    else
      ""
    end
  end

  defp render_tags_html([]), do: ""
  defp render_tags_html(tags) when is_list(tags) do
    tags_html = tags
    |> Enum.map(fn tag -> 
      name = safe_html_escape(tag.name)
      "<span class=\"text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded\">#{name}</span>"
    end)
    |> Enum.join("")
    
    if tags_html != "" do
      "<div class=\"flex items-center gap-1 mt-1 flex-wrap\">#{tags_html}</div>"
    else
      ""
    end
  end

  defp get_status_color(nil), do: "#4b5563"  # gray-600
  defp get_status_color("green"), do: "#10b981"  # green-500
  defp get_status_color("yellow"), do: "#f59e0b"  # yellow-500
  defp get_status_color("red"), do: "#ef4444"  # red-500
  defp get_status_color("blue"), do: "#3b82f6"  # blue-500
  defp get_status_color(_), do: "#4b5563"  # gray-600

  defp format_date(%Date{} = date) do
    # Simple date formatting without Timex
    month_names = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    month = Enum.at(month_names, date.month - 1)
    "#{month} #{date.day}, #{date.year}"
  end
  defp format_date(date_string) when is_binary(date_string), do: date_string

  defp is_overdue?(%Date{} = due_date) do
    Date.compare(due_date, Date.utc_today()) == :lt
  end
  defp is_overdue?(_), do: false

  defp safe_html_escape(value) when is_binary(value) do
    Phoenix.HTML.html_escape(value) |> Phoenix.HTML.safe_to_string()
  end
  defp safe_html_escape({:safe, content}) when is_binary(content) do
    content
  end
  defp safe_html_escape(value) do
    Phoenix.HTML.html_escape(to_string(value)) |> Phoenix.HTML.safe_to_string()
  end

  # SVG Icons
  defp asana_icon(class \\ "w-6 h-6 text-white") do
    """
    <svg class="#{class}" fill="currentColor" viewBox="0 0 24 24">
      <path d="M18.78 12.653c-2.882 0-5.22 2.336-5.22 5.22s2.338 5.22 5.22 5.22 5.22-2.336 5.22-5.22-2.336-5.22-5.22-5.22zm-13.56 0c-2.88 0-5.22 2.337-5.22 5.22s2.338 5.22 5.22 5.22 5.22-2.336 5.22-5.22-2.336-5.22-5.22-5.22zm6.78-6.73c0-2.883-2.337-5.22-5.22-5.22-2.882 0-5.22 2.337-5.22 5.22 0 2.884 2.338 5.22 5.22 5.22 2.884 0 5.22-2.336 5.22-5.22z"/>
    </svg>
    """
  end

  ## OAuth2 Integration

  defp enhance_credentials_with_oauth(credentials) do
    # Try to get OAuth2 token from the current workspace
    case get_workspace_oauth_token() do
      {:ok, oauth_token} ->
        Logger.debug("Using OAuth2 token for Asana API access")
        Map.put(credentials, "token", oauth_token)
      
      {:error, reason} ->
        Logger.debug("No OAuth2 token available: #{inspect(reason)}, API may return limited data")
        credentials
    end
  end

  defp get_workspace_oauth_token() do
    # Get the current workspace from the process context
    case Process.get(:current_workspace_id) do
      nil ->
        # Try to get default workspace
        case get_default_workspace_id() do
          {:ok, workspace_id} -> get_asana_token_for_workspace(workspace_id)
          error -> error
        end
      
      workspace_id ->
        get_asana_token_for_workspace(workspace_id)
    end
  end

  defp get_default_workspace_id() do
    # For decorators, we don't have user context
    # This will need to be refactored to pass user context through the decoration pipeline
    import Ecto.Query
    case LifeOrg.Repo.one(from w in LifeOrg.Workspace, order_by: [asc: w.id], limit: 1) do
      %{id: id} -> {:ok, id}
      _ -> {:error, :no_default_workspace}
    end
  end

  defp get_asana_token_for_workspace(workspace_id) do
    try do
      # Use the AuthController function to get the access token
      case LifeOrgWeb.AuthController.get_access_token(:asana, workspace_id) do
        {:ok, token} -> {:ok, token}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error -> 
        Logger.debug("Failed to get Asana token: #{inspect(error)}")
        {:error, :auth_controller_error}
    end
  end
end