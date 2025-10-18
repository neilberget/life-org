defmodule LifeOrg.Repo.Migrations.CreateAttachments do
  use Ecto.Migration

  def change do
    create table(:attachments) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string, null: false
      add :file_size, :integer, null: false
      add :journal_entry_id, references(:journal_entries, on_delete: :delete_all)
      add :todo_id, references(:todos, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:attachments, [:user_id])
    create index(:attachments, [:journal_entry_id])
    create index(:attachments, [:todo_id])
  end
end
