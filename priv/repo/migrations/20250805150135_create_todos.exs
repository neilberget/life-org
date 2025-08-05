defmodule LifeOrg.Repo.Migrations.CreateTodos do
  use Ecto.Migration

  def change do
    create table(:todos) do
      add :title, :string
      add :description, :text
      add :completed, :boolean, default: false, null: false
      add :priority, :string
      add :due_date, :date
      add :ai_generated, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
