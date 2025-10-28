defmodule GatewayDb.IntegrationsTest do
  use GatewayDb.DataCase, async: true

  alias GatewayDb.Integrations

  defp integration_fixture(attrs \\ %{}) do
    default_attrs = %{
      name: "stripe_#{System.unique_integer([:positive])}",
      type: "payment",
      base_url: "https://api.stripe.com",
      is_active: true,
      config: %{"timeout" => 5000}
    }

    {:ok, integration} =
      default_attrs
      |> Map.merge(attrs)
      |> Integrations.create_integration()

    integration
  end

  defp credential_fixture(integration, attrs \\ %{}) do
    default_attrs = %{
      environment: "production",
      api_key: "sk_live_test_key",
      api_secret: "secret_value"
    }

    {:ok, credential} =
      integration
      |> Integrations.add_credential(Map.merge(default_attrs, attrs))

    credential
  end

  describe "list_integrations/0" do
    test "returns all integrations" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      integrations = Integrations.list_integrations()

      assert length(integrations) >= 2
      assert Enum.any?(integrations, fn i -> i.id == integration1.id end)
      assert Enum.any?(integrations, fn i -> i.id == integration2.id end)
    end

    test "returns empty list when no integrations exist" do
      integrations = Integrations.list_integrations()
      assert integrations == []
    end
  end

  describe "list_integrations/1 with filters" do
    test "filters by active status" do
      active = integration_fixture(%{is_active: true})
      _inactive = integration_fixture(%{is_active: false})

      result = Integrations.list_integrations(active: true)

      assert length(result) >= 1
      assert Enum.all?(result, fn i -> i.is_active == true end)
      assert Enum.any?(result, fn i -> i.id == active.id end)
    end

    test "filters by type" do
      payment = integration_fixture(%{type: "payment"})
      _email = integration_fixture(%{type: "email"})

      result = Integrations.list_integrations(type: "payment")

      assert length(result) >= 1
      assert Enum.all?(result, fn i -> i.type == "payment" end)
      assert Enum.any?(result, fn i -> i.id == payment.id end)
    end

    test "filters by multiple criteria" do
      match = integration_fixture(%{type: "payment", is_active: true})
      _no_match1 = integration_fixture(%{type: "payment", is_active: false})
      _no_match2 = integration_fixture(%{type: "email", is_active: true})

      result = Integrations.list_integrations(type: "payment", active: true)

      assert length(result) >= 1
      assert Enum.all?(result, fn i -> i.type == "payment" and i.is_active == true end)
      assert Enum.any?(result, fn i -> i.id == match.id end)
    end

    test "ignores unknown filters" do
      integration = integration_fixture()

      result = Integrations.list_integrations(unknown_filter: "value")

      assert length(result) >= 1
      assert Enum.any?(result, fn i -> i.id == integration.id end)
    end
  end

  describe "get_integration/1" do
    test "returns integration when it exists" do
      integration = integration_fixture()

      assert {:ok, found} = Integrations.get_integration(integration.id)
      assert found.id == integration.id
      assert found.name == integration.name
    end

    test "returns error when integration does not exist" do
      assert {:error, :not_found} = Integrations.get_integration(Ecto.UUID.generate())
    end
  end

  describe "get_integration!/1" do
    test "returns integration when it exists" do
      integration = integration_fixture()

      found = Integrations.get_integration!(integration.id)
      assert found.id == integration.id
    end

    test "raises when integration does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Integrations.get_integration!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_integration_by_name/1" do
    test "returns integration when name exists" do
      integration = integration_fixture(%{name: "unique_stripe"})

      assert {:ok, found} = Integrations.get_integration_by_name("unique_stripe")
      assert found.id == integration.id
      assert found.name == "unique_stripe"
    end

    test "returns error when name does not exist" do
      assert {:error, :not_found} = Integrations.get_integration_by_name("nonexistent")
    end
  end

  describe "create_integration/1" do
    test "creates integration with valid attributes" do
      attrs = %{
        name: "test_integration",
        type: "payment",
        base_url: "https://api.test.com",
        is_active: true,
        config: %{"key" => "value"}
      }

      assert {:ok, integration} = Integrations.create_integration(attrs)
      assert integration.name == "test_integration"
      assert integration.type == "payment"
      assert integration.base_url == "https://api.test.com"
      assert integration.is_active == true
      assert integration.config == %{"key" => "value"}
    end

    test "creates integration with minimal attributes" do
      attrs = %{
        name: "minimal_integration",
        type: "email",
        base_url: "https://api.minimal.com"
      }

      assert {:ok, integration} = Integrations.create_integration(attrs)
      assert integration.name == "minimal_integration"
      assert integration.is_active == true  # default
      assert integration.config == %{}  # default
    end

    test "returns error with invalid attributes" do
      assert {:error, changeset} = Integrations.create_integration(%{})
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).type
      assert "can't be blank" in errors_on(changeset).base_url
    end

    test "returns error with duplicate name" do
      integration_fixture(%{name: "duplicate_name"})

      assert {:error, changeset} =
        Integrations.create_integration(%{
          name: "duplicate_name",
          type: "payment",
          base_url: "https://test.com"
        })

      assert "has already been taken" in errors_on(changeset).name
    end

    test "returns error with invalid URL" do
      assert {:error, changeset} =
        Integrations.create_integration(%{
          name: "test",
          type: "payment",
          base_url: "not-a-url"
        })

      assert "should be a valid URL (http:// or https://)" in errors_on(changeset).base_url
    end
  end

  describe "update_integration/2" do
    test "updates integration with valid attributes" do
      integration = integration_fixture()

      assert {:ok, updated} =
        Integrations.update_integration(integration, %{
          base_url: "https://new-url.com",
          config: %{"new" => "config"}
        })

      assert updated.id == integration.id
      assert updated.base_url == "https://new-url.com"
      assert updated.config == %{"new" => "config"}
    end

    test "returns error with invalid attributes" do
      integration = integration_fixture()

      assert {:error, changeset} =
        Integrations.update_integration(integration, %{name: ""})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "does not update with duplicate name" do
      _existing = integration_fixture(%{name: "existing_name"})
      integration = integration_fixture(%{name: "other_name"})

      assert {:error, changeset} =
        Integrations.update_integration(integration, %{name: "existing_name"})

      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "delete_integration/1" do
    test "deletes the integration" do
      integration = integration_fixture()

      assert {:ok, deleted} = Integrations.delete_integration(integration)
      assert deleted.id == integration.id
      assert {:error, :not_found} = Integrations.get_integration(integration.id)
    end

    test "deletes integration with credentials" do
      integration = integration_fixture()
      _credential = credential_fixture(integration)

      assert {:ok, _} = Integrations.delete_integration(integration)
      assert {:error, :not_found} = Integrations.get_integration(integration.id)
    end
  end

  describe "activate_integration/1" do
    test "activates an inactive integration" do
      integration = integration_fixture(%{is_active: false})

      assert {:ok, activated} = Integrations.activate_integration(integration)
      assert activated.is_active == true
    end

    test "keeps integration active if already active" do
      integration = integration_fixture(%{is_active: true})

      assert {:ok, activated} = Integrations.activate_integration(integration)
      assert activated.is_active == true
    end
  end

  describe "deactivate_integration/1" do
    test "deactivates an active integration" do
      integration = integration_fixture(%{is_active: true})

      assert {:ok, deactivated} = Integrations.deactivate_integration(integration)
      assert deactivated.is_active == false
    end

    test "keeps integration inactive if already inactive" do
      integration = integration_fixture(%{is_active: false})

      assert {:ok, deactivated} = Integrations.deactivate_integration(integration)
      assert deactivated.is_active == false
    end
  end

  describe "add_credential/2" do
    test "adds credential to integration" do
      integration = integration_fixture()

      attrs = %{
        environment: "production",
        api_key: "sk_live_123",
        api_secret: "secret_456"
      }

      assert {:ok, credential} = Integrations.add_credential(integration, attrs)
      assert credential.integration_id == integration.id
      assert credential.environment == "production"
      assert credential.api_key != nil
      assert credential.api_secret != nil
    end

    test "adds credential with extra_credentials" do
      integration = integration_fixture()

      attrs = %{
        environment: "staging",
        api_key: "key",
        api_secret: "secret",
        extra_credentials: %{"refresh_token" => "token_123"}
      }

      assert {:ok, credential} = Integrations.add_credential(integration, attrs)
      assert credential.extra_credentials == %{"refresh_token" => "token_123"}
    end

    test "adds credential with expiration" do
      integration = integration_fixture()
      expires_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

      attrs = %{
        environment: "production",
        api_key: "key",
        api_secret: "secret",
        expires_at: expires_at
      }

      assert {:ok, credential} = Integrations.add_credential(integration, attrs)
      assert DateTime.compare(credential.expires_at, expires_at) == :eq
    end

    test "returns error with invalid attributes" do
      integration = integration_fixture()

      assert {:error, changeset} = Integrations.add_credential(integration, %{})
      assert "can't be blank" in errors_on(changeset).environment
    end

    test "returns error with duplicate environment for same integration" do
      integration = integration_fixture()
      credential_fixture(integration, %{environment: "production"})

      assert {:error, changeset} =
        Integrations.add_credential(integration, %{
          environment: "production",
          api_key: "key",
          api_secret: "secret"
        })

      assert "a credential already exists for this integration in this environment" in
  errors_on(changeset).integration_id
    end

    test "allows same environment for different integrations" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      attrs = %{environment: "production", api_key: "key", api_secret: "secret"}

      assert {:ok, cred1} = Integrations.add_credential(integration1, attrs)
      assert {:ok, cred2} = Integrations.add_credential(integration2, attrs)

      assert cred1.integration_id != cred2.integration_id
      assert cred1.environment == cred2.environment
    end
  end

  describe "update_credential/2" do
    test "updates credential attributes" do
      integration = integration_fixture()
      credential = credential_fixture(integration)

      attrs = %{
        api_key: "new_key",
        extra_credentials: %{"updated" => "value"}
      }

      assert {:ok, updated} = Integrations.update_credential(credential, attrs)
      assert updated.id == credential.id
      assert updated.extra_credentials == %{"updated" => "value"}
    end

    test "updates expiration date" do
      integration = integration_fixture()
      credential = credential_fixture(integration)

      new_expiration = DateTime.utc_now() |> DateTime.add(60, :day) |> DateTime.truncate(:second)

      assert {:ok, updated} =
        Integrations.update_credential(credential, %{expires_at: new_expiration})

      assert DateTime.compare(updated.expires_at, new_expiration) == :eq
    end

    test "returns error with invalid attributes" do
      integration = integration_fixture()
      credential = credential_fixture(integration)

      assert {:error, changeset} =
        Integrations.update_credential(credential, %{environment: ""})

      assert "can't be blank" in errors_on(changeset).environment
    end
  end

  describe "get_credential/2 with integration struct" do
    test "returns credential when it exists" do
      integration = integration_fixture()
      credential = credential_fixture(integration, %{environment: "production"})

      assert {:ok, found} = Integrations.get_credential(integration, "production")
      assert found.id == credential.id
      assert found.environment == "production"
    end

    test "returns error when credential does not exist" do
      integration = integration_fixture()

      assert {:error, :not_found} =
        Integrations.get_credential(integration, "nonexistent")
    end
  end

  describe "get_credential/2 with integration_id" do
    test "returns credential when it exists" do
      integration = integration_fixture()
      credential = credential_fixture(integration, %{environment: "staging"})

      assert {:ok, found} = Integrations.get_credential(integration.id, "staging")
      assert found.id == credential.id
    end

    test "returns error when credential does not exist" do
      integration_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
        Integrations.get_credential(integration_id, "production")
    end
  end

  describe "list_credentials/1 with integration struct" do
    test "returns all credentials for integration" do
      integration = integration_fixture()
      cred1 = credential_fixture(integration, %{environment: "production"})
      cred2 = credential_fixture(integration, %{environment: "staging"})

      credentials = Integrations.list_credentials(integration)

      assert length(credentials) == 2
      assert Enum.any?(credentials, fn c -> c.id == cred1.id end)
      assert Enum.any?(credentials, fn c -> c.id == cred2.id end)
    end

    test "returns empty list when no credentials exist" do
      integration = integration_fixture()

      assert Integrations.list_credentials(integration) == []
    end

    test "does not return credentials from other integrations" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      cred1 = credential_fixture(integration1)
      _cred2 = credential_fixture(integration2)

      credentials = Integrations.list_credentials(integration1)

      assert length(credentials) == 1
      assert Enum.any?(credentials, fn c -> c.id == cred1.id end)
    end
  end

  describe "list_credentials/1 with integration_id" do
    test "returns all credentials for integration" do
      integration = integration_fixture()
      cred1 = credential_fixture(integration, %{environment: "production"})
      cred2 = credential_fixture(integration, %{environment: "development"})

      credentials = Integrations.list_credentials(integration.id)

      assert length(credentials) == 2
      assert Enum.any?(credentials, fn c -> c.id == cred1.id end)
      assert Enum.any?(credentials, fn c -> c.id == cred2.id end)
    end

    test "returns empty list when no credentials exist" do
      integration_id = Ecto.UUID.generate()

      assert Integrations.list_credentials(integration_id) == []
    end
  end

  describe "delete_credential/1" do
    test "deletes the credential" do
      integration = integration_fixture()
      credential = credential_fixture(integration)

      assert {:ok, deleted} = Integrations.delete_credential(credential)
      assert deleted.id == credential.id

      assert {:error, :not_found} =
        Integrations.get_credential(integration, credential.environment)
    end

    test "does not affect other credentials" do
      integration = integration_fixture()
      cred1 = credential_fixture(integration, %{environment: "production"})
      cred2 = credential_fixture(integration, %{environment: "staging"})

      assert {:ok, _} = Integrations.delete_credential(cred1)

      assert {:ok, found} = Integrations.get_credential(integration, "staging")
      assert found.id == cred2.id
    end
  end

  describe "preload_credentials/1" do
    test "loads credentials association" do
      integration = integration_fixture()
      cred1 = credential_fixture(integration, %{environment: "production"})
      cred2 = credential_fixture(integration, %{environment: "staging"})

      {:ok, integration} = Integrations.get_integration(integration.id)
      refute Ecto.assoc_loaded?(integration.credentials)

      integration = Integrations.preload_credentials(integration)
      assert Ecto.assoc_loaded?(integration.credentials)
      assert length(integration.credentials) == 2
      assert Enum.any?(integration.credentials, fn c -> c.id == cred1.id end)
      assert Enum.any?(integration.credentials, fn c -> c.id == cred2.id end)
    end

    test "returns empty list when no credentials exist" do
      integration = integration_fixture()

      {:ok, integration} = Integrations.get_integration(integration.id)
      integration = Integrations.preload_credentials(integration)

      assert integration.credentials == []
    end
  end
end
