defmodule LifeOrg.ApiTokens do
  import Ecto.Query, warn: false
  alias LifeOrg.Repo
  alias LifeOrg.ApiToken
  alias LifeOrg.Accounts.User

  @rand_size 32

  def generate_token do
    :crypto.strong_rand_bytes(@rand_size)
    |> Base.url_encode64(padding: false)
  end

  def hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.url_encode64(padding: false)
  end

  def create_token(user, attrs \\ %{}) do
    token = generate_token()
    token_hash = hash_token(token)

    attrs = Map.merge(attrs, %{
      "token_hash" => token_hash,
      "user_id" => user.id
    })

    changeset = ApiToken.changeset(%ApiToken{}, attrs)

    case Repo.insert(changeset) do
      {:ok, api_token} ->
        {:ok, api_token, token}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def list_tokens_for_user(user_id) do
    Repo.all(
      from t in ApiToken,
      where: t.user_id == ^user_id,
      order_by: [desc: t.inserted_at]
    )
  end

  def get_token_by_id(id, user_id) do
    Repo.one(
      from t in ApiToken,
      where: t.id == ^id and t.user_id == ^user_id
    )
  end

  def verify_token(token) do
    token_hash = hash_token(token)

    query =
      from t in ApiToken,
      join: u in User,
      on: t.user_id == u.id,
      where: t.token_hash == ^token_hash,
      select: {t, u}

    case Repo.one(query) do
      {api_token, user} ->
        if token_expired?(api_token) do
          {:error, :expired}
        else
          update_last_used(api_token)
          {:ok, user}
        end

      nil ->
        {:error, :invalid}
    end
  end

  defp token_expired?(%ApiToken{expires_at: nil}), do: false
  defp token_expired?(%ApiToken{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp update_last_used(api_token) do
    api_token
    |> Ecto.Changeset.change(last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def delete_token(id, user_id) do
    case get_token_by_id(id, user_id) do
      nil ->
        {:error, :not_found}
      api_token ->
        Repo.delete(api_token)
    end
  end

  def delete_expired_tokens do
    now = DateTime.utc_now()

    Repo.delete_all(
      from t in ApiToken,
      where: not is_nil(t.expires_at) and t.expires_at < ^now
    )
  end
end
