defmodule LifeOrg.Repo.Migrations.CreateWorkspaceUsers do
  use Ecto.Migration

  def up do
    create table(:workspace_users) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :is_owner, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_users, [:workspace_id])
    create index(:workspace_users, [:user_id])
    create unique_index(:workspace_users, [:workspace_id, :user_id])

    # Populate workspace_users with existing workspace owners
    execute """
    INSERT INTO workspace_users (workspace_id, user_id, is_owner, inserted_at, updated_at)
    SELECT id, user_id, true, NOW(), NOW()
    FROM workspaces
    """

    # Drop the unique constraint on (user_id, name) since multiple users can now access same workspace
    # We need to drop the foreign key first, then the index, then recreate the foreign key
    execute "ALTER TABLE workspaces DROP FOREIGN KEY workspaces_user_id_fkey"

    # Now drop the unique index if it exists
    execute """
    DROP PROCEDURE IF EXISTS drop_index_if_exists
    """

    execute """
    CREATE PROCEDURE drop_index_if_exists()
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE()
        AND table_name = 'workspaces'
        AND index_name = 'workspaces_user_id_name_index'
      ) THEN
        ALTER TABLE workspaces DROP INDEX workspaces_user_id_name_index;
      END IF;
    END
    """

    execute "CALL drop_index_if_exists()"
    execute "DROP PROCEDURE drop_index_if_exists"

    # Recreate the foreign key without the unique constraint
    execute "ALTER TABLE workspaces ADD CONSTRAINT workspaces_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE"

    # Add a regular (non-unique) index on user_id for performance
    execute "CREATE INDEX workspaces_user_id_index ON workspaces (user_id)"
  end

  def down do
    # Drop the non-unique index
    execute "DROP INDEX workspaces_user_id_index ON workspaces"

    # Drop the foreign key
    execute "ALTER TABLE workspaces DROP FOREIGN KEY workspaces_user_id_fkey"

    # Recreate the unique constraint
    execute "CREATE UNIQUE INDEX workspaces_user_id_name_index ON workspaces (user_id, name)"

    # Recreate the foreign key
    execute "ALTER TABLE workspaces ADD CONSTRAINT workspaces_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE"

    drop table(:workspace_users)
  end
end
