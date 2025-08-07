defmodule LifeOrg.LinkDetector do
  @moduledoc """
  Detects and extracts URLs from text content.
  
  This module provides functions to find URLs in markdown content and 
  return them with their positions for later enhancement.
  """

  # Comprehensive URL regex pattern - matches http(s):// URLs with paths
  @url_pattern ~r/(?i)(?:https?:\/\/)[-\w.]+(?:\.[a-z]{2,})+(?::\d+)?(?:\/[^\s\)]*)?/

  # More permissive pattern that includes www. without protocol  
  @url_pattern_permissive ~r/(?i)(?:www\.)[-\w.]+\.[a-z]{2,}(?::\d+)?(?:\/[^\s\)]*)??/

  @doc """
  Extracts all URLs from the given text content.
  
  Returns a list of maps with :url, :start_pos, and :end_pos keys.
  URLs are deduplicated but positions are preserved.
  
  ## Examples
  
      iex> LifeOrg.LinkDetector.extract_urls("Check out https://example.com and https://github.com/user/repo")
      [
        %{url: "https://example.com", start_pos: 10, end_pos: 29},
        %{url: "https://github.com/user/repo", start_pos: 34, end_pos: 59}
      ]
  """
  def extract_urls(content) when is_binary(content) do
    extract_with_pattern(content, @url_pattern) ++
    extract_with_pattern(content, @url_pattern_permissive)
    |> normalize_urls()
    |> deduplicate_by_url()
    |> Enum.sort_by(& &1.start_pos)
  end

  def extract_urls(_content), do: []

  @doc """
  Extracts just the URL strings without position information.
  
  ## Examples
  
      iex> LifeOrg.LinkDetector.extract_url_strings("Visit https://example.com")
      ["https://example.com"]
  """
  def extract_url_strings(content) do
    extract_urls(content)
    |> Enum.map(& &1.url)
    |> Enum.uniq()
  end

  @doc """
  Checks if the given string contains any URLs.
  
  ## Examples
  
      iex> LifeOrg.LinkDetector.contains_urls?("Check out https://example.com")
      true
      
      iex> LifeOrg.LinkDetector.contains_urls?("No links here")
      false
  """
  def contains_urls?(content) do
    content
    |> extract_urls()
    |> Enum.any?()
  end

  @doc """
  Validates if a string is a properly formatted URL.
  
  ## Examples
  
      iex> LifeOrg.LinkDetector.valid_url?("https://example.com")
      true
      
      iex> LifeOrg.LinkDetector.valid_url?("not-a-url")
      false
  """
  def valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        scheme in ["http", "https"] and String.contains?(host, ".")
      _ ->
        false
    end
  end

  @doc """
  Normalizes a URL by ensuring it has a protocol and cleaning up the format.
  
  ## Examples
  
      iex> LifeOrg.LinkDetector.normalize_url("www.example.com")
      "https://www.example.com"
      
      iex> LifeOrg.LinkDetector.normalize_url("https://example.com")
      "https://example.com"
  """
  def normalize_url(url) do
    url = String.trim(url)
    
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url
      String.starts_with?(url, "www.") ->
        "https://" <> url
      String.contains?(url, ".") and not String.contains?(url, " ") ->
        "https://" <> url
      true ->
        url
    end
  end

  ## Private Functions

  defp extract_with_pattern(content, pattern) do
    pattern
    |> Regex.scan(content, return: :index)
    |> List.flatten()
    |> Enum.map(fn {start_pos, length} ->
      end_pos = start_pos + length
      url = String.slice(content, start_pos, length)
      
      %{
        url: url,
        start_pos: start_pos,
        end_pos: end_pos
      }
    end)
  end

  defp normalize_urls(url_matches) do
    Enum.map(url_matches, fn match ->
      %{match | url: normalize_url(match.url)}
    end)
  end

  defp deduplicate_by_url(url_matches) do
    url_matches
    |> Enum.group_by(& &1.url)
    |> Enum.map(fn {_url, matches} -> 
      # Keep the first occurrence of each URL
      hd(matches) 
    end)
  end
end