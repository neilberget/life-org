defmodule LifeOrg.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :description, :string
    field :color, :string, default: "#6B7280"
    field :url, :string
    field :favicon_url, :string
    
    belongs_to :workspace, LifeOrg.Workspace
    many_to_many :todos, LifeOrg.Todo, 
      join_through: "todo_projects",
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :color, :url, :favicon_url, :workspace_id])
    |> validate_required([:name, :workspace_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/)
    |> validate_url()
    |> unique_constraint([:workspace_id, :name])
  end

  defp validate_url(changeset) do
    case get_change(changeset, :url) do
      nil -> changeset
      url ->
        if valid_url?(url) do
          changeset
        else
          add_error(changeset, :url, "must be a valid URL")
        end
    end
  end

  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme != nil && uri.host != nil
  end
end