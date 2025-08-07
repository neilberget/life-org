defmodule LifeOrg.LinkFetcher do
  @moduledoc """
  Service for fetching and caching link metadata.
  
  This module handles HTTP requests to fetch web pages, parse HTML for 
  metadata (Open Graph, Twitter Cards, standard meta tags), and cache 
  the results to avoid repeated requests.
  """

  use GenServer
  require Logger
  alias LifeOrg.{LinkMetadata, Repo}
  import Ecto.Query

  @fetch_timeout 10_000  # 10 seconds
  @user_agent "LifeOrg/1.0 (+https://github.com/yourorg/life-org)"

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Fetches metadata for a URL, using cache if available and not expired.
  
  Returns {:ok, metadata} or {:error, reason}.
  """
  def fetch_metadata(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:fetch_metadata, url}, @fetch_timeout + 1000)
  end

  @doc """
  Synchronously fetches metadata without caching (for testing).
  """
  def fetch_metadata_sync(url) when is_binary(url) do
    fetch_from_web(url)
  end

  @doc """
  Clears expired cache entries.
  """
  def cleanup_cache do
    GenServer.cast(__MODULE__, :cleanup_cache)
  end

  ## Server Callbacks

  def init(_opts) do
    # Schedule periodic cache cleanup
    schedule_cleanup()
    {:ok, %{}}
  end

  def handle_call({:fetch_metadata, url}, _from, state) do
    result = 
      case get_cached_metadata(url) do
        {:ok, metadata} ->
          Logger.debug("Using cached metadata for #{url}")
          {:ok, metadata}
        
        {:error, :not_found} ->
          Logger.debug("Fetching fresh metadata for #{url}")
          fetch_and_cache_metadata(url)
        
        {:error, :expired} ->
          Logger.debug("Cache expired for #{url}, fetching fresh metadata")
          fetch_and_cache_metadata(url)
      end
    
    {:reply, result, state}
  end

  def handle_cast(:cleanup_cache, state) do
    cleanup_expired_cache()
    schedule_cleanup()
    {:reply, :ok, state}
  end

  def handle_info(:cleanup_cache, state) do
    cleanup_expired_cache()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp get_cached_metadata(url) do
    query = from(lm in LinkMetadata,
              where: lm.url == ^url,
              order_by: [desc: lm.cached_at],
              limit: 1)
    
    case Repo.one(query) do
      nil ->
        {:error, :not_found}
      
      %LinkMetadata{} = cached ->
        if LinkMetadata.expired?(cached) do
          {:error, :expired}
        else
          {:ok, cached.metadata}
        end
    end
  end

  defp fetch_and_cache_metadata(url) do
    case fetch_from_web(url) do
      {:ok, metadata} ->
        cache_metadata(url, metadata)
        {:ok, metadata}
      
      {:error, _reason} = error ->
        error
    end
  end

  defp fetch_from_web(url) do
    normalized_url = LifeOrg.LinkDetector.normalize_url(url)
    
    Logger.debug("Fetching URL: #{normalized_url}")
    
    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.5"},
      {"Accept-Encoding", "gzip, deflate"}
    ]

    options = [
      receive_timeout: @fetch_timeout,
      max_redirects: 5,
      headers: headers
    ]

    case Req.get(normalized_url, options) do
      {:ok, %{status: 200, body: body, headers: response_headers}} ->
        content_type = get_content_type(response_headers)
        
        if is_html_content?(content_type) do
          parse_html_metadata(body, normalized_url)
        else
          {:error, :not_html}
        end
      
      {:ok, %{status: status}} ->
        Logger.warning("HTTP #{status} for #{normalized_url}")
        {:error, {:http_error, status}}
      
      {:error, reason} ->
        Logger.warning("Request failed for #{normalized_url}: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  rescue
    error ->
      Logger.error("Exception fetching #{url}: #{inspect(error)}")
      {:error, {:exception, error}}
  end

  defp get_content_type(headers) do
    # Req returns headers as a map, not a list of tuples
    case headers do
      %{} = header_map ->
        # Look for content-type header (case insensitive)
        content_type = 
          header_map
          |> Enum.find_value(fn {key, value} -> 
            if String.downcase(to_string(key)) == "content-type" do
              to_string(value)
            end
          end)
        
        if content_type, do: String.downcase(content_type), else: ""
      
      headers when is_list(headers) ->
        # Fallback for list format
        headers
        |> Enum.find(fn {name, _value} -> String.downcase(to_string(name)) == "content-type" end)
        |> case do
          {_name, value} -> String.downcase(to_string(value))
          nil -> ""
        end
      
      _ -> 
        ""
    end
  end

  defp is_html_content?(content_type) do
    String.contains?(content_type, "text/html") or String.contains?(content_type, "application/xhtml")
  end

  defp parse_html_metadata(html, url) do
    try do
      {:ok, document} = Floki.parse_document(html)
      
      metadata = %{
        "title" => extract_title(document),
        "description" => extract_description(document)
      }
      |> Map.merge(extract_og_tags(document))
      |> Map.merge(extract_twitter_tags(document))
      |> Map.merge(extract_meta_tags(document))
      
      {:ok, metadata}
    rescue
      error ->
        Logger.error("Failed to parse HTML for #{url}: #{inspect(error)}")
        {:error, {:parse_error, error}}
    end
  end

  defp extract_title(document) do
    case Floki.find(document, "title") do
      [{"title", _, [title]}] when is_binary(title) -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_description(document) do
    case Floki.find(document, "meta[name='description']") do
      [{"meta", attrs, _}] -> get_content_attr(attrs)
      _ -> nil
    end
  end

  defp extract_og_tags(document) do
    document
    |> Floki.find("meta[property^='og:']")
    |> Enum.reduce(%{}, fn {"meta", attrs, _}, acc ->
      property = get_attr(attrs, "property")
      content = get_content_attr(attrs)
      
      if property && content do
        Map.put(acc, property, content)
      else
        acc
      end
    end)
  end

  defp extract_twitter_tags(document) do
    document
    |> Floki.find("meta[name^='twitter:']")
    |> Enum.reduce(%{}, fn {"meta", attrs, _}, acc ->
      name = get_attr(attrs, "name")
      content = get_content_attr(attrs)
      
      if name && content do
        Map.put(acc, name, content)
      else
        acc
      end
    end)
  end

  defp extract_meta_tags(document) do
    # Extract other useful meta tags
    keywords = case Floki.find(document, "meta[name='keywords']") do
      [{"meta", attrs, _}] -> get_content_attr(attrs)
      _ -> nil
    end
    
    author = case Floki.find(document, "meta[name='author']") do
      [{"meta", attrs, _}] -> get_content_attr(attrs)
      _ -> nil
    end

    %{}
    |> maybe_put("keywords", keywords)
    |> maybe_put("author", author)
  end

  defp get_attr(attrs, name) do
    case Enum.find(attrs, fn {attr_name, _} -> String.downcase(attr_name) == String.downcase(name) end) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_content_attr(attrs) do
    get_attr(attrs, "content")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp cache_metadata(url, metadata) do
    now = DateTime.utc_now()
    expires_at = LinkMetadata.build_expires_at(now)
    
    attrs = %{
      url: url,
      metadata: metadata,
      cached_at: now,
      expires_at: expires_at
    }

    case Repo.insert(LinkMetadata.changeset(%LinkMetadata{}, attrs)) do
      {:ok, _cached} ->
        Logger.debug("Cached metadata for #{url}")
        :ok
      
      {:error, changeset} ->
        Logger.warning("Failed to cache metadata for #{url}: #{inspect(changeset.errors)}")
        :error
    end
  end

  defp cleanup_expired_cache do
    now = DateTime.utc_now()
    
    query = from(lm in LinkMetadata, where: lm.expires_at < ^now)
    
    case Repo.delete_all(query) do
      {count, _} when count > 0 ->
        Logger.info("Cleaned up #{count} expired cache entries")
      
      {0, _} ->
        Logger.debug("No expired cache entries to clean up")
    end
  end

  defp schedule_cleanup do
    # Clean up cache every hour
    Process.send_after(self(), :cleanup_cache, 60 * 60 * 1000)
  end
end