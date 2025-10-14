defmodule LifeOrg.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_tokens" do
    field :token_hash, :string
    field :name, :string
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, LifeOrg.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :token_hash, :expires_at, :user_id])
    |> validate_required([:name, :token_hash, :user_id])
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
  end
end
