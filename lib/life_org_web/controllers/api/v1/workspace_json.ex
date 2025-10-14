defmodule LifeOrgWeb.API.V1.WorkspaceJSON do
  alias LifeOrg.Workspace

  def index(%{workspaces: workspaces}) do
    %{data: for(workspace <- workspaces, do: data(workspace))}
  end

  def show(%{workspace: workspace}) do
    %{data: data(workspace)}
  end

  defp data(%Workspace{} = workspace) do
    %{
      id: workspace.id,
      name: workspace.name,
      description: workspace.description,
      color: workspace.color,
      is_default: workspace.is_default,
      inserted_at: workspace.inserted_at,
      updated_at: workspace.updated_at
    }
  end
end
