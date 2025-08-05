defmodule LifeOrg.Repo.Migrations.SeedDefaultWorkspaces do
  use Ecto.Migration

  def change do
    # Insert default workspaces
    execute """
    INSERT INTO workspaces (name, description, color, is_default, inserted_at, updated_at) VALUES
    ('Personal', 'Personal workspace for journal entries, todos, and conversations', '#3B82F6', true, NOW(), NOW()),
    ('Work', 'Work-related workspace for professional tasks and notes', '#059669', false, NOW(), NOW())
    """, """
    DELETE FROM workspaces WHERE name IN ('Personal', 'Work')
    """

    # Update existing records to use the Personal workspace
    execute """
    UPDATE journal_entries SET workspace_id = (SELECT id FROM workspaces WHERE name = 'Personal' LIMIT 1)
    """, ""

    execute """
    UPDATE todos SET workspace_id = (SELECT id FROM workspaces WHERE name = 'Personal' LIMIT 1)
    """, ""

    execute """
    UPDATE conversations SET workspace_id = (SELECT id FROM workspaces WHERE name = 'Personal' LIMIT 1)
    """, ""
  end
end
