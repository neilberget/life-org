defmodule LifeOrg.UserIntegration do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Workspace
  alias LifeOrg.Integration

  schema "user_integrations" do
    field :credentials, :string
    field :settings, :map, default: %{}
    field :last_sync_at, :utc_datetime
    field :status, :string, default: "active"

    belongs_to :workspace, Workspace
    belongs_to :integration, Integration

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(active paused error)

  def changeset(user_integration, attrs) do
    user_integration
    |> cast(attrs, [:workspace_id, :integration_id, :credentials, :settings, :last_sync_at, :status])
    |> validate_required([:workspace_id, :integration_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:integration_id)
    |> unique_constraint([:workspace_id, :integration_id])
  end
end