defmodule LifeOrg.Repo.Migrations.AddEntryDateToJournalEntries do
  use Ecto.Migration

  def change do
    alter table(:journal_entries) do
      add :entry_date, :date
    end
  end
end
