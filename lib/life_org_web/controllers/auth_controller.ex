defmodule LifeOrgWeb.AuthController do
  @moduledoc """
  Handles OAuth2 authentication flows using Ueberauth.
  
  Provides endpoints for:
  - Initiating OAuth2 flows with various providers
  - Handling OAuth2 callbacks
  - Managing user integration connections
  """

  use LifeOrgWeb, :controller
  
  require Logger
  alias LifeOrg.{UserIntegration, Repo, Integrations.Registry}
  import Ecto.Query

  plug Ueberauth

  @doc """
  Handles successful OAuth2 authentication.
  Creates or updates a UserIntegration record.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider} = params) do
    provider_atom = String.to_atom(provider)
    workspace_id = get_workspace_id(conn, params)
    
    case create_or_update_user_integration(auth, provider_atom, workspace_id) do
      {:ok, _user_integration} ->
        conn
        |> put_flash(:info, "Successfully connected to #{String.capitalize(provider)}!")
        |> redirect(to: redirect_path(conn, params))
      
      {:error, reason} ->
        Logger.error("OAuth2 integration failed for #{provider}: #{inspect(reason)}")
        
        conn
        |> put_flash(:error, "Failed to connect to #{String.capitalize(provider)}. Please try again.")
        |> redirect(to: redirect_path(conn, params))
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, %{"provider" => provider} = params) do
    Logger.warning("OAuth2 authentication failed for #{provider}")
    
    conn
    |> put_flash(:error, "Authentication with #{String.capitalize(provider)} was cancelled or failed.")
    |> redirect(to: redirect_path(conn, params))
  end

  @doc """
  Disconnects a user integration.
  """
  def disconnect(conn, %{"provider" => provider} = params) do
    provider_atom = String.to_atom(provider)
    workspace_id = get_workspace_id(conn, params)
    
    case get_user_integration(provider_atom, workspace_id) do
      nil ->
        conn
        |> put_flash(:info, "No #{String.capitalize(provider)} connection found.")
        |> redirect(to: redirect_path(conn, params))
      
      user_integration ->
        case Repo.delete(user_integration) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Successfully disconnected from #{String.capitalize(provider)}.")
            |> redirect(to: redirect_path(conn, params))
          
          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to disconnect from #{String.capitalize(provider)}.")
            |> redirect(to: redirect_path(conn, params))
        end
    end
  end

  @doc """
  Shows the integration settings page.
  """
  def settings(conn, params) do
    workspace_id = get_workspace_id(conn, params)
    user_integrations = list_user_integrations(workspace_id)
    available_providers = get_available_auth_providers()
    
    render(conn, "settings.html", %{
      user_integrations: user_integrations,
      available_providers: available_providers,
      workspace_id: workspace_id
    })
  end

  ## Private Functions

  defp create_or_update_user_integration(auth, provider, workspace_id) do
    with {:ok, integration_id} <- get_integration_id(provider),
         {:ok, attrs} <- build_integration_attrs(auth, provider, workspace_id, integration_id) do
      
      # Check if integration already exists (global lookup)
      existing_query = from ui in UserIntegration,
                         where: ui.integration_id == ^integration_id and ui.status == "active",
                         limit: 1
      
      case Repo.one(existing_query) do
        nil ->
          %UserIntegration{}
          |> UserIntegration.changeset(attrs)
          |> Repo.insert()
        
        existing ->
          existing
          |> UserIntegration.changeset(attrs)
          |> Repo.update()
      end
    end
  end

  defp build_integration_attrs(auth, provider, workspace_id, integration_id) do
    # Extract credentials from Ueberauth
    credentials = %{
      "access_token" => auth.credentials.token,
      "refresh_token" => auth.credentials.refresh_token,
      "expires_at" => auth.credentials.expires_at,
      "scopes" => auth.credentials.scopes || []
    }
    
    # Extract user info
    user_info = %{
      "external_id" => to_string(auth.uid),
      "username" => auth.info.nickname || auth.info.name,
      "email" => auth.info.email,
      "name" => auth.info.name,
      "avatar_url" => auth.info.image
    }
    
    # Build integration attributes
    attrs = %{
      workspace_id: workspace_id,
      integration_id: integration_id,
      credentials: encrypt_credentials(credentials),
      settings: %{
        "user_info" => user_info,
        "provider" => to_string(provider),
        "connected_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      },
      status: "active"
    }
    
    {:ok, attrs}
  end

  defp get_integration_id(provider) do
    case Registry.get_integration_by_provider(provider) do
      nil ->
        {:error, :integration_not_found}
      
      _module ->
        # For now, use a simple mapping based on provider
        # In the future, this should be stored in the integrations table
        id = case provider do
          :github -> 1
          :asana -> 2
          _ -> nil
        end
        
        if id, do: {:ok, id}, else: {:error, :unknown_provider}
    end
  end

  defp get_user_integration(provider, _workspace_id) do
    # Look for global integration (any workspace) - treating integrations as global for now
    with {:ok, integration_id} <- get_integration_id(provider) do
      query = from ui in UserIntegration,
                where: ui.integration_id == ^integration_id and ui.status == "active",
                limit: 1
      
      Repo.one(query)
    else
      _ -> nil
    end
  end

  defp list_user_integrations(_workspace_id) do
    # Show global integrations (any workspace) - treating integrations as global for now
    query = from ui in UserIntegration,
              where: ui.status == "active",
              order_by: [desc: ui.inserted_at]
    
    Repo.all(query)
    |> Enum.map(&enrich_user_integration/1)
  end

  defp enrich_user_integration(user_integration) do
    # Add provider name and user info
    settings = user_integration.settings || %{}
    provider_name = Map.get(settings, "provider", "unknown")
    user_info = Map.get(settings, "user_info", %{})
    
    Map.merge(user_integration, %{
      provider_name: String.capitalize(provider_name),
      username: Map.get(user_info, "username"),
      avatar_url: Map.get(user_info, "avatar_url")
    })
  end

  defp get_available_auth_providers do
    [
      %{
        name: "GitHub",
        provider: "github",
        description: "Connect your GitHub account to access private repositories",
        icon: "github",
        scopes: ["repo", "user:email"]
      },
      %{
        name: "Asana",
        provider: "asana",
        description: "Connect your Asana account to view task and project details",
        icon: "asana",
        scopes: ["default"]
      }
      # Add more providers here as they're implemented
    ]
  end

  defp get_workspace_id(conn, params) do
    # Try to get workspace_id from params, session, or default to 1
    cond do
      Map.has_key?(params, "workspace_id") ->
        String.to_integer(params["workspace_id"])
      
      get_session(conn, :current_workspace_id) ->
        get_session(conn, :current_workspace_id)
      
      true ->
        # For OAuth, we don't have user context yet, so just use 1 as fallback
        # This will be replaced when proper OAuth user association is implemented
        1
    end
  end

  defp redirect_path(_conn, params) do
    # Redirect back to where the user came from, or default to the main page
    Map.get(params, "redirect_to", "/")
  end

  defp encrypt_credentials(credentials) do
    # TODO: Implement proper encryption using Cloak or similar
    # For now, just store as JSON (NOT SECURE - development only)
    Jason.encode!(credentials)
  end

  @doc """
  Gets a valid access token for a provider and workspace.
  
  This is the main function that other parts of the app will use
  to get authenticated API access.
  """
  def get_access_token(provider, _workspace_id) when is_atom(provider) do
    case get_user_integration(provider, nil) do
      nil ->
        {:error, :not_connected}
      
      user_integration ->
        case decrypt_credentials(user_integration.credentials) do
          {:ok, credentials} ->
            if token_expired?(credentials) do
              # TODO: Implement token refresh
              {:error, :token_expired}
            else
              {:ok, credentials["access_token"]}
            end
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def get_access_token(provider, workspace_id) when is_binary(provider) do
    get_access_token(String.to_atom(provider), workspace_id)
  end

  defp decrypt_credentials(encrypted_credentials) do
    case Jason.decode(encrypted_credentials) do
      {:ok, credentials} -> {:ok, credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  defp token_expired?(credentials) do
    case Map.get(credentials, "expires_at") do
      nil -> false  # Token doesn't expire
      expires_at when is_integer(expires_at) ->
        # Check if token has expired (with 5-minute buffer)
        current_time = System.system_time(:second)
        current_time > (expires_at - 300)
      _ -> false
    end
  end
end