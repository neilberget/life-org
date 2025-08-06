defmodule LifeOrg.Repo.Migrations.AddJournalEntryIdToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :journal_entry_id, references(:journal_entries, on_delete: :nilify_all)
    end
  end
end
