defmodule GatewayDb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
        GatewayDb.Vault,
        GatewayDb.Repo
      ]

      opts = [strategy: :one_for_one, name: GatewayDb.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
