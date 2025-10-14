defmodule LifeOrgWeb.API.V1.FallbackController do
  use LifeOrgWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: LifeOrgWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: LifeOrgWeb.API.V1.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: LifeOrgWeb.ErrorJSON)
    |> render(:"401")
  end
end
