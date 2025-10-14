defmodule LifeOrg.FaviconFetcher do
  @moduledoc """
  Fetches favicons from URLs using Google's favicon service
  """

  require Logger

  @doc """
  Fetches favicon URL for a given website URL using Google's favicon service
  """
  def fetch_favicon(url) when is_binary(url) do
    with {:ok, uri} <- parse_url(url) do
      favicon_url = "https://www.google.com/s2/favicons?domain=#{uri.host}&sz=32"
      {:ok, favicon_url}
    else
      error ->
        Logger.debug("Failed to parse URL for favicon #{url}: #{inspect(error)}")
        {:error, :invalid_url}
    end
  end

  def fetch_favicon(_), do: {:error, :invalid_url}

  defp parse_url(url) do
    uri = URI.parse(url)
    
    if uri.scheme in ["http", "https"] && uri.host do
      {:ok, uri}
    else
      {:error, :invalid_url}
    end
  end
end