defmodule LifeOrg.LinkMetadata do
  use Ecto.Schema
  import Ecto.Changeset
  alias LifeOrg.Integration

  schema "link_metadata" do
    field :url, :string
    field :metadata, :map, default: %{}
    field :cached_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :integration, Integration

    timestamps(type: :utc_datetime)
  end

  def changeset(link_metadata, attrs) do
    link_metadata
    |> cast(attrs, [:url, :integration_id, :metadata, :cached_at, :expires_at])
    |> validate_required([:url, :metadata, :cached_at, :expires_at])
    |> validate_length(:url, max: 2048)
    |> foreign_key_constraint(:integration_id)
  end

  def expired?(link_metadata) do
    DateTime.utc_now() |> DateTime.after?(link_metadata.expires_at)
  end

  def cache_duration_minutes, do: 15

  def build_expires_at(cached_at \\ nil) do
    base_time = cached_at || DateTime.utc_now()
    DateTime.add(base_time, cache_duration_minutes(), :minute)
  end
end