defmodule LifeOrg.Integrations.Syncer do
  @moduledoc """
  Behavior for content syncer integrations.
  
  Syncers provide bidirectional synchronization between local content 
  and external systems. This is for future implementation.
  """

  @doc """
  Syncs changes from local to external system.
  
  Args:
  - changes: List of local changes to sync
  - credentials: Authentication credentials
  - opts: Sync options
  
  Returns:
  - {:ok, %{synced: count, conflicts: [...]}}
  - {:error, reason}
  """
  @callback sync_to_external(changes :: [map()], credentials :: map(), opts :: map()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Syncs changes from external to local system.
  
  Args:
  - since: Last sync timestamp
  - credentials: Authentication credentials
  - opts: Sync options
  
  Returns:
  - {:ok, %{synced: count, conflicts: [...]}}
  - {:error, reason}
  """
  @callback sync_from_external(since :: DateTime.t(), credentials :: map(), opts :: map()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Resolves sync conflicts between local and external data.
  
  Args:
  - conflicts: List of conflict maps
  - resolution_strategy: :local_wins | :external_wins | :manual
  - opts: Resolution options
  
  Returns resolved conflicts.
  """
  @callback resolve_conflicts(conflicts :: [map()], resolution_strategy :: atom(), opts :: map()) ::
    {:ok, [map()]} | {:error, any()}

  defmacro __using__(_opts) do
    quote do
      use LifeOrg.Integrations.Integration, type: :syncer
      @behaviour LifeOrg.Integrations.Syncer
    end
  end
end