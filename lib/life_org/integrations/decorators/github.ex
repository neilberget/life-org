defmodule LifeOrg.Integrations.Decorators.GitHub do
  @moduledoc """
  GitHub decorator for fetching repository, issue, and pull request metadata.
  
  Provides rich previews for GitHub URLs including:
  - Repository information (stars, forks, language, description)
  - Issue details (status, labels, assignee, comments)
  - Pull request details (status, checks, reviews, mergeable)
  
  Supports both public repositories (no auth required) and private repositories
  with GitHub token authentication.
  """

  @behaviour LifeOrg.Integrations.Integration
  @behaviour LifeOrg.Integrations.Decorator
  require Logger
  import Bitwise

  # GitHub API base URL
  @github_api_base "https://api.github.com"
  @github_user_agent "LifeOrg/1.0"

  # Integration behavior callbacks
  @impl true
  def name, do: "GitHub"
  
  @impl true
  def provider, do: :github
  
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
      _ -> {:error, "GitHub token must be a valid string"}
    end
  end

  # Decorator behavior callbacks
  @impl true
  def priority, do: 10  # Higher priority than generic web decorator
  
  @impl true
  def match_url(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when host in ["github.com", "www.github.com"] ->
        # Match repository, issue, and PR URLs
        path != nil and (
          Regex.match?(~r|^/[^/]+/[^/]+/?$|, path) or          # repo: /owner/repo
          Regex.match?(~r|^/[^/]+/[^/]+/issues/\d+|, path) or  # issue: /owner/repo/issues/123
          Regex.match?(~r|^/[^/]+/[^/]+/pull/\d+|, path)       # PR: /owner/repo/pull/123
        )
      _ -> false
    end
  end

  @impl true
  def fetch_metadata(url, credentials \\ %{}) do
    Logger.debug("Fetching GitHub metadata for URL: #{url}")
    
    case parse_github_url(url) do
      {:ok, github_info} ->
        # Try to get OAuth2 token for authenticated access
        enhanced_credentials = enhance_credentials_with_oauth(credentials)
        fetch_github_data(github_info, enhanced_credentials)
      
      {:error, reason} ->
        Logger.warning("Failed to parse GitHub URL #{url}: #{reason}")
        {:error, reason}
    end
  end

  @impl true
  def render_preview(metadata, opts \\ %{}) do
    size = Map.get(opts, :size, :normal)
    
    case metadata.type do
      "repository" -> render_repository_preview(metadata, size)
      "issue" -> render_issue_preview(metadata, size)
      "pull_request" -> render_pull_request_preview(metadata, size)
      _ -> render_generic_github_preview(metadata, size)
    end
  end

  ## Private Functions

  defp parse_github_url(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when host in ["github.com", "www.github.com"] ->
        parse_github_path(path, url)
      
      _ ->
        {:error, :invalid_github_url}
    end
  end

  defp parse_github_path(path, original_url) do
    case String.split(path, "/", trim: true) do
      [owner, repo] ->
        {:ok, %{
          type: :repository,
          owner: owner,
          repo: repo,
          url: original_url
        }}
      
      [owner, repo, "issues", issue_number] ->
        case Integer.parse(issue_number) do
          {number, ""} ->
            {:ok, %{
              type: :issue,
              owner: owner,
              repo: repo,
              number: number,
              url: original_url
            }}
          _ ->
            {:error, :invalid_issue_number}
        end
      
      [owner, repo, "pull", pr_number] ->
        case Integer.parse(pr_number) do
          {number, ""} ->
            {:ok, %{
              type: :pull_request,
              owner: owner,
              repo: repo,
              number: number,
              url: original_url
            }}
          _ ->
            {:error, :invalid_pr_number}
        end
      
      _ ->
        {:error, :unsupported_github_path}
    end
  end

  defp fetch_github_data(github_info, credentials) do
    headers = build_headers(credentials)
    
    case github_info.type do
      :repository ->
        fetch_repository_data(github_info, headers)
      
      :issue ->
        fetch_issue_data(github_info, headers)
      
      :pull_request ->
        fetch_pull_request_data(github_info, headers)
    end
  end

  defp build_headers(credentials) do
    base_headers = [
      {"User-Agent", @github_user_agent},
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
    
    case Map.get(credentials, "token") do
      token when is_binary(token) and byte_size(token) > 0 ->
        [{"Authorization", "Bearer #{token}"} | base_headers]
      
      _ ->
        base_headers
    end
  end

  defp fetch_repository_data(%{owner: owner, repo: repo, url: url}, headers) do
    api_url = "#{@github_api_base}/repos/#{owner}/#{repo}"
    
    case Req.get(api_url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, process_repository_data(body, url)}
      
      {:ok, %{status: 404}} ->
        {:error, :repository_not_found}
      
      {:ok, %{status: status}} ->
        Logger.warning("GitHub API returned status #{status} for #{api_url}")
        {:error, {:github_api_error, status}}
      
      {:error, reason} ->
        Logger.warning("Failed to fetch GitHub repository data: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_issue_data(%{owner: owner, repo: repo, number: number, url: url}, headers) do
    api_url = "#{@github_api_base}/repos/#{owner}/#{repo}/issues/#{number}"
    
    case Req.get(api_url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, process_issue_data(body, url, owner, repo)}
      
      {:ok, %{status: 404}} ->
        {:error, :issue_not_found}
      
      {:ok, %{status: status}} ->
        Logger.warning("GitHub API returned status #{status} for #{api_url}")
        {:error, {:github_api_error, status}}
      
      {:error, reason} ->
        Logger.warning("Failed to fetch GitHub issue data: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_pull_request_data(%{owner: owner, repo: repo, number: number, url: url}, headers) do
    api_url = "#{@github_api_base}/repos/#{owner}/#{repo}/pulls/#{number}"
    
    case Req.get(api_url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, process_pull_request_data(body, url, owner, repo)}
      
      {:ok, %{status: 404}} ->
        {:error, :pull_request_not_found}
      
      {:ok, %{status: status}} ->
        Logger.warning("GitHub API returned status #{status} for #{api_url}")
        {:error, {:github_api_error, status}}
      
      {:error, reason} ->
        Logger.warning("Failed to fetch GitHub PR data: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp process_repository_data(repo_data, url) do
    %{
      type: "repository",
      url: url,
      name: repo_data["full_name"],
      title: repo_data["name"],
      description: repo_data["description"],
      language: repo_data["language"],
      stars: repo_data["stargazers_count"],
      forks: repo_data["forks_count"],
      issues_count: repo_data["open_issues_count"],
      is_private: repo_data["private"],
      is_fork: repo_data["fork"],
      owner: %{
        login: repo_data["owner"]["login"],
        avatar: repo_data["owner"]["avatar_url"]
      },
      raw: repo_data
    }
  end

  defp process_issue_data(issue_data, url, owner, repo) do
    %{
      type: "issue",
      url: url,
      title: issue_data["title"],
      number: issue_data["number"],
      state: issue_data["state"],
      repository: "#{owner}/#{repo}",
      author: %{
        login: issue_data["user"]["login"],
        avatar: issue_data["user"]["avatar_url"]
      },
      assignee: extract_assignee(issue_data["assignee"]),
      labels: extract_labels(issue_data["labels"]),
      comments_count: issue_data["comments"],
      created_at: issue_data["created_at"],
      updated_at: issue_data["updated_at"],
      body_preview: truncate_text(issue_data["body"], 150),
      raw: issue_data
    }
  end

  defp process_pull_request_data(pr_data, url, owner, repo) do
    %{
      type: "pull_request",
      url: url,
      title: pr_data["title"],
      number: pr_data["number"],
      state: pr_data["state"],
      is_draft: pr_data["draft"],
      is_mergeable: pr_data["mergeable"],
      repository: "#{owner}/#{repo}",
      author: %{
        login: pr_data["user"]["login"],
        avatar: pr_data["user"]["avatar_url"]
      },
      assignee: extract_assignee(pr_data["assignee"]),
      labels: extract_labels(pr_data["labels"]),
      comments_count: pr_data["comments"],
      commits_count: pr_data["commits"],
      additions: pr_data["additions"],
      deletions: pr_data["deletions"],
      changed_files: pr_data["changed_files"],
      created_at: pr_data["created_at"],
      updated_at: pr_data["updated_at"],
      body_preview: truncate_text(pr_data["body"], 150),
      base_branch: pr_data["base"]["ref"],
      head_branch: pr_data["head"]["ref"],
      raw: pr_data
    }
  end

  defp extract_assignee(nil), do: nil
  defp extract_assignee(assignee) do
    %{
      login: assignee["login"],
      avatar: assignee["avatar_url"]
    }
  end

  defp extract_labels(labels) when is_list(labels) do
    Enum.map(labels, fn label ->
      %{
        name: label["name"],
        color: label["color"],
        description: label["description"]
      }
    end)
  end
  defp extract_labels(_), do: []

  defp truncate_text(nil, _), do: nil
  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  ## Preview Rendering

  defp render_repository_preview(metadata, size) do
    case size do
      :compact -> render_compact_repo_preview(metadata)
      :expanded -> render_expanded_repo_preview(metadata)
      _ -> render_normal_repo_preview(metadata)
    end
  end

  defp render_issue_preview(metadata, size) do
    case size do
      :compact -> render_compact_issue_preview(metadata)
      :expanded -> render_expanded_issue_preview(metadata)
      _ -> render_normal_issue_preview(metadata)
    end
  end

  defp render_pull_request_preview(metadata, size) do
    case size do
      :compact -> render_compact_pr_preview(metadata)
      :expanded -> render_expanded_pr_preview(metadata)
      _ -> render_normal_pr_preview(metadata)
    end
  end

  defp render_generic_github_preview(metadata, _size) do
    title = safe_html_escape(metadata.title || "GitHub Link")
    url = safe_html_escape(metadata.url)
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        <div class="w-12 h-12 bg-gray-900 rounded flex-shrink-0 flex items-center justify-center">
          #{github_icon()}
        </div>
        <div class="flex-1 min-w-0">
          <h4 class="font-medium text-gray-900 truncate">#{title}</h4>
          <span class="text-xs text-gray-500">github.com</span>
        </div>
      </div>
    </a>
    """)
  end

  # Repository Previews
  defp render_compact_repo_preview(metadata) do
    name = safe_html_escape(metadata.name)
    url = safe_html_escape(metadata.url)
    stars = format_number(metadata.stars)
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" 
       class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 hover:bg-gray-100 rounded text-sm border transition-colors max-w-sm">
      #{github_icon("w-3 h-3")}
      <span class="truncate font-medium">#{name}</span>
      <span class="text-xs text-gray-500 flex-shrink-0">⭐ #{stars}</span>
    </a>
    """)
  end

  defp render_normal_repo_preview(metadata) do
    name = safe_html_escape(metadata.name)
    description = safe_html_escape(metadata.description || "")
    url = safe_html_escape(metadata.url)
    language = safe_html_escape(metadata.language || "")
    stars = format_number(metadata.stars)
    forks = format_number(metadata.forks)
    
    avatar_html = if metadata.owner.avatar do
      avatar = safe_html_escape(metadata.owner.avatar)
      "<img src=\"#{avatar}\" alt=\"\" class=\"w-12 h-12 rounded\" loading=\"lazy\">"
    else
      "<div class=\"w-12 h-12 bg-gray-900 rounded flex items-center justify-center\">#{github_icon()}</div>"
    end

    description_html = if description != "" do
      "<p class=\"text-sm text-gray-600 mt-1\">#{description}</p>"
    else
      ""
    end

    language_html = if language != "" do
      "<span class=\"text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded\">#{language}</span>"
    else
      ""
    end

    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        #{avatar_html}
        <div class="flex-1 min-w-0">
          <h4 class="font-medium text-gray-900 truncate">#{name}</h4>
          #{description_html}
          <div class="flex items-center gap-3 mt-2">
            #{language_html}
            <span class="text-xs text-gray-500 flex items-center gap-1">
              ⭐ #{stars}
            </span>
            <span class="text-xs text-gray-500 flex items-center gap-1">
              🍴 #{forks}
            </span>
            <span class="text-xs text-gray-500">github.com</span>
          </div>
        </div>
      </div>
    </a>
    """)
  end

  defp render_expanded_repo_preview(metadata) do
    # Similar to normal but with more details
    render_normal_repo_preview(metadata)
  end

  # Issue Previews
  defp render_compact_issue_preview(metadata) do
    title = safe_html_escape(metadata.title)
    url = safe_html_escape(metadata.url)
    state_class = if metadata.state == "open", do: "text-green-600", else: "text-purple-600"
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" 
       class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 hover:bg-gray-100 rounded text-sm border transition-colors max-w-sm">
      <span class="#{state_class}">#{issue_icon("w-3 h-3")}</span>
      <span class="truncate font-medium">#{title}</span>
      <span class="text-xs text-gray-500 flex-shrink-0">##{metadata.number}</span>
    </a>
    """)
  end

  defp render_normal_issue_preview(metadata) do
    title = safe_html_escape(metadata.title)
    repo = safe_html_escape(metadata.repository)
    url = safe_html_escape(metadata.url)
    state = String.capitalize(metadata.state)
    state_class = if metadata.state == "open", do: "bg-green-100 text-green-800", else: "bg-purple-100 text-purple-800"
    
    avatar_html = if metadata.author.avatar do
      avatar = safe_html_escape(metadata.author.avatar)
      "<img src=\"#{avatar}\" alt=\"\" class=\"w-8 h-8 rounded-full\" loading=\"lazy\">"
    else
      "<div class=\"w-8 h-8 bg-gray-300 rounded-full\"></div>"
    end

    labels_html = render_labels_html(metadata.labels)
    
    body_html = if metadata.body_preview do
      body = safe_html_escape(metadata.body_preview)
      "<p class=\"text-sm text-gray-600 mt-1\">#{body}</p>"
    else
      ""
    end

    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        <div class="w-12 h-12 bg-gray-900 rounded flex-shrink-0 flex items-center justify-center">
          #{github_icon()}
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-start gap-2 mb-1">
            <span class="text-green-600">#{issue_icon("w-4 h-4 mt-0.5")}</span>
            <h4 class="font-medium text-gray-900 flex-1">#{title}</h4>
            <span class="text-xs px-2 py-1 rounded #{state_class}">#{state}</span>
          </div>
          #{body_html}
          <div class="flex items-center gap-2 mt-2">
            #{avatar_html}
            <span class="text-xs text-gray-600">#{metadata.author.login}</span>
            <span class="text-xs text-gray-500">#{repo} ##{metadata.number}</span>
            <span class="text-xs text-gray-500">💬 #{metadata.comments_count}</span>
          </div>
          #{labels_html}
        </div>
      </div>
    </a>
    """)
  end

  defp render_expanded_issue_preview(metadata) do
    # Similar to normal but with more space and details
    render_normal_issue_preview(metadata)
  end

  # Pull Request Previews  
  defp render_compact_pr_preview(metadata) do
    title = safe_html_escape(metadata.title)
    url = safe_html_escape(metadata.url)
    state_class = case metadata.state do
      "open" -> "text-green-600"
      "merged" -> "text-purple-600"
      "closed" -> "text-red-600"
    end
    
    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" 
       class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 hover:bg-gray-100 rounded text-sm border transition-colors max-w-sm">
      <span class="#{state_class}">#{pr_icon("w-3 h-3")}</span>
      <span class="truncate font-medium">#{title}</span>
      <span class="text-xs text-gray-500 flex-shrink-0">##{metadata.number}</span>
    </a>
    """)
  end

  defp render_normal_pr_preview(metadata) do
    title = safe_html_escape(metadata.title)
    repo = safe_html_escape(metadata.repository)
    url = safe_html_escape(metadata.url)
    state = String.capitalize(metadata.state)
    
    state_class = case metadata.state do
      "open" -> "bg-green-100 text-green-800"
      "merged" -> "bg-purple-100 text-purple-800"  
      "closed" -> "bg-red-100 text-red-800"
    end
    
    avatar_html = if metadata.author.avatar do
      avatar = safe_html_escape(metadata.author.avatar)
      "<img src=\"#{avatar}\" alt=\"\" class=\"w-8 h-8 rounded-full\" loading=\"lazy\">"
    else
      "<div class=\"w-8 h-8 bg-gray-300 rounded-full\"></div>"
    end

    labels_html = render_labels_html(metadata.labels)
    
    body_html = if metadata.body_preview do
      body = safe_html_escape(metadata.body_preview)
      "<p class=\"text-sm text-gray-600 mt-1\">#{body}</p>"
    else
      ""
    end

    draft_badge = if metadata.is_draft do
      "<span class=\"text-xs px-2 py-1 bg-gray-100 text-gray-600 rounded\">Draft</span>"
    else
      ""
    end

    Phoenix.HTML.raw("""
    <a href="#{url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        <div class="w-12 h-12 bg-gray-900 rounded flex-shrink-0 flex items-center justify-center">
          #{github_icon()}
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-start gap-2 mb-1">
            <span class="text-green-600">#{pr_icon("w-4 h-4 mt-0.5")}</span>
            <h4 class="font-medium text-gray-900 flex-1">#{title}</h4>
            <div class="flex gap-1">
              <span class="text-xs px-2 py-1 rounded #{state_class}">#{state}</span>
              #{draft_badge}
            </div>
          </div>
          #{body_html}
          <div class="flex items-center gap-2 mt-2">
            #{avatar_html}
            <span class="text-xs text-gray-600">#{metadata.author.login}</span>
            <span class="text-xs text-gray-500">#{repo} ##{metadata.number}</span>
            <span class="text-xs text-gray-500">💬 #{metadata.comments_count}</span>
            <span class="text-xs text-gray-500">+#{metadata.additions || 0}/-#{metadata.deletions || 0}</span>
          </div>
          #{labels_html}
        </div>
      </div>
    </a>
    """)
  end

  defp render_expanded_pr_preview(metadata) do
    # Similar to normal but with more details
    render_normal_pr_preview(metadata)
  end

  ## Helper Functions

  defp render_labels_html([]), do: ""
  defp render_labels_html(labels) when length(labels) > 3 do
    # Show first 3 labels plus count
    visible_labels = Enum.take(labels, 3)
    remaining_count = length(labels) - 3
    
    labels_html = visible_labels
    |> Enum.map(fn label -> render_single_label(label) end)
    |> Enum.join("")
    
    """
    <div class="flex items-center gap-1 mt-1 flex-wrap">
      #{labels_html}
      <span class="text-xs px-2 py-1 bg-gray-100 text-gray-600 rounded">+#{remaining_count} more</span>
    </div>
    """
  end
  defp render_labels_html(labels) do
    labels_html = labels
    |> Enum.map(fn label -> render_single_label(label) end)
    |> Enum.join("")
    
    if labels_html != "" do
      "<div class=\"flex items-center gap-1 mt-1 flex-wrap\">#{labels_html}</div>"
    else
      ""
    end
  end

  defp render_single_label(label) do
    name = safe_html_escape(label.name)
    # Convert GitHub hex color to tailwind-safe background
    style = if label.color do
      "background-color: ##{label.color}; color: #{get_contrast_color(label.color)}"
    else
      ""
    end
    
    "<span class=\"text-xs px-2 py-1 rounded\" style=\"#{style}\">#{name}</span>"
  end

  defp get_contrast_color(hex_color) do
    # Simple contrast calculation - return white or black based on brightness
    case Integer.parse(hex_color, 16) do
      {color_int, ""} ->
        r = (color_int >>> 16) &&& 0xFF
        g = (color_int >>> 8) &&& 0xFF
        b = color_int &&& 0xFF
        
        # Calculate brightness using standard formula
        brightness = (r * 299 + g * 587 + b * 114) / 1000
        
        if brightness > 128, do: "#000000", else: "#FFFFFF"
      
      _ ->
        "#000000"  # Default to black
    end
  end

  defp safe_html_escape(value) when is_binary(value) do
    Phoenix.HTML.html_escape(value) |> Phoenix.HTML.safe_to_string()
  end
  defp safe_html_escape({:safe, content}) when is_binary(content) do
    content
  end
  defp safe_html_escape(value) do
    Phoenix.HTML.html_escape(to_string(value)) |> Phoenix.HTML.safe_to_string()
  end

  defp format_number(nil), do: "0"
  defp format_number(num) when is_integer(num) do
    cond do
      num >= 1000 -> "#{Float.round(num / 1000, 1)}k"
      true -> to_string(num)
    end
  end

  # SVG Icons
  defp github_icon(class \\ "w-6 h-6 text-white") do
    """
    <svg class="#{class}" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
    </svg>
    """
  end

  defp issue_icon(class) do
    """
    <svg class="#{class}" fill="currentColor" viewBox="0 0 16 16">
      <path d="M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z"/>
      <path d="M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0zM1.5 8a6.5 6.5 0 1 1 13 0 6.5 6.5 0 0 1-13 0z"/>
    </svg>
    """
  end

  defp pr_icon(class) do
    """
    <svg class="#{class}" fill="currentColor" viewBox="0 0 16 16">
      <path fill-rule="evenodd" d="M7.177 3.073L9.573.677A.25.25 0 0 1 10 .854v4.792a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354zM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5zm-2.25.75a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25zM11 2.5h-1V4h1a1 1 0 0 1 1 1v5.628a2.251 2.251 0 1 1-1.5 0V5.5a2.5 2.5 0 0 0-2.5-2.5h-1v-.5a.5.5 0 0 1 1 0V2.5z"/>
    </svg>
    """
  end

  ## OAuth2 Integration

  defp enhance_credentials_with_oauth(credentials) do
    # Try to get OAuth2 token from the current workspace
    # This will be called from the decorator pipeline which should have workspace context
    case get_workspace_oauth_token() do
      {:ok, oauth_token} ->
        Logger.debug("Using OAuth2 token for GitHub API access")
        Map.put(credentials, "token", oauth_token)
      
      {:error, reason} ->
        Logger.debug("No OAuth2 token available: #{inspect(reason)}, using unauthenticated access")
        credentials
    end
  end

  defp get_workspace_oauth_token() do
    # Get the current workspace from the process context
    # This is a bit of a hack - in a real implementation, we'd pass workspace_id through the pipeline
    case Process.get(:current_workspace_id) do
      nil ->
        # Try to get default workspace
        case get_default_workspace_id() do
          {:ok, workspace_id} -> get_github_token_for_workspace(workspace_id)
          error -> error
        end
      
      workspace_id ->
        get_github_token_for_workspace(workspace_id)
    end
  end

  defp get_default_workspace_id() do
    # For decorators, we don't have user context
    # This will need to be refactored to pass user context through the decoration pipeline
    # For now, just use the first workspace as a fallback
    import Ecto.Query
    case LifeOrg.Repo.one(from w in LifeOrg.Workspace, order_by: [asc: w.id], limit: 1) do
      %{id: id} -> {:ok, id}
      _ -> {:error, :no_default_workspace}
    end
  end

  defp get_github_token_for_workspace(workspace_id) do
    try do
      # Use the AuthController function to get the access token
      case LifeOrgWeb.AuthController.get_access_token(:github, workspace_id) do
        {:ok, token} -> {:ok, token}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error -> 
        Logger.debug("Failed to get GitHub token: #{inspect(error)}")
        {:error, :auth_controller_error}
    end
  end
end