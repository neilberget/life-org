defmodule LifeOrg.Projects do
  @moduledoc """
  The Projects context.
  """

  import Ecto.Query, warn: false
  alias LifeOrg.Repo
  alias LifeOrg.Projects.Project

  @doc """
  Returns the list of projects for a workspace.
  """
  def list_projects(workspace_id) do
    Project
    |> where(workspace_id: ^workspace_id)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Gets a single project.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Gets a project by name in a workspace.
  """
  def get_project_by_name(workspace_id, name) do
    Repo.get_by(Project, workspace_id: workspace_id, name: name)
  end

  @doc """
  Creates a project.
  """
  def create_project(attrs \\ %{}) do
    attrs = maybe_fetch_favicon(attrs)
    
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    attrs = maybe_fetch_favicon(attrs, project)
    
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @doc """
  Gets or creates a project by name.
  """
  def get_or_create_project(workspace_id, name) do
    case get_project_by_name(workspace_id, name) do
      nil -> 
        create_project(%{
          name: name,
          workspace_id: workspace_id,
          color: generate_color_for_name(name)
        })
      project -> 
        {:ok, project}
    end
  end

  @doc """
  Gets or creates multiple projects by names.
  """
  def get_or_create_projects(workspace_id, names) when is_list(names) do
    Enum.map(names, fn name ->
      case get_or_create_project(workspace_id, String.trim(name)) do
        {:ok, project} -> project
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp generate_color_for_name(name) do
    colors = [
      "#EF4444", # red
      "#F59E0B", # amber
      "#10B981", # emerald
      "#3B82F6", # blue
      "#8B5CF6", # violet
      "#EC4899", # pink
      "#14B8A6", # teal
      "#F97316", # orange
      "#6366F1", # indigo
      "#84CC16"  # lime
    ]
    
    hash = :erlang.phash2(name, length(colors))
    Enum.at(colors, hash)
  end

  defp maybe_fetch_favicon(attrs, existing_project \\ nil) do
    url = Map.get(attrs, :url) || Map.get(attrs, "url")
    existing_url = if existing_project, do: existing_project.url, else: nil
    
    cond do
      # No URL provided
      is_nil(url) || url == "" ->
        attrs
      
      # URL is being removed
      url == "" && existing_url != nil ->
        Map.put(attrs, :favicon_url, nil)
      
      # URL changed or new URL
      url != existing_url ->
        Task.start(fn ->
          case LifeOrg.FaviconFetcher.fetch_favicon(url) do
            {:ok, favicon_url} ->
              # Update the project asynchronously with the favicon
              if existing_project do
                update_favicon_async(existing_project.id, favicon_url)
              end
            _ ->
              :ok
          end
        end)
        attrs
      
      # URL unchanged
      true ->
        attrs
    end
  end

  defp update_favicon_async(project_id, favicon_url) do
    project = get_project!(project_id)
    
    project
    |> Ecto.Changeset.change(%{favicon_url: favicon_url})
    |> Repo.update()
  end
end