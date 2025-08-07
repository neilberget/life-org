defmodule LifeOrg.Decorators.Pipeline do
  @moduledoc """
  Pipeline for processing content and injecting link previews.
  
  This module orchestrates the link detection, decorator matching,
  metadata fetching, and preview injection process.
  """

  require Logger
  alias LifeOrg.{LinkDetector, Integrations.Registry}

  @doc """
  Processes content by detecting URLs and injecting preview components.
  
  Returns processed HTML with link previews injected inline.
  """
  def process_content(content, workspace_id \\ nil, opts \\ %{})

  def process_content(nil, _workspace_id, _opts), do: ""
  def process_content("", _workspace_id, _opts), do: ""

  def process_content(content, workspace_id, opts) when is_binary(content) do
    if should_process_content?(content, opts) do
      do_process_content(content, workspace_id, opts)
    else
      content
    end
  end

  @doc """
  Processes content asynchronously and returns a task reference.
  Useful for LiveView async assigns.
  """
  def process_content_async(content, workspace_id \\ nil, opts \\ %{}) do
    Task.async(fn ->
      process_content(content, workspace_id, opts)
    end)
  end

  defp process_html(html, original_content, workspace_id, opts) do
    if should_process_content?(original_content, opts) do
      do_process_html(html, original_content, workspace_id, opts)
    else
      html
    end
  end

  ## Private Functions

  defp should_process_content?(content, opts) do
    # Skip processing if disabled or content too short
    enabled = Map.get(opts, :enable_decorators, true)
    min_length = Map.get(opts, :min_content_length, 10)
    
    enabled and 
    String.length(content) >= min_length and
    LinkDetector.contains_urls?(content)
  end

  defp do_process_content(content, workspace_id, opts) do
    Logger.debug("Processing content for decorators")
    
    # Set workspace context for OAuth2 token access
    if workspace_id do
      Process.put(:current_workspace_id, workspace_id)
    end
    
    # Extract URLs from content
    urls = LinkDetector.extract_urls(content)
    
    if Enum.empty?(urls) do
      content
    else
      # Process URLs and inject previews
      result = process_urls_and_inject(content, urls, workspace_id, opts)
      
      # Clean up process context
      Process.delete(:current_workspace_id)
      
      result
    end
  end

  defp do_process_html(html, original_content, workspace_id, opts) do
    Logger.debug("Processing HTML for decorators while preserving existing elements")
    
    # Set workspace context for OAuth2 token access
    if workspace_id do
      Process.put(:current_workspace_id, workspace_id)
    end
    
    # Extract URLs from original content (not HTML)
    urls = LinkDetector.extract_urls(original_content)
    
    if Enum.empty?(urls) do
      html
    else
      # Process URLs and inject previews into existing HTML
      result = process_urls_and_inject_html(html, urls, workspace_id, opts)
      
      # Clean up process context
      Process.delete(:current_workspace_id)
      
      result
    end
  end

  defp process_urls_and_inject(content, urls, workspace_id, opts) do
    # Group URLs by decorator to batch process them
    url_decorator_pairs = 
      urls
      |> Enum.map(fn url_info ->
        decorators = Registry.get_decorators_for_url(url_info.url)
        {url_info, List.first(decorators)}  # Use highest priority decorator
      end)
      |> Enum.filter(fn {_url_info, decorator} -> decorator != nil end)

    if Enum.empty?(url_decorator_pairs) do
      Logger.debug("No decorators found for URLs")
      content
    else
      # Fetch metadata for all URLs
      metadata_results = fetch_metadata_batch(url_decorator_pairs, workspace_id, opts)
      
      # Inject previews into content
      inject_previews(content, metadata_results, opts)
    end
  end

  defp process_urls_and_inject_html(html, urls, workspace_id, opts) do
    # Group URLs by decorator to batch process them
    url_decorator_pairs = 
      urls
      |> Enum.map(fn url_info ->
        decorators = Registry.get_decorators_for_url(url_info.url)
        {url_info, List.first(decorators)}  # Use highest priority decorator
      end)
      |> Enum.filter(fn {_url_info, decorator} -> decorator != nil end)

    if Enum.empty?(url_decorator_pairs) do
      Logger.debug("No decorators found for URLs")
      html
    else
      # Fetch metadata for all URLs
      metadata_results = fetch_metadata_batch(url_decorator_pairs, workspace_id, opts)
      
      # Inject previews into HTML by appending to the end
      inject_previews_html(html, metadata_results, opts)
    end
  end

  defp fetch_metadata_batch(url_decorator_pairs, _workspace_id, opts) do
    timeout = Map.get(opts, :fetch_timeout, 5000)
    
    url_decorator_pairs
    |> Task.async_stream(
      fn {url_info, decorator} ->
        fetch_single_metadata(url_info, decorator, opts)
      end,
      timeout: timeout,
      on_timeout: :kill_task,
      max_concurrency: 4
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> 
        Logger.warning("Metadata fetch timed out")
        nil
    end)
    |> Enum.filter(& &1 != nil)
  end

  defp fetch_single_metadata(url_info, decorator, _opts) do
    case decorator.fetch_metadata(url_info.url, %{}) do
      {:ok, metadata} ->
        preview_html = decorator.render_preview(metadata, %{size: :normal})
        
        %{
          url_info: url_info,
          metadata: metadata,
          preview_html: preview_html,
          decorator: decorator
        }
      
      {:error, reason} ->
        Logger.debug("Failed to fetch metadata for #{url_info.url}: #{inspect(reason)}")
        nil
    end
  end

  defp inject_previews(content, metadata_results, _opts) do
    # Sort by position in reverse order to maintain positions during injection
    sorted_results = Enum.sort_by(metadata_results, & &1.url_info.start_pos, :desc)
    
    Enum.reduce(sorted_results, content, fn result, acc_content ->
      inject_single_preview(acc_content, result)
    end)
  end

  defp inject_previews_html(html, metadata_results, _opts) do
    # For HTML processing, append all previews at the end to preserve existing structure
    preview_htmls = 
      metadata_results
      |> Enum.filter(& &1.preview_html)
      |> Enum.map(&safe_html_to_string/1)
      |> Enum.join("\n")
    
    if preview_htmls != "" do
      html <> "\n" <> preview_htmls
    else
      html
    end
  end

  defp safe_html_to_string(%{preview_html: {:safe, content}}), do: content
  defp safe_html_to_string(%{preview_html: content}) when is_binary(content), do: content
  defp safe_html_to_string(%{preview_html: nil}), do: ""
  defp safe_html_to_string(result) when is_map(result) do
    case Map.get(result, :preview_html) do
      {:safe, content} -> content
      content when is_binary(content) -> content
      nil -> ""
      other -> to_string(other)
    end
  end

  defp inject_single_preview(content, %{url_info: url_info, preview_html: preview_html}) do
    # Find the end of the line containing the URL
    line_end_pos = find_line_end(content, url_info.end_pos)
    
    # Split content and inject preview
    {before, remaining} = String.split_at(content, line_end_pos)
    
    preview_html_string = Phoenix.HTML.safe_to_string(preview_html)
    
    before <> "\n" <> preview_html_string <> remaining
  end

  defp find_line_end(content, start_pos) do
    content
    |> String.slice(start_pos..-1//1)
    |> String.split("\n", parts: 2)
    |> case do
      [first_part] -> start_pos + String.length(first_part)  # No newline found
      [first_part, _rest] -> start_pos + String.length(first_part)  # Found newline
    end
  end

  @doc """
  Processes content with enhanced error handling and fallback.
  Returns processed content or original content if processing fails.
  """
  def process_content_safe(content, workspace_id \\ nil, opts \\ %{}) do
    try do
      process_content(content, workspace_id, opts)
    rescue
      error ->
        Logger.error("Content processing failed: #{inspect(error)}")
        content
    catch
      :exit, reason ->
        Logger.error("Content processing exited: #{inspect(reason)}")
        content
    end
  end

  @doc """
  Processes existing HTML by detecting URLs in the original content and injecting link previews
  while preserving existing HTML elements (like interactive checkboxes).
  """
  def process_html_safe(html, original_content, workspace_id \\ nil, opts \\ %{}) do
    try do
      process_html(html, original_content, workspace_id, opts)
    rescue
      error ->
        Logger.error("HTML processing failed: #{inspect(error)}")
        html
    catch
      :exit, reason ->
        Logger.error("HTML processing exited: #{inspect(reason)}")
        html
    end
  end

  @doc """
  Strips all link previews from processed content, leaving only original text.
  Useful for editing or exporting plain content.
  """
  def strip_previews(processed_content) do
    # Simple approach: remove common preview HTML patterns
    processed_content
    |> String.replace(~r/<div class="[^"]*bg-gray-50[^"]*">.*?<\/div>/s, "")
    |> String.replace(~r/<div class="[^"]*bg-white[^"]*">.*?<\/div>/s, "")
    |> String.replace(~r/\n\s*\n\s*\n/, "\n\n")  # Clean up extra newlines
    |> String.trim()
  end
end