defmodule LifeOrg.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    base_children = [
      LifeOrgWeb.Telemetry,
      LifeOrg.Repo,
      {DNSCluster, query: Application.get_env(:life_org, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LifeOrg.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: LifeOrg.Finch},
      # Start MCP server registry and task supervisor
      {Task.Supervisor, name: LifeOrg.MCP.TaskSupervisor},
      # Start integration registry
      LifeOrg.Integrations.Registry,
      # Start link fetcher service
      LifeOrg.LinkFetcher
    ]
    
    # Conditionally add embeddings worker if OpenAI API key is present
    embeddings_worker = if System.get_env("OPENAI_API_KEY") do
      [LifeOrg.EmbeddingsWorker]
    else
      []
    end
    
    children = base_children ++ embeddings_worker ++ [
      # Start a worker by calling: LifeOrg.Worker.start_link(arg)
      # {LifeOrg.Worker, arg},
      # Start to serve requests, typically the last entry
      LifeOrgWeb.Endpoint,
      Hermes.Server.Registry,
      {LifeOrg.MCPServer, transport: :streamable_http}
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
