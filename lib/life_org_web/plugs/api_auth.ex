defmodule LifeOrgWeb.Plugs.ApiAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias LifeOrg.ApiTokens

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        authenticate_token(conn, token)

      _ ->
        unauthorized(conn)
    end
  end

  defp authenticate_token(conn, token) do
    case ApiTokens.verify_token(token) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      {:error, :expired} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: LifeOrgWeb.ErrorJSON)
        |> render(:"401", message: "Token has expired")
        |> halt()

      {:error, :invalid} ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: LifeOrgWeb.ErrorJSON)
    |> render(:"401", message: "Invalid or missing API token")
    |> halt()
  end
end
