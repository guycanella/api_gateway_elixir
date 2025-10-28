defmodule GatewayDb.Integrations do
  import Ecto.Query, warn: false
  alias GatewayDb.Repo
  alias GatewayDb.{Integration, IntegrationCredential}

  def list_integrations do
    Repo.all(Integration)
  end

  def list_integrations(filters) when is_list(filters) do
    Integration
    |> apply_filters(filters)
    |> Repo.all()
  end

  def get_integration(id) do
    case Repo.get(Integration, id) do
      nil -> {:error, :not_found}
      integration -> {:ok, integration}
    end
  end

  def get_integration!(id) do
    Repo.get!(Integration, id)
  end

  def get_integration_by_name(name) do
    case Repo.get_by(Integration, name: name) do
      nil -> {:error, :not_found}
      integration -> {:ok, integration}
    end
  end

  def create_integration(attrs \\ %{}) do
    %Integration{}
    |> Integration.changeset(attrs)
    |> Repo.insert()
  end

  def update_integration(%Integration{} = integration, attrs) do
    integration
    |> Integration.changeset(attrs)
    |> Repo.update()
  end

  def delete_integration(%Integration{} = integration) do
    Repo.delete(integration)
  end

  def activate_integration(%Integration{} = integration) do
    update_integration(integration, %{is_active: true})
  end

  def deactivate_integration(%Integration{} = integration) do
    update_integration(integration, %{is_active: false})
  end

  def add_credential(%Integration{} = integration, attrs) do
    integration
    |> Ecto.build_assoc(:credentials)
    |> IntegrationCredential.changeset(attrs)
    |> Repo.insert()
  end

  def update_credential(%IntegrationCredential{} = credential, attrs) do
    credential
    |> IntegrationCredential.changeset(attrs)
    |> Repo.update()
  end

  def get_credential(%Integration{} = integration, environment) do
    case Repo.get_by(IntegrationCredential,
                     integration_id: integration.id,
                     environment: environment) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  def get_credential(integration_id, environment) when is_binary(integration_id) do
    case Repo.get_by(IntegrationCredential,
                     integration_id: integration_id,
                     environment: environment) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  def list_credentials(%Integration{} = integration) do
    integration
    |> Ecto.assoc(:credentials)
    |> Repo.all()
  end

  def list_credentials(integration_id) when is_binary(integration_id) do
    IntegrationCredential
    |> where([c], c.integration_id == ^integration_id)
    |> Repo.all()
  end

  def delete_credential(%IntegrationCredential{} = credential) do
    Repo.delete(credential)
  end

  def preload_credentials(%Integration{} = integration) do
    Repo.preload(integration, :credentials)
  end

  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:active, value} | rest]) do
    query
    |> where([i], i.is_active == ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:type, value} | rest]) do
    query
    |> where([i], i.type == ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_unknown | rest]) do
    apply_filters(query, rest)
  end
end
