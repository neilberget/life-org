defmodule LifeOrg.Repo.Migrations.AddProjectIdToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :project_id, references(:projects, on_delete: :delete_all)
    end

    create index(:conversations, [:project_id])
  end
end
