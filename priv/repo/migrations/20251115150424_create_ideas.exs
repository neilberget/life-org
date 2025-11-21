defmodule LifeOrg.Repo.Migrations.CreateIdeas do
  use Ecto.Migration

  def change do
    create table(:ideas) do
      add :title, :string, null: false
      add :description, :text
      add :category, :string
      add :timeframe, :string
      add :tags, :json
      add :status, :string, default: "captured"
      add :position, :integer
      add :embedding, :json
      add :embedding_generated_at, :utc_datetime
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :journal_entry_id, references(:journal_entries, on_delete: :nilify_all)

      timestamps()
    end

    create index(:ideas, [:workspace_id])
    create index(:ideas, [:journal_entry_id])
    create index(:ideas, [:embedding_generated_at])
    create index(:ideas, [:position])
  end
end
