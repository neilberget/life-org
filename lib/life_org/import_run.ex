defmodule LifeOrg.ImportRun do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Integration
  alias LifeOrg.Workspace

  schema "import_runs" do
    field :type, :string
    field :items_imported, :integer, default: 0
    field :status, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :log, :map, default: %{}

    belongs_to :integration, Integration
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  @valid_types ~w(manual scheduled)
  @valid_statuses ~w(pending running completed failed)

  def changeset(import_run, attrs) do
    import_run
    |> cast(attrs, [:integration_id, :workspace_id, :type, :items_imported, :status, :started_at, :completed_at, :log])
    |> validate_required([:integration_id, :workspace_id, :type, :status, :started_at])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:items_imported, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:integration_id)
    |> foreign_key_constraint(:workspace_id)
  end

  def start_changeset(import_run, attrs \\ %{}) do
    import_run
    |> changeset(attrs)
    |> put_change(:status, "running")
    |> put_change(:started_at, DateTime.utc_now())
  end

  def complete_changeset(import_run, items_imported, log \\ %{}) do
    import_run
    |> change()
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now())
    |> put_change(:items_imported, items_imported)
    |> put_change(:log, log)
  end

  def fail_changeset(import_run, error_log) do
    import_run
    |> change()
    |> put_change(:status, "failed")
    |> put_change(:completed_at, DateTime.utc_now())
    |> put_change(:log, %{error: error_log})
  end
end