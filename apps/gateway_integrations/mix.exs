defmodule GatewayIntegrations.MixProject do
  use Mix.Project

  def project do
    [
      app: :gateway_integrations,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GatewayIntegrations.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.20.0"},
      {:jason, "~> 1.4"},
      {:tesla, "~> 1.8.0"},
      {:fuse, "~> 2.5"},
      {:retry, "~> 0.19.0"},
      {:gateway_db, in_umbrella: true}
    ]
  end
end
