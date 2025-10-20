defmodule LifeOrg.Repo.Migrations.AddRecurringTodos do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      # Recurrence configuration
      add :is_recurring, :boolean, default: false
      add :recurrence_type, :string  # "fixed" or "floating"
      add :recurrence_pattern, :map  # Flexible JSON pattern
      add :recurrence_start_date, :date
      add :recurrence_end_date, :date  # nullable

      # Relationship to template
      add :parent_todo_id, references(:todos, on_delete: :delete_all)
      add :occurrence_date, :date  # Which occurrence this represents
      add :is_template, :boolean, default: false  # True for recurring templates

      # Metadata
      add :occurrence_number, :integer  # Sequential occurrence counter
      add :last_generated_occurrence_date, :date  # Track last generated date
    end

    # Indexes for performance
    create index(:todos, [:parent_todo_id])
    create index(:todos, [:is_recurring])
    create index(:todos, [:is_template])
    create index(:todos, [:occurrence_date])
  end
end
