defmodule GatewayDb.Vault do
  use Cloak.Vault, otp_app: :gateway_db

  @impl GenServer
  def init(config) do
    ciphers = Keyword.get_lazy(config, :ciphers, fn ->
      [
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1",
          key: decode_env!("CLOAK_KEY")
        }
      ]
    end)

    config = Keyword.put(config, :ciphers, ciphers)

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
