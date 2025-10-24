import Config

config :gateway_db, GatewayDb.Repo,
  database: "api_gateway_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :gateway_web, GatewayWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "V1MxPR42R97lzi7zpbCDwxcwjUZp2b/jLiQbzyc0R3m+/TgeD+1Vvie79ZO2c9Xc",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:gateway_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:gateway_web, ~w(--watch)]}
  ]

config :gateway_web, GatewayWebWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/gateway_web_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$"
    ]
  ]

config :gateway_web, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
