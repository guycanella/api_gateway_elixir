defmodule GatewayDb.Repo do
  use Ecto.Repo,
    otp_app: :gateway_db,
    adapter: Ecto.Adapters.Postgres
end
