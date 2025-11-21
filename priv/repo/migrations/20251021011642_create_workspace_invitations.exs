defmodule LifeOrg.Repo.Migrations.CreateWorkspaceInvitations do
  use Ecto.Migration

  def change do
    create table(:workspace_invitations) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :invited_by_user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, default: "pending", null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_invitations, [:workspace_id])
    create index(:workspace_invitations, [:email])
    create index(:workspace_invitations, [:status])
  end
end
