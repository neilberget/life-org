defmodule LifeOrg.Repo.Migrations.AddUserIdToWorkspaces do
  use Ecto.Migration

  def up do
    # First add the column as nullable
    alter table(:workspaces) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    # Assign all existing workspaces to the first user (if any exists)
    # or delete them if no users exist
    execute """
    UPDATE workspaces 
    SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1)
    WHERE user_id IS NULL
    """

    # Delete any workspaces that still don't have a user_id (in case no users exist)
    execute "DELETE FROM workspaces WHERE user_id IS NULL"

    # Now make the column non-nullable
    alter table(:workspaces) do
      modify :user_id, :bigint, null: false
    end

    create index(:workspaces, [:user_id])
    create unique_index(:workspaces, [:user_id, :name])
  end

  def down do
    drop unique_index(:workspaces, [:user_id, :name])
    drop index(:workspaces, [:user_id])
    
    alter table(:workspaces) do
      remove :user_id
    end
  end
end