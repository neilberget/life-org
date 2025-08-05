defmodule LifeOrg.Repo.Migrations.AddTagsToTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :tags, :json
    end
  end
end
