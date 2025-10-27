defmodule GatewayDb.IntegrationCredentialTest do
  use ExUnit.Case, async: true
  import Ecto.Changeset
  alias GatewayDb.{Integration, IntegrationCredential, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    {:ok, integration} = create_integration(%{
      name: "test_integration",
      type: "payment",
      base_url: "https://api.test.com"
    })

    %{integration: integration}
  end

  describe "changeset/2 - valid data" do
    test "creates a valid changeset with all required fields", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_live_1234567890abcdef"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :integration_id) == integration.id
      assert get_change(changeset, :environment) == "production"
      assert get_change(changeset, :api_key) == "sk_live_1234567890abcdef"
    end

    test "creates a valid changeset with optional fields", %{integration: integration} do
      expires_at = DateTime.utc_now()
        |> DateTime.add(365, :day)
        |> DateTime.truncate(:second)

      attrs = %{
        integration_id: integration.id,
        environment: "staging",
        api_key: "sk_test_abc123",
        api_secret: "whsec_secret123",
        extra_credentials: %{refresh_token: "refresh_xyz"},
        expires_at: expires_at
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :api_secret) == "whsec_secret123"
      assert get_change(changeset, :extra_credentials) == %{refresh_token: "refresh_xyz"}
      assert get_change(changeset, :expires_at) == expires_at
    end

    test "accepts all valid environments", %{integration: integration} do
      valid_environments = ["development", "staging", "production"]

      for env <- valid_environments do
        attrs = %{
          integration_id: integration.id,
          environment: env,
          api_key: "test_key_#{env}"
        }

        changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
        assert changeset.valid?, "Environment '#{env}' should be valid"
      end
    end

    test "sets default value for extra_credentials", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_live_test"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
      credential = apply_changes(changeset)

      assert credential.extra_credentials == %{}
    end
  end

  describe "changeset/2 - validations" do
    test "requires integration_id", %{integration: _integration} do
      attrs = %{
        environment: "production",
        api_key: "sk_live_test"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).integration_id
    end

    test "requires environment", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        api_key: "sk_live_test"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).environment
    end

    test "requires api_key", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).api_key
    end

    test "rejects invalid environment", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "invalid_env",
        api_key: "sk_test_123"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      refute changeset.valid?
      assert "should be one of the following: development, staging, production" in errors_on(changeset).environment
    end

    test "rejects empty api_key", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: ""
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).api_key
    end

    test "rejects expires_at in the past", %{integration: integration} do
      past_date = DateTime.utc_now() |> DateTime.add(-1, :day)

      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_test_123",
        expires_at: past_date
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      refute changeset.valid?
      assert "should be a future date" in errors_on(changeset).expires_at
    end

    test "accepts expires_at in the future", %{integration: integration} do
      future_date = DateTime.utc_now() |> DateTime.add(30, :day)

      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_test_123",
        expires_at: future_date
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      assert changeset.valid?
    end
  end

  describe "Repo.insert/1" do
    test "successfully inserts a valid credential", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_live_test123"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      assert {:ok, credential} = Repo.insert(changeset)
      assert credential.id != nil
      assert credential.integration_id == integration.id
      assert credential.environment == "production"
      assert credential.inserted_at != nil
    end

    test "enforces unique constraint on integration_id + environment", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_live_first"
      }

      changeset1 = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
      assert {:ok, _credential} = Repo.insert(changeset1)

      changeset2 = IntegrationCredential.changeset(%IntegrationCredential{}, %{attrs | api_key: "sk_live_second"})
      assert {:error, changeset} = Repo.insert(changeset2)

      assert "a credential already exists for this integration in this environment" in errors_on(changeset).integration_id
    end

    test "allows same integration with different environments", %{integration: integration} do
      attrs_prod = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_live_prod"
      }

      changeset_prod = IntegrationCredential.changeset(%IntegrationCredential{}, attrs_prod)
      assert {:ok, _cred_prod} = Repo.insert(changeset_prod)

      attrs_staging = %{
        integration_id: integration.id,
        environment: "staging",
        api_key: "sk_test_staging"
      }

      changeset_staging = IntegrationCredential.changeset(%IntegrationCredential{}, attrs_staging)
      assert {:ok, _cred_staging} = Repo.insert(changeset_staging)
    end

    test "enforces foreign key constraint", %{integration: _integration} do
      fake_uuid = Ecto.UUID.generate()

      attrs = %{
        integration_id: fake_uuid,
        environment: "production",
        api_key: "sk_live_test"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert "integration not found" in errors_on(changeset).integration
    end
  end

  describe "encryption with Cloak" do
    test "encrypts api_key before saving to database", %{integration: integration} do
      plain_key = "sk_live_secret_key_123456"

      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: plain_key
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
      {:ok, credential} = Repo.insert(changeset)

      result = Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT api_key FROM integration_credentials WHERE id = $1",
        [Ecto.UUID.dump!(credential.id)]
      )

      [[encrypted_value]] = result.rows

      assert is_binary(encrypted_value)
      refute encrypted_value == plain_key
    end

    test "decrypts api_key when reading from database", %{integration: integration} do
      plain_key = "sk_live_my_secret_key"

      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: plain_key
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
      {:ok, credential} = Repo.insert(changeset)

      fetched = Repo.get!(IntegrationCredential, credential.id)

      assert fetched.api_key == plain_key
    end

    test "encrypts api_secret when provided", %{integration: integration} do
      plain_secret = "whsec_secret_value_xyz"

      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_test_key",
        api_secret: plain_secret
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
      {:ok, credential} = Repo.insert(changeset)

      result = Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT api_secret FROM integration_credentials WHERE id = $1",
        [Ecto.UUID.dump!(credential.id)]
      )

      [[encrypted_secret]] = result.rows

      assert is_binary(encrypted_secret)
      refute encrypted_secret == plain_secret

      fetched = Repo.get!(IntegrationCredential, credential.id)
      assert fetched.api_secret == plain_secret
    end

    test "handles nil api_secret (optional field)", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_test_key"
      }

      changeset = IntegrationCredential.changeset(%IntegrationCredential{}, attrs)
      {:ok, credential} = Repo.insert(changeset)

      fetched = Repo.get!(IntegrationCredential, credential.id)
      assert fetched.api_secret == nil
    end
  end

  describe "update_credentials_changeset/2" do
    test "updates only credential fields", %{integration: integration} do
      {:ok, credential} = create_credential(%{
        integration_id: integration.id,
        environment: "production",
        api_key: "old_key"
      })

      changeset = IntegrationCredential.update_credentials_changeset(credential, %{
        api_key: "new_key",
        api_secret: "new_secret"
      })

      assert changeset.valid?
      assert get_change(changeset, :api_key) == "new_key"
      assert get_change(changeset, :api_secret) == "new_secret"

      refute get_change(changeset, :environment)
      refute get_change(changeset, :integration_id)
    end

    test "validates api_key is not empty in update", %{integration: integration} do
      {:ok, credential} = create_credential(%{
        integration_id: integration.id,
        environment: "production",
        api_key: "old_key"
      })

      changeset = IntegrationCredential.update_credentials_changeset(credential, %{
        api_key: ""
      })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).api_key
    end
  end

  describe "expired?/1" do
    test "returns false when expires_at is nil" do
      credential = %IntegrationCredential{expires_at: nil}

      refute IntegrationCredential.expired?(credential)
    end

    test "returns false when expires_at is in the future" do
      future_date = DateTime.utc_now() |> DateTime.add(30, :day)
      credential = %IntegrationCredential{expires_at: future_date}

      refute IntegrationCredential.expired?(credential)
    end

    test "returns true when expires_at is in the past" do
      past_date = DateTime.utc_now() |> DateTime.add(-1, :day)
      credential = %IntegrationCredential{expires_at: past_date}

      assert IntegrationCredential.expired?(credential)
    end

    test "returns true when expires_at is exactly now (edge case)" do
      now = DateTime.utc_now()
      credential = %IntegrationCredential{expires_at: now}

      assert IntegrationCredential.expired?(credential)
    end
  end

  describe "environment_atom/1" do
    test "converts environment string to atom" do
      credential = %IntegrationCredential{environment: "production"}

      assert IntegrationCredential.environment_atom(credential) == :production
    end

    test "works with all valid environments" do
      assert IntegrationCredential.environment_atom(%IntegrationCredential{environment: "development"}) == :development
      assert IntegrationCredential.environment_atom(%IntegrationCredential{environment: "staging"}) == :staging
      assert IntegrationCredential.environment_atom(%IntegrationCredential{environment: "production"}) == :production
    end
  end

  describe "belongs_to :integration" do
    test "association is defined" do
      assert %Ecto.Association.BelongsTo{} = IntegrationCredential.__schema__(:association, :integration)
    end

    test "can preload integration", %{integration: integration} do
      {:ok, credential} = create_credential(%{
        integration_id: integration.id,
        environment: "production",
        api_key: "sk_test_123"
      })

      credential_with_integration = Repo.preload(credential, :integration)

      assert credential_with_integration.integration.id == integration.id
      assert credential_with_integration.integration.name == "test_integration"
    end
  end

  defp create_integration(attrs) do
    %Integration{}
    |> Integration.changeset(attrs)
    |> Repo.insert()
  end

  defp create_credential(attrs) do
    %IntegrationCredential{}
    |> IntegrationCredential.changeset(attrs)
    |> Repo.insert()
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
