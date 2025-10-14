defmodule LifeOrg.Repo.Migrations.AddUserIdToWorkspaces do
  use Ecto.Migration

  def up do
    # Check if column already exists
    column_exists = repo().query!("""
      SELECT COUNT(*) as count
      FROM information_schema.columns
      WHERE table_schema = DATABASE()
        AND table_name = 'workspaces'
        AND column_name = 'user_id'
    """).rows |> List.first() |> List.first() > 0

    unless column_exists do
      # Add the column as nullable without foreign key
      alter table(:workspaces) do
        add :user_id, :bigint
      end
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

    # Check if foreign key constraint exists and drop it
    fk_exists = repo().query!("""
      SELECT COUNT(*) as count
      FROM information_schema.table_constraints
      WHERE table_schema = DATABASE()
        AND table_name = 'workspaces'
        AND constraint_name = 'workspaces_user_id_fkey'
        AND constraint_type = 'FOREIGN KEY'
    """).rows |> List.first() |> List.first() > 0

    if fk_exists do
      execute "ALTER TABLE workspaces DROP FOREIGN KEY workspaces_user_id_fkey"
    end

    # Now make the column non-nullable
    alter table(:workspaces) do
      modify :user_id, :bigint, null: false
    end

    # Add the foreign key constraint after the column is properly set up
    alter table(:workspaces) do
      modify :user_id, references(:users, on_delete: :delete_all)
    end

    # Create indexes if they don't exist
    execute "CREATE INDEX IF NOT EXISTS workspaces_user_id_index ON workspaces (user_id)"
    execute "CREATE UNIQUE INDEX IF NOT EXISTS workspaces_user_id_name_index ON workspaces (user_id, name)"
  end

  def down do
    drop unique_index(:workspaces, [:user_id, :name])
    drop index(:workspaces, [:user_id])
    
    alter table(:workspaces) do
      remove :user_id
    end
  end
end