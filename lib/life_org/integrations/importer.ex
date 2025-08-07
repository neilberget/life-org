defmodule LifeOrg.Integrations.Importer do
  @moduledoc """
  Behavior for content importer integrations.
  
  Importers fetch data from external systems and convert it into 
  local todos, journal entries, or other content.
  """

  @doc """
  Lists items available for import from the external system.
  
  Args:
  - credentials: Authentication credentials
  - opts: Options like filters, pagination, etc.
  
  Returns:
  - {:ok, items} - list of importable items
  - {:error, reason} - if listing fails
  """
  @callback list_importable_items(credentials :: map(), opts :: map()) ::
    {:ok, [map()]} | {:error, any()}

  @doc """
  Imports selected items into the local system.
  
  Args:
  - items: List of items to import (from list_importable_items)
  - credentials: Authentication credentials
  - opts: Import options (workspace_id, field_mappings, etc.)
  
  Returns:
  - {:ok, %{imported: count, skipped: count, errors: [...]}}
  - {:error, reason}
  """
  @callback import_items(items :: [map()], credentials :: map(), opts :: map()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Maps an external item to a local schema (todo or journal_entry).
  
  Args:
  - item: External item data
  - target_schema: :todo or :journal_entry
  - field_mappings: Map of external_field => local_field
  
  Returns a map suitable for creating local records.
  """
  @callback map_to_local_schema(item :: map(), target_schema :: atom(), field_mappings :: map()) :: map()

  @doc """
  Validates that an item can be imported (e.g., required fields present).
  """
  @callback validate_item(item :: map(), target_schema :: atom()) :: {:ok, map()} | {:error, String.t()}

  @doc """
  Returns available field mappings for this importer.
  Format: %{external_field => %{type: :string, required: true, description: "..."}}
  """
  @callback available_fields() :: map()

  defmacro __using__(_opts) do
    quote do
      use LifeOrg.Integrations.Integration, type: :importer
      @behaviour LifeOrg.Integrations.Importer

      def validate_item(item, _target_schema), do: {:ok, item}

      defoverridable validate_item: 2
    end
  end
end