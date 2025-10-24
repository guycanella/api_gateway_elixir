defmodule GatewayWebWeb.PageController do
  use GatewayWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
