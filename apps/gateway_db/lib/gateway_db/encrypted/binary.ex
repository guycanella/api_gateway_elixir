defmodule GatewayDb.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: GatewayDb.Vault
end
