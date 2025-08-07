defmodule LifeOrg.Integration do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.UserIntegration
  alias LifeOrg.LinkMetadata
  alias LifeOrg.ImportRun

  schema "integrations" do
    field :name, :string
    field :type, :string
    field :provider, :string
    field :config, :map, default: %{}
    field :status, :string, default: "active"

    has_many :user_integrations, UserIntegration
    has_many :link_metadata, LinkMetadata
    has_many :import_runs, ImportRun

    timestamps(type: :utc_datetime)
  end

  @valid_types ~w(decorator importer syncer trigger)
  @valid_statuses ~w(active inactive)

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:name, :type, :provider, :config, :status])
    |> validate_required([:name, :type, :provider])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:name, :provider])
  end
end