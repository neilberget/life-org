defmodule LifeOrg.Integrations.Decorator do
  @moduledoc """
  Behavior for content decorator integrations.
  
  Decorators enhance existing content by fetching metadata for URLs and 
  rendering rich previews inline.
  """

  @doc """
  Determines if this decorator can handle the given URL.
  Returns true if the URL matches this decorator's pattern.
  """
  @callback match_url(url :: String.t()) :: boolean()

  @doc """
  Fetches metadata for the given URL using the provided credentials.
  
  Returns:
  - {:ok, metadata} - metadata as a map
  - {:error, reason} - if fetching fails
  """
  @callback fetch_metadata(url :: String.t(), credentials :: map()) :: 
    {:ok, map()} | {:error, any()}

  @doc """
  Renders a preview component for the given metadata.
  
  Args:
  - metadata: The metadata map returned from fetch_metadata/2
  - opts: Rendering options (e.g., size: :compact, show_description: true)
  
  Returns Phoenix.HTML.safe() content
  """
  @callback render_preview(metadata :: map(), opts :: map()) :: Phoenix.HTML.safe()

  @doc """
  Returns the priority of this decorator (higher number = higher priority).
  Used when multiple decorators match the same URL.
  """
  @callback priority() :: integer()

  @optional_callbacks [priority: 0]

  defmacro __using__(_opts) do
    quote do
      use LifeOrg.Integrations.Integration, type: :decorator
      @behaviour LifeOrg.Integrations.Decorator

      def priority, do: 0

      defoverridable priority: 0
    end
  end
end