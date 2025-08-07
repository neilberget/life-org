defmodule LifeOrg.Integrations.Decorators.WebLink do
  @moduledoc """
  Generic web link decorator that fetches Open Graph, Twitter Card, and 
  standard HTML meta tags to provide rich link previews.
  """

  @behaviour LifeOrg.Integrations.Integration
  @behaviour LifeOrg.Integrations.Decorator
  require Logger

  # Integration behavior callbacks
  @impl true
  def name, do: "Generic Web Link"
  
  @impl true
  def provider, do: :web
  
  @impl true
  def capabilities, do: [:fetch_metadata, :render_preview]
  
  @impl true
  def configure(config), do: {:ok, config}
  
  @impl true
  def type, do: :decorator
  
  @impl true
  def validate_settings(settings), do: {:ok, settings}

  # Decorator behavior callbacks
  @impl true
  def priority, do: 1
  
  @impl true
  def match_url(url) do
    # Match any HTTP/HTTPS URL that's not handled by a more specific decorator
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end


  @impl true
  def fetch_metadata(url, _credentials) do
    Logger.debug("Fetching metadata for URL: #{url}")
    
    case LifeOrg.LinkFetcher.fetch_metadata(url) do
      {:ok, metadata} ->
        processed_metadata = process_metadata(metadata, url)
        {:ok, processed_metadata}
      
      {:error, reason} ->
        Logger.warning("Failed to fetch metadata for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def render_preview(metadata, opts \\ %{}) do
    size = Map.get(opts, :size, :normal)
    
    case size do
      :compact -> render_compact_preview(metadata)
      :expanded -> render_expanded_preview(metadata)
      _ -> render_normal_preview(metadata)
    end
  end

  ## Private Functions

  defp process_metadata(raw_metadata, url) do
    %{
      url: url,
      title: extract_title(raw_metadata),
      description: extract_description(raw_metadata),
      image: extract_image(raw_metadata),
      site_name: extract_site_name(raw_metadata),
      domain: extract_domain(url),
      type: "web_link",
      raw: raw_metadata
    }
  end

  defp extract_title(metadata) do
    metadata
    |> get_in(["og:title"])
    |> fallback(get_in(metadata, ["twitter:title"]))
    |> fallback(get_in(metadata, ["title"]))
    |> fallback("Untitled")
    |> String.trim()
    |> truncate(100)
  end

  defp extract_description(metadata) do
    metadata
    |> get_in(["og:description"])
    |> fallback(get_in(metadata, ["twitter:description"]))
    |> fallback(get_in(metadata, ["description"]))
    |> case do
      nil -> nil
      desc -> String.trim(desc) |> truncate(200)
    end
  end

  defp extract_image(metadata) do
    image_url = 
      metadata
      |> get_in(["og:image"])
      |> fallback(get_in(metadata, ["twitter:image"]))
    
    case image_url do
      nil -> nil
      url when is_binary(url) -> normalize_image_url(url)
      _ -> nil
    end
  end

  defp extract_site_name(metadata) do
    metadata
    |> get_in(["og:site_name"])
    |> fallback(get_in(metadata, ["twitter:site"]))
    |> case do
      nil -> nil
      name -> String.trim(name) |> truncate(50)
    end
  end

  defp extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "Unknown"
    end
  end

  defp fallback(nil, alternative), do: alternative
  defp fallback("", alternative), do: alternative
  defp fallback(value, _alternative), do: value

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end
  defp truncate(nil, _), do: nil

  defp normalize_image_url(url) do
    # Handle relative URLs
    cond do
      String.starts_with?(url, "http") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      true -> url  # Leave relative URLs as-is for now
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

  ## Preview Rendering

  defp render_compact_preview(metadata) do
    escaped_title = safe_html_escape(metadata.title)
    escaped_domain = safe_html_escape(metadata.domain)
    
    Phoenix.HTML.raw("""
    <div class="inline-flex items-center gap-2 px-2 py-1 bg-gray-50 rounded text-sm border max-w-sm">
      <svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.102m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
      </svg>
      <span class="truncate">#{escaped_title}</span>
      <span class="text-xs text-gray-500 flex-shrink-0">#{escaped_domain}</span>
    </div>
    """)
  end

  defp render_normal_preview(metadata) do
    description_html = if metadata.description do
      escaped_desc = safe_html_escape(metadata.description)
      "<p class=\"text-sm text-gray-600 mt-1\">#{escaped_desc}</p>"
    else
      ""
    end

    image_html = if metadata.image do
      escaped_image = safe_html_escape(metadata.image)
      """
      <div class="w-12 h-12 bg-gray-200 rounded flex-shrink-0 overflow-hidden">
        <img src="#{escaped_image}" alt="" class="w-full h-full object-cover" onerror="this.style.display='none'">
      </div>
      """
    else
      """
      <div class="w-12 h-12 bg-gray-200 rounded flex-shrink-0 flex items-center justify-center">
        <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.102m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
        </svg>
      </div>
      """
    end

    site_name_html = if metadata.site_name do
      escaped_site = safe_html_escape(metadata.site_name)
      " • #{escaped_site}"
    else
      ""
    end

    escaped_title = safe_html_escape(metadata.title)
    escaped_domain = safe_html_escape(metadata.domain)
    escaped_url = safe_html_escape(metadata.url)

    Phoenix.HTML.raw("""
    <a href="#{escaped_url}" target="_blank" rel="noopener noreferrer" class="block mb-2 no-underline hover:no-underline" style="text-decoration: none !important;">
      <div class="flex gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-100 transition-all">
        #{image_html}
        <div class="flex-1 min-w-0">
          <h4 class="font-medium text-gray-900 truncate m-0" style="text-decoration: none !important; margin: 0 !important;">#{escaped_title}</h4>
          <div style="text-decoration: none !important;">#{description_html}</div>
          <div class="flex items-center gap-1 mt-2">
            <span class="text-xs text-gray-500" style="text-decoration: none !important;">#{escaped_domain}#{site_name_html}</span>
          </div>
        </div>
      </div>
    </a>
    """)
  end

  defp render_expanded_preview(metadata) do
    description_html = if metadata.description do
      escaped_desc = safe_html_escape(metadata.description)
      "<p class=\"text-gray-600 mt-2\">#{escaped_desc}</p>"
    else
      ""
    end

    image_html = if metadata.image do
      escaped_image = safe_html_escape(metadata.image)
      """
      <div class="w-full h-48 bg-gray-200 rounded-lg overflow-hidden mb-4">
        <img src="#{escaped_image}" alt="" class="w-full h-full object-cover" onerror="this.style.display='none'">
      </div>
      """
    else
      ""
    end

    site_name_html = if metadata.site_name do
      escaped_site = safe_html_escape(metadata.site_name)
      " • #{escaped_site}"
    else
      ""
    end

    escaped_title = safe_html_escape(metadata.title)
    escaped_domain = safe_html_escape(metadata.domain)

    Phoenix.HTML.raw("""
    <div class="p-4 bg-white rounded-lg border border-gray-200 shadow-sm hover:shadow-md transition-shadow mt-3 mb-3 max-w-lg">
      #{image_html}
      <div>
        <h3 class="text-lg font-semibold text-gray-900 mb-1">#{escaped_title}</h3>
        #{description_html}
        <div class="flex items-center gap-1 mt-3 pt-3 border-t border-gray-100">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.102m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
          </svg>
          <span class="text-sm text-gray-500">#{escaped_domain}#{site_name_html}</span>
        </div>
      </div>
    </div>
    """)
  end
end