defmodule LifeOrg.Repo.Migrations.CreateIntegrations do
  use Ecto.Migration

  def change do
    create table(:integrations) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :provider, :string, null: false
      add :config, :json
      add :status, :string, default: "active", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:integrations, [:type])
    create index(:integrations, [:provider])
    create index(:integrations, [:status])
  end
end
