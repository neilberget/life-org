defmodule LifeOrg.Repo.Migrations.AddUrlAndFaviconToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :url, :string
      add :favicon_url, :string
    end
  end
end
