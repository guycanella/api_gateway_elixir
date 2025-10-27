defmodule GatewayDb.RequestLogTest do
  @moduledoc """
  Testes para o schema RequestLog.

  Testa criação, validações, funções auxiliares (success?, error?, classify_response),
  sanitização de dados sensíveis e queries.
  """
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias GatewayDb.{Integration, RequestLog, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, integration} = create_integration(%{
      name: "test_api",
      type: "payment",
      base_url: "https://api.test.com"
    })

    %{integration: integration}
  end

  describe "changeset/2 - valid data" do
    test "creates a valid changeset with all required fields", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_abc123",
        method: "POST",
        endpoint: "/v1/charges"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :integration_id) == integration.id
      assert get_change(changeset, :request_id) == "req_abc123"
      assert get_change(changeset, :method) == "POST"
      assert get_change(changeset, :endpoint) == "/v1/charges"
    end

    test "creates a valid changeset with complete request/response", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_xyz789",
        method: "GET",
        endpoint: "/v1/customers",
        request_headers: %{"Authorization" => "Bearer token"},
        request_body: %{"limit" => 10},
        response_status: 200,
        response_headers: %{"Content-Type" => "application/json"},
        response_body: %{"data" => []},
        duration_ms: 145
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :response_status) == 200
      assert get_change(changeset, :duration_ms) == 145
    end

    test "accepts all valid HTTP methods", %{integration: integration} do
      valid_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

      for method <- valid_methods do
        attrs = %{
          integration_id: integration.id,
          request_id: "req_#{method}",
          method: method,
          endpoint: "/test"
        }

        changeset = RequestLog.changeset(%RequestLog{}, attrs)
        assert changeset.valid?, "Method '#{method}' should be valid"
      end
    end

    test "sets default values for optional fields", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)
      log = apply_changes(changeset)

      assert log.request_headers == %{}
      assert log.request_body == %{}
      assert log.response_headers == %{}
      assert log.response_body == %{}
    end
  end

  describe "changeset/2 - validations" do
    test "requires integration_id", %{integration: _integration} do
      attrs = %{
        request_id: "req_123",
        method: "POST",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).integration_id
    end

    test "requires request_id", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        method: "POST",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).request_id
    end

    test "requires method", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).method
    end

    test "requires endpoint", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).endpoint
    end

    test "rejects invalid HTTP method", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "INVALID",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "should be one of the following: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS" in errors_on(changeset).method
    end

    test "rejects invalid HTTP status code (too low)", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test",
        response_status: 99
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "should be a valid HTTP status code (100-599)" in errors_on(changeset).response_status
    end

    test "rejects invalid HTTP status code (too high)", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test",
        response_status: 600
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "should be a valid HTTP status code (100-599)" in errors_on(changeset).response_status
    end

    test "accepts valid HTTP status codes", %{integration: integration} do
      valid_statuses = [100, 200, 301, 404, 500, 599]

      for status <- valid_statuses do
        attrs = %{
          integration_id: integration.id,
          request_id: "req_#{status}",
          method: "GET",
          endpoint: "/test",
          response_status: status
        }

        changeset = RequestLog.changeset(%RequestLog{}, attrs)
        assert changeset.valid?, "Status #{status} should be valid"
      end
    end

    test "rejects negative duration_ms", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test",
        duration_ms: -100
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "should be a positive value" in errors_on(changeset).duration_ms
    end

    test "accepts zero duration_ms", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test",
        duration_ms: 0
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      assert changeset.valid?
    end

    test "rejects empty request_id", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "   ",
        method: "GET",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).request_id
    end
  end

  describe "Repo.insert/1" do
    test "successfully inserts a valid log", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_success",
        method: "POST",
        endpoint: "/v1/payments",
        response_status: 201,
        duration_ms: 234
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      assert {:ok, log} = Repo.insert(changeset)
      assert log.id != nil
      assert log.inserted_at != nil
      refute Map.has_key?(log, :updated_at)
    end

    test "enforces foreign key constraint", %{integration: _integration} do
      fake_uuid = Ecto.UUID.generate()

      attrs = %{
        integration_id: fake_uuid,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test"
      }

      changeset = RequestLog.changeset(%RequestLog{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert "integration not found" in errors_on(changeset).integration
    end

    test "allows duplicate request_ids (no unique constraint)", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "duplicate_req_id",
        method: "GET",
        endpoint: "/test"
      }

      changeset1 = RequestLog.changeset(%RequestLog{}, attrs)
      assert {:ok, _log1} = Repo.insert(changeset1)

      changeset2 = RequestLog.changeset(%RequestLog{}, attrs)
      assert {:ok, _log2} = Repo.insert(changeset2)
    end
  end

  describe "error_changeset/2" do
    test "creates a valid error log", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_error",
        method: "POST",
        endpoint: "/v1/charges",
        error_message: "Connection timeout after 5000ms",
        duration_ms: 5000
      }

      changeset = RequestLog.error_changeset(%RequestLog{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :error_message) == "Connection timeout after 5000ms"
    end

    test "requires error_message", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test"
      }

      changeset = RequestLog.error_changeset(%RequestLog{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).error_message
    end
  end

  describe "success?/1" do
    test "returns true for 2xx status codes" do
      success_statuses = [200, 201, 202, 204, 299]

      for status <- success_statuses do
        log = %RequestLog{response_status: status}
        assert RequestLog.success?(log), "Status #{status} should be success"
      end
    end

    test "returns false for non-2xx status codes" do
      non_success_statuses = [199, 300, 400, 404, 500]

      for status <- non_success_statuses do
        log = %RequestLog{response_status: status}
        refute RequestLog.success?(log), "Status #{status} should not be success"
      end
    end

    test "returns false when response_status is nil" do
      log = %RequestLog{response_status: nil}
      refute RequestLog.success?(log)
    end
  end

  describe "error?/1" do
    test "returns true for 4xx status codes" do
      client_errors = [400, 401, 403, 404, 422, 499]

      for status <- client_errors do
        log = %RequestLog{response_status: status}
        assert RequestLog.error?(log), "Status #{status} should be error"
      end
    end

    test "returns true for 5xx status codes" do
      server_errors = [500, 502, 503, 504, 599]

      for status <- server_errors do
        log = %RequestLog{response_status: status}
        assert RequestLog.error?(log), "Status #{status} should be error"
      end
    end

    test "returns true when error_message is present" do
      log = %RequestLog{error_message: "Connection failed"}
      assert RequestLog.error?(log)
    end

    test "returns false for 2xx status codes" do
      log = %RequestLog{response_status: 200}
      refute RequestLog.error?(log)
    end

    test "returns false when no status and no error_message" do
      log = %RequestLog{response_status: nil, error_message: nil}
      refute RequestLog.error?(log)
    end
  end

  describe "classify_response/1" do
    test "classifies 2xx as :success" do
      log = %RequestLog{response_status: 200}
      assert RequestLog.classify_response(log) == :success
    end

    test "classifies 3xx as :redirect" do
      log = %RequestLog{response_status: 301}
      assert RequestLog.classify_response(log) == :redirect
    end

    test "classifies 4xx as :client_error" do
      log = %RequestLog{response_status: 404}
      assert RequestLog.classify_response(log) == :client_error
    end

    test "classifies 5xx as :server_error" do
      log = %RequestLog{response_status: 500}
      assert RequestLog.classify_response(log) == :server_error
    end

    test "classifies with error_message but no status as :error" do
      log = %RequestLog{response_status: nil, error_message: "Timeout"}
      assert RequestLog.classify_response(log) == :error
    end

    test "classifies with no status and no error as :unknown" do
      log = %RequestLog{response_status: nil, error_message: nil}
      assert RequestLog.classify_response(log) == :unknown
    end
  end

  describe "sanitize_sensitive_data/1" do
    test "masks Authorization header" do
      headers = %{"Authorization" => "Bearer sk_live_1234567890abcdef"}

      sanitized = RequestLog.sanitize_sensitive_data(headers)

      assert sanitized["Authorization"] == "Bear***"
    end

    test "masks password field" do
      data = %{"password" => "super_secret_password"}

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["password"] == "supe***"
    end

    test "masks api_key field" do
      data = %{"api_key" => "sk_live_abcdef123456"}

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["api_key"] == "sk_l***"
    end

    test "masks secret field" do
      data = %{"secret" => "my_secret_value"}

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["secret"] == "my_s***"
    end

    test "masks token field" do
      data = %{"refresh_token" => "refresh_abc123xyz"}

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["refresh_token"] == "refr***"
    end

    test "preserves non-sensitive fields" do
      data = %{
        "Content-Type" => "application/json",
        "User-Agent" => "MyApp/1.0",
        "Accept" => "*/*"
      }

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized == data
    end

    test "works with mixed sensitive and non-sensitive fields" do
      data = %{
        "Authorization" => "Bearer secret_token",
        "Content-Type" => "application/json",
        "api_key" => "sk_test_123"
      }

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["Authorization"] == "Bear***"
      assert sanitized["api_key"] == "sk_t***"
      assert sanitized["Content-Type"] == "application/json"
    end

    test "handles case-insensitive matching" do
      data = %{
        "AUTHORIZATION" => "Bearer token",
        "Password" => "secret",
        "Api_Key" => "key123"
      }

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["AUTHORIZATION"] == "Bear***"
      assert sanitized["Password"] == "secr***"
      assert sanitized["Api_Key"] == "key1***"
    end

    test "handles very short values" do
      data = %{"password" => "ab"}

      sanitized = RequestLog.sanitize_sensitive_data(data)

      assert sanitized["password"] == "***"
    end

    test "returns non-map data unchanged" do
      assert RequestLog.sanitize_sensitive_data("string") == "string"
      assert RequestLog.sanitize_sensitive_data(123) == 123
      assert RequestLog.sanitize_sensitive_data(nil) == nil
    end
  end

  describe "belongs_to :integration" do
    test "association is defined" do
      assert %Ecto.Association.BelongsTo{} = RequestLog.__schema__(:association, :integration)
    end

    test "can preload integration", %{integration: integration} do
      {:ok, log} = create_log(%{
        integration_id: integration.id,
        request_id: "req_123",
        method: "GET",
        endpoint: "/test"
      })

      log_with_integration = Repo.preload(log, :integration)

      assert log_with_integration.integration.id == integration.id
      assert log_with_integration.integration.name == "test_api"
    end
  end

  describe "querying logs" do
    test "can filter by integration_id", %{integration: integration} do
      {:ok, other_integration} = create_integration(%{
        name: "other_api",
        type: "email",
        base_url: "https://api.other.com"
      })

      create_log(%{integration_id: integration.id, request_id: "req_1", method: "GET", endpoint: "/a"})
      create_log(%{integration_id: integration.id, request_id: "req_2", method: "GET", endpoint: "/b"})
      create_log(%{integration_id: other_integration.id, request_id: "req_3", method: "GET", endpoint: "/c"})

      import Ecto.Query

      logs =
        from(l in RequestLog, where: l.integration_id == ^integration.id)
        |> Repo.all()

      assert length(logs) == 2
    end

    test "can filter by response_status", %{integration: integration} do
      create_log(%{integration_id: integration.id, request_id: "req_1", method: "GET", endpoint: "/a", response_status: 200})
      create_log(%{integration_id: integration.id, request_id: "req_2", method: "GET", endpoint: "/b", response_status: 404})
      create_log(%{integration_id: integration.id, request_id: "req_3", method: "GET", endpoint: "/c", response_status: 500})

      import Ecto.Query

      error_logs =
        from(l in RequestLog, where: l.response_status >= 400)
        |> Repo.all()

      assert length(error_logs) == 2
    end

    test "can order by inserted_at", %{integration: integration} do
      create_log(%{integration_id: integration.id, request_id: "req_1", method: "GET", endpoint: "/a"})
      :timer.sleep(1000)
      create_log(%{integration_id: integration.id, request_id: "req_2", method: "GET", endpoint: "/b"})

      import Ecto.Query

      logs =
        from(l in RequestLog, order_by: [desc: l.inserted_at])
        |> Repo.all()

      assert hd(logs).request_id == "req_2"
    end
  end

  defp create_integration(attrs) do
    %Integration{}
    |> Integration.changeset(attrs)
    |> Repo.insert()
  end

  defp create_log(attrs) do
    %RequestLog{}
    |> RequestLog.changeset(attrs)
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
