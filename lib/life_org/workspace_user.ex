defmodule LifeOrg.WorkspaceUser do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.{Workspace, Accounts.User}

  schema "workspace_users" do
    field :is_owner, :boolean, default: false

    belongs_to :workspace, Workspace
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(workspace_user, attrs) do
    workspace_user
    |> cast(attrs, [:workspace_id, :user_id, :is_owner])
    |> validate_required([:workspace_id, :user_id])
    |> unique_constraint([:workspace_id, :user_id])
  end
end
