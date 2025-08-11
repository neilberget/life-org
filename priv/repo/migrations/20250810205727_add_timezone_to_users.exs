defmodule LifeOrg.Repo.Migrations.AddTimezoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :timezone, :string, default: "America/Chicago", null: false
    end
  end
end
