defmodule LifeOrg.Repo.Migrations.AddEmbeddingsToContent do
  use Ecto.Migration

  def change do
    alter table(:journal_entries) do
      add :embedding, :json
      add :embedding_generated_at, :utc_datetime
    end

    alter table(:todos) do
      add :embedding, :json
      add :embedding_generated_at, :utc_datetime
    end

    create index(:journal_entries, [:embedding_generated_at])
    create index(:todos, [:embedding_generated_at])
  end
end