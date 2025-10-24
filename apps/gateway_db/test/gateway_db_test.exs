defmodule GatewayDbTest do
  use ExUnit.Case
  doctest GatewayDb

  test "greets the world" do
    assert GatewayDb.hello() == :world
  end
end
