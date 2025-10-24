defmodule GatewayWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GatewayWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:gateway_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GatewayWeb.PubSub},
      # Start a worker by calling: GatewayWeb.Worker.start_link(arg)
      # {GatewayWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      GatewayWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GatewayWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GatewayWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
