defmodule LifeOrgWeb.HealthController do
  use LifeOrgWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
