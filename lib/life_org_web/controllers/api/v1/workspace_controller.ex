defmodule LifeOrgWeb.API.V1.WorkspaceController do
  use LifeOrgWeb, :controller

  alias LifeOrg.WorkspaceService

  action_fallback LifeOrgWeb.API.V1.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_user
    workspaces = WorkspaceService.list_workspaces(user.id)

    render(conn, :index, workspaces: workspaces)
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_workspace(id, user.id) do
      nil ->
        {:error, :not_found}

      workspace ->
        render(conn, :show, workspace: workspace)
    end
  end
end
