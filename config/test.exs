import Config

config :gateway_db, GatewayDb.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "api_gateway_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :gateway_web, GatewayWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ilGdshAnEqF5jTAK2wJrp+3MmGrKJeV1+QLFYYD2M4B6gcCqxrxraRg6nkR7j1JI",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
