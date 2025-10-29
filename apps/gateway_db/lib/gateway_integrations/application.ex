defmodule GatewayIntegrations.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch,
       name: GatewayIntegrations.Finch,
       pools: %{
         # Default pool for all integrations
         :default => [
           size: 10,
           count: 1,
           conn_opts: [
             transport_opts: [
               timeout: 30_000
             ]
           ]
         ],

         # Specific pool for high-volume integrations
         "https://api.stripe.com" => [
           size: 20,
           count: 2,
           conn_opts: [
             transport_opts: [
               timeout: 10_000
             ]
           ]
         ],

         # Specific pool for SendGrid
         "https://api.sendgrid.com" => [
           size: 15,
           count: 1,
           conn_opts: [
             transport_opts: [
               timeout: 10_000
             ]
           ]
         ],

         # Pool for Brazilian APIs (ViaCEP, etc)
         "https://viacep.com.br" => [
           size: 10,
           count: 1,
           conn_opts: [
             transport_opts: [
               timeout: 5_000
             ]
           ]
         ]
       }}
    ]

    opts = [strategy: :one_for_one, name: GatewayIntegrations.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
