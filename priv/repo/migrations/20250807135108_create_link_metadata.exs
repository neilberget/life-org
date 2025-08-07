defmodule LifeOrg.Repo.Migrations.CreateLinkMetadata do
  use Ecto.Migration

  def change do
    create table(:link_metadata) do
      add :url, :string, size: 2048, null: false
      add :integration_id, references(:integrations, on_delete: :delete_all)
      add :metadata, :json, null: false
      add :cached_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:link_metadata, ["url(255)"], name: :link_metadata_url_index)
    create index(:link_metadata, [:expires_at])
    create index(:link_metadata, [:integration_id])
  end
end
