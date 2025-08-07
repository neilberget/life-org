defmodule LifeOrg.Integrations.Registry do
  @moduledoc """
  Manages registration and lookup of all integration modules.
  
  The registry maintains a list of available integrations and provides
  functions to find the right integration for a given task.
  """

  use GenServer
  require Logger

  @registry_name __MODULE__

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Registers an integration module with the registry.
  
  The module must implement the appropriate behavior (Decorator, Importer, etc.).
  """
  def register_integration(module, opts \\ []) do
    GenServer.call(@registry_name, {:register, module, opts})
  end

  @doc """
  Returns all decorator integrations that can handle the given URL.
  Results are sorted by priority (highest first).
  """
  def get_decorators_for_url(url) do
    GenServer.call(@registry_name, {:decorators_for_url, url})
  end

  @doc """
  Returns all available importer integrations.
  """
  def get_available_importers do
    GenServer.call(@registry_name, :available_importers)
  end

  @doc """
  Returns all integrations of the specified type.
  """
  def get_integrations_by_type(type) do
    GenServer.call(@registry_name, {:integrations_by_type, type})
  end

  @doc """
  Returns user integrations for a specific workspace and type.
  """
  def get_user_integrations(workspace_id, type \\ nil) do
    GenServer.call(@registry_name, {:user_integrations, workspace_id, type})
  end

  @doc """
  Returns all registered integration modules.
  """
  def list_all_integrations do
    GenServer.call(@registry_name, :list_all)
  end

  @doc """
  Finds an integration module by provider name.
  """
  def get_integration_by_provider(provider) do
    GenServer.call(@registry_name, {:integration_by_provider, provider})
  end

  ## Server Callbacks

  def init(_opts) do
    state = %{
      integrations: %{},  # provider => module
      by_type: %{         # type => [modules]
        decorator: [],
        importer: [],
        syncer: [],
        trigger: []
      }
    }
    
    # Auto-register built-in integrations
    {:ok, new_state} = register_builtin_integrations(state)
    {:ok, new_state}
  end

  def handle_call({:register, module, _opts}, _from, state) do
    case validate_integration_module(module) do
      {:ok, info} ->
        new_state = add_integration_to_state(state, module, info)
        Logger.info("Registered integration: #{info.provider} (#{info.type})")
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        Logger.warning("Failed to register integration #{module}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:decorators_for_url, url}, _from, state) do
    decorators = state.by_type.decorator
    
    matching_decorators = 
      decorators
      |> Enum.filter(&decorator_matches_url?(&1, url))
      |> Enum.sort_by(&get_decorator_priority/1, :desc)
    
    {:reply, matching_decorators, state}
  end

  def handle_call(:available_importers, _from, state) do
    {:reply, state.by_type.importer, state}
  end

  def handle_call({:integrations_by_type, type}, _from, state) do
    integrations = Map.get(state.by_type, type, [])
    {:reply, integrations, state}
  end

  def handle_call({:user_integrations, _workspace_id, _type}, _from, state) do
    # This would typically query the database for UserIntegration records
    # For now, return empty list since we haven't implemented user setup yet
    {:reply, [], state}
  end

  def handle_call(:list_all, _from, state) do
    all_integrations = Map.values(state.integrations)
    {:reply, all_integrations, state}
  end

  def handle_call({:integration_by_provider, provider}, _from, state) do
    integration = Map.get(state.integrations, provider)
    {:reply, integration, state}
  end

  ## Private Functions

  defp register_builtin_integrations(state) do
    Logger.info("Registering built-in integrations...")
    # Ensure the WebLink module is loaded before registration
    Code.ensure_loaded!(LifeOrg.Integrations.Decorators.WebLink)
    
    # Register built-in web link decorator
    case register_integration_internal(state, LifeOrg.Integrations.Decorators.WebLink) do
      {:ok, new_state} -> 
        Logger.info("Successfully registered WebLink decorator")
        {:ok, new_state}
      {:error, reason} -> 
        Logger.error("Failed to register WebLink decorator: #{inspect(reason)}")
        {:ok, state}  # Continue even if registration fails
    end
  end

  defp register_integration_internal(state, module) do
    case validate_integration_module(module) do
      {:ok, info} ->
        new_state = add_integration_to_state(state, module, info)
        Logger.info("Auto-registered integration: #{info.provider} (#{info.type})")
        {:ok, new_state}
      
      {:error, reason} ->
        Logger.warning("Failed to auto-register integration #{module}: #{reason}")
        {:error, reason}
    end
  end

  defp validate_integration_module(module) do
    try do
      # Check if module exists and has required functions
      unless function_exported?(module, :name, 0), do: throw(:missing_name)
      unless function_exported?(module, :provider, 0), do: throw(:missing_provider)
      unless function_exported?(module, :type, 0), do: throw(:missing_type)
      unless function_exported?(module, :capabilities, 0), do: throw(:missing_capabilities)

      info = %{
        name: module.name(),
        provider: module.provider(),
        type: module.type(),
        capabilities: module.capabilities()
      }

      # Validate type
      valid_types = [:decorator, :importer, :syncer, :trigger]
      unless info.type in valid_types do
        throw({:invalid_type, info.type})
      end

      {:ok, info}
    catch
      :missing_name -> {:error, "Module must implement name/0"}
      :missing_provider -> {:error, "Module must implement provider/0"}
      :missing_type -> {:error, "Module must implement type/0"}
      :missing_capabilities -> {:error, "Module must implement capabilities/0"}
      {:invalid_type, type} -> {:error, "Invalid type: #{type}"}
      error -> {:error, "Validation failed: #{inspect(error)}"}
    end
  end

  defp add_integration_to_state(state, module, info) do
    # Add to provider lookup
    new_integrations = Map.put(state.integrations, info.provider, module)
    
    # Add to type-based lookup
    current_type_list = Map.get(state.by_type, info.type, [])
    new_type_list = [module | current_type_list] |> Enum.uniq()
    new_by_type = Map.put(state.by_type, info.type, new_type_list)
    
    %{state | integrations: new_integrations, by_type: new_by_type}
  end

  defp decorator_matches_url?(module, url) do
    try do
      if function_exported?(module, :match_url, 1) do
        module.match_url(url)
      else
        false
      end
    rescue
      _ -> false
    end
  end

  defp get_decorator_priority(module) do
    try do
      if function_exported?(module, :priority, 0) do
        module.priority()
      else
        0
      end
    rescue
      _ -> 0
    end
  end
end