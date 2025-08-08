defmodule LifeOrg.Workspace do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.{JournalEntry, Todo, Conversation, UserIntegration, ImportRun}
  alias LifeOrg.Accounts.User

  schema "workspaces" do
    field :name, :string
    field :description, :string
    field :color, :string, default: "#3B82F6"
    field :is_default, :boolean, default: false

    belongs_to :user, User
    has_many :journal_entries, JournalEntry
    has_many :todos, Todo
    has_many :conversations, Conversation
    has_many :user_integrations, UserIntegration
    has_many :import_runs, ImportRun

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :color, :is_default, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/, message: "must be a valid hex color")
    |> unique_constraint([:user_id, :name], name: :workspaces_user_id_name_index)
    |> maybe_unset_other_defaults()
  end

  defp maybe_unset_other_defaults(changeset) do
    case get_change(changeset, :is_default) do
      true -> changeset
      _ -> changeset
    end
  end
end