defmodule LifeOrg.Repo.Migrations.CreateJournalEntries do
  use Ecto.Migration

  def change do
    create table(:journal_entries) do
      add :content, :text
      add :tags, :json
      add :mood, :string

      timestamps(type: :utc_datetime)
    end
  end
end
