defmodule GatewayDb.IntegrationTest do
  use ExUnit.Case, async: true
  import Ecto.Changeset
  alias GatewayDb.{Integration, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    :ok
  end

  describe "changeset/2 - valid data" do
    test "creates a valid changeset with all required fields" do
      attrs = %{
        name: "stripe",
        type: "payment",
        base_url: "https://api.stripe.com/v1"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "stripe"
      assert get_change(changeset, :type) == "payment"
      assert get_change(changeset, :base_url) == "https://api.stripe.com/v1"
    end

    test "creates a valid changeset with optional fields" do
      attrs = %{
        name: "sendgrid",
        type: "email",
        base_url: "https://api.sendgrid.com/v3",
        is_active: false,
        config: %{timeout_ms: 5000, max_retries: 3}
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :is_active) == false
      assert get_change(changeset, :config) == %{timeout_ms: 5000, max_retries: 3}
    end

    test "sets default values for optional fields" do
      attrs = %{
        name: "test_integration",
        type: "other",
        base_url: "https://api.example.com"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      integration = apply_changes(changeset)

      assert integration.is_active == true
      assert integration.config == %{}
    end

    test "accepts all valid integration types" do
      valid_types = ["payment", "email", "shipping", "notification", "sms", "other"]

      for type <- valid_types do
        attrs = %{
          name: "test_#{type}",
          type: type,
          base_url: "https://api.example.com"
        }

        changeset = Integration.changeset(%Integration{}, attrs)
        assert changeset.valid?, "Type '#{type}' should be valid"
      end
    end

    test "accepts both http and https URLs" do
      attrs_https = %{
        name: "secure_api",
        type: "other",
        base_url: "https://api.example.com"
      }

      changeset_https = Integration.changeset(%Integration{}, attrs_https)
      assert changeset_https.valid?

      attrs_http = %{
        name: "local_api",
        type: "other",
        base_url: "http://localhost:4000"
      }

      changeset_http = Integration.changeset(%Integration{}, attrs_http)
      assert changeset_http.valid?
    end
  end

  describe "changeset/2 - validations" do
    test "requires name field" do
      attrs = %{
        type: "payment",
        base_url: "https://api.stripe.com"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires type field" do
      attrs = %{
        name: "stripe",
        base_url: "https://api.stripe.com"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).type
    end

    test "requires base_url field" do
      attrs = %{
        name: "stripe",
        type: "payment"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).base_url
    end

    test "rejects invalid integration type" do
      attrs = %{
        name: "test",
        type: "invalid_type",
        base_url: "https://api.example.com"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "should be one of the following: payment, email, shipping, notification, sms, other" in errors_on(changeset).type
    end

    test "rejects invalid URL format" do
      attrs = %{
        name: "test",
        type: "payment",
        base_url: "not-a-url"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "should be a valid URL (http:// or https://)" in errors_on(changeset).base_url
    end

    test "rejects URL without protocol" do
      attrs = %{
        name: "test",
        type: "payment",
        base_url: "api.example.com"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "should be a valid URL (http:// or https://)" in errors_on(changeset).base_url
    end

    test "rejects invalid config format (not a map)" do
      attrs = %{
        name: "test",
        type: "payment",
        base_url: "https://api.example.com",
        config: "not_a_map"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).config
    end
  end

  describe "Repo.insert/1" do
    test "successfully inserts a valid integration" do
      attrs = %{
        name: "stripe",
        type: "payment",
        base_url: "https://api.stripe.com/v1"
      }

      changeset = Integration.changeset(%Integration{}, attrs)

      assert {:ok, integration} = Repo.insert(changeset)
      assert integration.id != nil
      assert integration.name == "stripe"
      assert integration.type == "payment"
      assert integration.inserted_at != nil
      assert integration.updated_at != nil
    end

    test "enforces unique constraint on name" do
      attrs = %{
        name: "duplicate_name",
        type: "payment",
        base_url: "https://api.example.com"
      }

      changeset1 = Integration.changeset(%Integration{}, attrs)
      assert {:ok, _integration} = Repo.insert(changeset1)

      changeset2 = Integration.changeset(%Integration{}, attrs)
      assert {:error, changeset} = Repo.insert(changeset2)

      assert "has already been taken" in errors_on(changeset).name
    end

    test "allows same name if first integration is deleted" do
      attrs = %{
        name: "reusable_name",
        type: "payment",
        base_url: "https://api.example.com"
      }

      changeset1 = Integration.changeset(%Integration{}, attrs)
      {:ok, integration1} = Repo.insert(changeset1)
      Repo.delete(integration1)

      changeset2 = Integration.changeset(%Integration{}, attrs)
      assert {:ok, _integration2} = Repo.insert(changeset2)
    end
  end

  describe "Repo.update/1" do
    test "successfully updates an existing integration" do
      {:ok, integration} = create_integration(%{
        name: "original_name",
        type: "payment",
        base_url: "https://api.example.com"
      })

      changeset = Integration.changeset(integration, %{
        name: "updated_name",
        is_active: false
      })

      assert {:ok, updated} = Repo.update(changeset)
      assert updated.name == "updated_name"
      assert updated.is_active == false
      assert updated.type == "payment"
    end

    test "enforces unique constraint on update" do
      {:ok, _integration1} = create_integration(%{
        name: "first",
        type: "payment",
        base_url: "https://api.example.com"
      })

      {:ok, integration2} = create_integration(%{
        name: "second",
        type: "email",
        base_url: "https://api.example.com"
      })

      changeset = Integration.changeset(integration2, %{name: "first"})

      assert {:error, changeset} = Repo.update(changeset)
      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "associations" do
    test "has_many :credentials association is defined" do
      _ = %Integration{}

      assert %Ecto.Association.Has{} = Integration.__schema__(:association, :credentials)
    end

    test "has_many :request_logs association is defined" do
      _ = %Integration{}

      assert %Ecto.Association.Has{} = Integration.__schema__(:association, :request_logs)
    end

    test "has_many :circuit_breaker_states association is defined" do
      _ = %Integration{}

      assert %Ecto.Association.Has{} = Integration.__schema__(:association, :circuit_breaker_states)
    end
  end

  describe "querying integrations" do
    test "can list all integrations" do
      create_integration(%{name: "stripe", type: "payment", base_url: "https://api.stripe.com"})
      create_integration(%{name: "sendgrid", type: "email", base_url: "https://api.sendgrid.com"})

      integrations = Repo.all(Integration)

      assert length(integrations) == 2
    end

    test "can filter by type" do
      create_integration(%{name: "stripe", type: "payment", base_url: "https://api.stripe.com"})
      create_integration(%{name: "sendgrid", type: "email", base_url: "https://api.sendgrid.com"})
      create_integration(%{name: "shipstation", type: "shipping", base_url: "https://api.shipstation.com"})

      import Ecto.Query

      payment_integrations =
        from(i in Integration, where: i.type == "payment")
        |> Repo.all()

      assert length(payment_integrations) == 1
      assert hd(payment_integrations).name == "stripe"
    end

    test "can filter by is_active" do
      create_integration(%{name: "active", type: "payment", base_url: "https://api.active.com", is_active: true})
      create_integration(%{name: "inactive", type: "payment", base_url: "https://api.inactive.com", is_active: false})

      import Ecto.Query

      active_integrations =
        from(i in Integration, where: i.is_active == true)
        |> Repo.all()

      assert length(active_integrations) == 1
      assert hd(active_integrations).name == "active"
    end
  end

  defp create_integration(attrs) do
    %Integration{}
    |> Integration.changeset(attrs)
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
