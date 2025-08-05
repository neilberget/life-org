defmodule LifeOrg.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LifeOrgWeb.Telemetry,
      LifeOrg.Repo,
      {DNSCluster, query: Application.get_env(:life_org, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LifeOrg.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: LifeOrg.Finch},
      # Start a worker by calling: LifeOrg.Worker.start_link(arg)
      # {LifeOrg.Worker, arg},
      # Start to serve requests, typically the last entry
      LifeOrgWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LifeOrg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LifeOrgWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
