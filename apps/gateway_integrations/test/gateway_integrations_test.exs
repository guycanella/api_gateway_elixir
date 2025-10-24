defmodule GatewayIntegrationsTest do
  use ExUnit.Case
  doctest GatewayIntegrations

  test "greets the world" do
    assert GatewayIntegrations.hello() == :world
  end
end
