defmodule LifeOrg.Repo.Migrations.AddJournalEntryIdToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :journal_entry_id, references(:journal_entries, on_delete: :delete_all), null: true
    end

    create index(:conversations, [:journal_entry_id])
  end
end
