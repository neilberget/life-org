defmodule LifeOrg.Repo.Migrations.RemoveMoodFromJournalEntries do
  use Ecto.Migration

  def change do
    alter table(:journal_entries) do
      remove :mood, :string
    end
  end
end
