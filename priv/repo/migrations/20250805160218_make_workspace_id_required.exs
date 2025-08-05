defmodule LifeOrg.Repo.Migrations.MakeWorkspaceIdRequired do
  use Ecto.Migration

  def change do
    # Make workspace_id NOT NULL for all tables
    execute "ALTER TABLE journal_entries MODIFY workspace_id BIGINT UNSIGNED NOT NULL", 
            "ALTER TABLE journal_entries MODIFY workspace_id BIGINT UNSIGNED NULL"
    
    execute "ALTER TABLE todos MODIFY workspace_id BIGINT UNSIGNED NOT NULL", 
            "ALTER TABLE todos MODIFY workspace_id BIGINT UNSIGNED NULL"
    
    execute "ALTER TABLE conversations MODIFY workspace_id BIGINT UNSIGNED NOT NULL", 
            "ALTER TABLE conversations MODIFY workspace_id BIGINT UNSIGNED NULL"
  end
end
