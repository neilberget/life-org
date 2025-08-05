defmodule LifeOrg.Repo do
  use Ecto.Repo,
    otp_app: :life_org,
    adapter: Ecto.Adapters.MyXQL
end
