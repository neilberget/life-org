defmodule LifeOrg.Integrations.Integration do
  @moduledoc """
  Base behavior that all integrations must implement.
  
  This defines the common interface for all integration types (decorators, importers, etc).
  """

  @doc """
  Returns the human-readable name of the integration.
  """
  @callback name() :: String.t()

  @doc """
  Returns the provider atom (e.g., :asana, :jira, :github, :web).
  """
  @callback provider() :: atom()

  @doc """
  Returns a list of capabilities this integration supports.
  Examples: [:authenticate, :fetch_metadata, :import_todos]
  """
  @callback capabilities() :: [atom()]

  @doc """
  Validates and processes configuration for this integration.
  Returns {:ok, processed_config} or {:error, reason}.
  """
  @callback configure(config :: map()) :: {:ok, map()} | {:error, String.t()}

  @doc """
  Returns the integration type (:decorator, :importer, :syncer, :trigger).
  """
  @callback type() :: atom()

  @doc """
  Validates user-specific settings for this integration.
  Returns {:ok, processed_settings} or {:error, reason}.
  """
  @callback validate_settings(settings :: map()) :: {:ok, map()} | {:error, String.t()}

  @optional_callbacks [validate_settings: 1]

  defmacro __using__(opts) do
    integration_type = Keyword.get(opts, :type)

    quote do
      @behaviour LifeOrg.Integrations.Integration

      def type, do: unquote(integration_type)

      def validate_settings(settings), do: {:ok, settings}

      defoverridable validate_settings: 1
    end
  end
end