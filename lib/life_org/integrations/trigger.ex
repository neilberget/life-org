defmodule LifeOrg.Integrations.Trigger do
  @moduledoc """
  Behavior for automation trigger integrations.
  
  Triggers react to external events (webhooks, polling) and create or 
  modify local content automatically. This is for future implementation.
  """

  @doc """
  Handles an incoming webhook event.
  
  Args:
  - event: The webhook event data
  - credentials: Authentication credentials
  - opts: Processing options (workspace_id, rules, etc.)
  
  Returns:
  - {:ok, %{actions_taken: [...]}}
  - {:error, reason}
  """
  @callback handle_webhook(event :: map(), credentials :: map(), opts :: map()) ::
    {:ok, map()} | {:error, any()}

  @doc """
  Polls the external system for new events.
  
  Args:
  - since: Last poll timestamp
  - credentials: Authentication credentials
  - opts: Polling options
  
  Returns:
  - {:ok, events} - list of new events
  - {:error, reason}
  """
  @callback poll_events(since :: DateTime.t(), credentials :: map(), opts :: map()) ::
    {:ok, [map()]} | {:error, any()}

  @doc """
  Processes an event according to user-defined rules.
  
  Args:
  - event: The event to process
  - rules: List of user-defined automation rules
  - opts: Processing options
  
  Returns list of actions to take.
  """
  @callback process_event(event :: map(), rules :: [map()], opts :: map()) :: [map()]

  @doc """
  Validates webhook signatures/authenticity.
  """
  @callback validate_webhook(headers :: map(), body :: String.t(), secret :: String.t()) :: boolean()

  defmacro __using__(_opts) do
    quote do
      use LifeOrg.Integrations.Integration, type: :trigger
      @behaviour LifeOrg.Integrations.Trigger
    end
  end
end