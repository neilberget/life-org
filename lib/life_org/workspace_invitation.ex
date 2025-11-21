defmodule LifeOrg.WorkspaceInvitation do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.{Workspace, Accounts.User}

  schema "workspace_invitations" do
    field :email, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :invited_by, User, foreign_key: :invited_by_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :status, :expires_at, :workspace_id, :invited_by_user_id])
    |> validate_required([:email, :workspace_id, :invited_by_user_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_inclusion(:status, ["pending", "accepted", "declined"])
  end

  def create_changeset(attrs) do
    # Set expiration to 30 days from now
    expires_at = DateTime.utc_now()
                 |> DateTime.add(30, :day)
                 |> DateTime.truncate(:second)

    attrs = Map.put(attrs, :expires_at, expires_at)

    %__MODULE__{}
    |> changeset(attrs)
  end
end
