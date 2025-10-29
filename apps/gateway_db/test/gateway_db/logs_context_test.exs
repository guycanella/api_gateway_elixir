defmodule GatewayDb.LogsTest do
  use GatewayDb.DataCase, async: true

  alias GatewayDb.{Logs, Integrations}

  defp integration_fixture do
    {:ok, integration} =
      Integrations.create_integration(%{
        name: "test_integration_#{System.unique_integer([:positive])}",
        type: "payment",
        base_url: "https://api.test.com"
      })

    integration
  end

  defp log_fixture(integration, attrs \\ %{}) do
    default_attrs = %{
      integration_id: integration.id,
      request_id: "req_#{System.unique_integer([:positive])}",
      method: "POST",
      endpoint: "/v1/charges",
      request_headers: %{"Content-Type" => "application/json"},
      request_body: %{"amount" => 1000},
      response_status: 200,
      response_headers: %{"Content-Type" => "application/json"},
      response_body: %{"id" => "ch_123"},
      duration_ms: 150
    }

    {:ok, log} =
      default_attrs
      |> Map.merge(attrs)
      |> Logs.create_log()

    log
  end

  describe "create_log/1" do
    test "creates log with valid attributes" do
      integration = integration_fixture()

      attrs = %{
        integration_id: integration.id,
        request_id: "req_unique_123",
        method: "POST",
        endpoint: "/v1/charges",
        request_headers: %{"Authorization" => "Bearer token"},
        request_body: %{"amount" => 1000, "currency" => "usd"},
        response_status: 201,
        response_headers: %{"Content-Type" => "application/json"},
        response_body: %{"id" => "ch_123", "status" => "succeeded"},
        duration_ms: 234
      }

      assert {:ok, log} = Logs.create_log(attrs)
      assert log.integration_id == integration.id
      assert log.request_id == "req_unique_123"
      assert log.method == "POST"
      assert log.endpoint == "/v1/charges"
      assert log.response_status == 201
      assert log.duration_ms == 234
      assert log.request_body == %{"amount" => 1000, "currency" => "usd"}
      assert log.response_body == %{"id" => "ch_123", "status" => "succeeded"}
    end

    test "creates log with minimal attributes" do
      integration = integration_fixture()

      attrs = %{
        integration_id: integration.id,
        request_id: "req_minimal",
        method: "GET",
        endpoint: "/v1/balance"
      }

      assert {:ok, log} = Logs.create_log(attrs)
      assert log.integration_id == integration.id
      assert log.request_id == "req_minimal"
      assert log.method == "GET"
      assert log.endpoint == "/v1/balance"
      assert log.request_headers == %{}
      assert log.response_headers == %{}
    end

    test "creates log with error message" do
      integration = integration_fixture()

      attrs = %{
        integration_id: integration.id,
        request_id: "req_error",
        method: "POST",
        endpoint: "/v1/charges",
        response_status: 500,
        error_message: "Connection timeout",
        duration_ms: 5000
      }

      assert {:ok, log} = Logs.create_log(attrs)
      assert log.error_message == "Connection timeout"
      assert log.response_status == 500
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = Logs.create_log(%{})
      assert "can't be blank" in errors_on(changeset).integration_id
      assert "can't be blank" in errors_on(changeset).request_id
      assert "can't be blank" in errors_on(changeset).method
      assert "can't be blank" in errors_on(changeset).endpoint
    end

    test "returns error with invalid method" do
      integration = integration_fixture()

      assert {:error, changeset} =
        Logs.create_log(%{
          integration_id: integration.id,
          request_id: "req_123",
          method: "INVALID",
          endpoint: "/test"
        })

      assert "should be one of the following: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS" in
        errors_on(changeset).method
    end
  end

  describe "get_log/1" do
    test "returns log when it exists" do
      integration = integration_fixture()
      log = log_fixture(integration)

      assert {:ok, found} = Logs.get_log(log.id)
      assert found.id == log.id
      assert found.request_id == log.request_id
    end

    test "returns error when log does not exist" do
      assert {:error, :not_found} = Logs.get_log(Ecto.UUID.generate())
    end
  end

  describe "get_log!/1" do
    test "returns log when it exists" do
      integration = integration_fixture()
      log = log_fixture(integration)

      found = Logs.get_log!(log.id)
      assert found.id == log.id
    end

    test "raises when log does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Logs.get_log!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_log_by_request_id/1" do
    test "returns log when request_id exists" do
      integration = integration_fixture()
      log = log_fixture(integration, %{request_id: "req_unique_find"})

      assert {:ok, found} = Logs.get_log_by_request_id("req_unique_find")
      assert found.id == log.id
      assert found.request_id == "req_unique_find"
    end

    test "returns error when request_id does not exist" do
      assert {:error, :not_found} = Logs.get_log_by_request_id("nonexistent")
    end
  end

  describe "list_logs/0" do
    test "returns all logs ordered by inserted_at desc" do
      integration = integration_fixture()
      log1 = log_fixture(integration)
      Process.sleep(10)  # Ensure different timestamps
      log2 = log_fixture(integration)

      logs = Logs.list_logs()

      assert length(logs) >= 2
      # Verify logs are present
      assert Enum.any?(logs, fn l -> l.id == log1.id end)
      assert Enum.any?(logs, fn l -> l.id == log2.id end)
    end

    test "returns empty list when no logs exist" do
      assert Logs.list_logs() == []
    end
  end

  describe "list_logs/1 with integration_id filter" do
    test "filters by integration_id" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      log1 = log_fixture(integration1)
      _log2 = log_fixture(integration2)

      result = Logs.list_logs(integration_id: integration1.id)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.integration_id == integration1.id end)
      assert Enum.any?(result, fn l -> l.id == log1.id end)
    end
  end

  describe "list_logs/1 with method filter" do
    test "filters by HTTP method" do
      integration = integration_fixture()

      post_log = log_fixture(integration, %{method: "POST"})
      _get_log = log_fixture(integration, %{method: "GET"})

      result = Logs.list_logs(method: "POST")

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.method == "POST" end)
      assert Enum.any?(result, fn l -> l.id == post_log.id end)
    end
  end

  describe "list_logs/1 with status filter" do
    test "filters by exact status code" do
      integration = integration_fixture()

      success = log_fixture(integration, %{response_status: 200})
      _error = log_fixture(integration, %{response_status: 500})

      result = Logs.list_logs(status: 200)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.response_status == 200 end)
      assert Enum.any?(result, fn l -> l.id == success.id end)
    end
  end

  describe "list_logs/1 with status_range filter" do
    test "filters by status code range" do
      integration = integration_fixture()

      success1 = log_fixture(integration, %{response_status: 200})
      success2 = log_fixture(integration, %{response_status: 201})
      _error = log_fixture(integration, %{response_status: 500})

      result = Logs.list_logs(status_range: 200..299)

      assert length(result) >= 2
      assert Enum.all?(result, fn l -> l.response_status >= 200 and l.response_status <= 299 end)
      assert Enum.any?(result, fn l -> l.id == success1.id end)
      assert Enum.any?(result, fn l -> l.id == success2.id end)
    end
  end

  describe "list_logs/1 with duration filters" do
    test "filters by min_duration" do
      integration = integration_fixture()

      slow = log_fixture(integration, %{duration_ms: 1500})
      _fast = log_fixture(integration, %{duration_ms: 100})

      result = Logs.list_logs(min_duration: 1000)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.duration_ms >= 1000 end)
      assert Enum.any?(result, fn l -> l.id == slow.id end)
    end

    test "filters by max_duration" do
      integration = integration_fixture()

      fast = log_fixture(integration, %{duration_ms: 50})
      _slow = log_fixture(integration, %{duration_ms: 2000})

      result = Logs.list_logs(max_duration: 100)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.duration_ms <= 100 end)
      assert Enum.any?(result, fn l -> l.id == fast.id end)
    end

    test "filters by duration range" do
      integration = integration_fixture()

      medium = log_fixture(integration, %{duration_ms: 500})
      _too_fast = log_fixture(integration, %{duration_ms: 50})
      _too_slow = log_fixture(integration, %{duration_ms: 2000})

      result = Logs.list_logs(min_duration: 200, max_duration: 800)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.duration_ms >= 200 and l.duration_ms <= 800 end)
      assert Enum.any?(result, fn l -> l.id == medium.id end)
    end
  end

  describe "list_logs/1 with time period filters" do
    test "filters by from datetime" do
      integration = integration_fixture()

      log = log_fixture(integration)

      future = DateTime.utc_now() |> DateTime.add(1, :hour)
      result = Logs.list_logs(from: future)

      refute Enum.any?(result, fn l -> l.id == log.id end)
    end

    test "filters by to datetime" do
      integration = integration_fixture()

      now = DateTime.utc_now()
      future = DateTime.add(now, 1, :hour)

      log = log_fixture(integration)

      result = Logs.list_logs(to: future)

      assert Enum.any?(result, fn l -> l.id == log.id end)
    end
  end

  describe "list_logs/1 with has_error filter" do
    test "filters logs with errors" do
      integration = integration_fixture()

      error_log = log_fixture(integration, %{error_message: "Timeout error"})
      _success_log = log_fixture(integration, %{error_message: nil})

      result = Logs.list_logs(has_error: true)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.error_message != nil end)
      assert Enum.any?(result, fn l -> l.id == error_log.id end)
    end

    test "filters logs without errors" do
      integration = integration_fixture()

      success_log = log_fixture(integration, %{error_message: nil})
      _error_log = log_fixture(integration, %{error_message: "Error"})

      result = Logs.list_logs(has_error: false)

      assert length(result) >= 1
      assert Enum.all?(result, fn l -> l.error_message == nil end)
      assert Enum.any?(result, fn l -> l.id == success_log.id end)
    end
  end

  describe "list_logs/1 with multiple filters" do
    test "combines multiple filters" do
      integration = integration_fixture()

      match = log_fixture(integration, %{
        method: "POST",
        response_status: 200,
        duration_ms: 500
      })

      _no_match1 = log_fixture(integration, %{method: "GET", response_status: 200})
      _no_match2 = log_fixture(integration, %{method: "POST", response_status: 500})

      result = Logs.list_logs(
        integration_id: integration.id,
        method: "POST",
        status_range: 200..299,
        max_duration: 600
      )

      assert length(result) >= 1
      assert Enum.any?(result, fn l -> l.id == match.id end)
    end
  end

  describe "list_logs/1 with limit option" do
    test "limits number of results" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ -> log_fixture(integration) end)

      result = Logs.list_logs(limit: 3)

      assert length(result) == 3
    end

    test "uses default limit of 100" do
      integration = integration_fixture()
      log_fixture(integration)

      result = Logs.list_logs([])

      assert is_list(result)
    end
  end

  describe "list_logs/1 with offset option" do
    test "skips specified number of records" do
      integration = integration_fixture()

      _logs = Enum.map(1..5, fn i ->
        Process.sleep(5)
        log_fixture(integration, %{request_id: "req_#{i}"})
      end)

      all_logs = Logs.list_logs(integration_id: integration.id, limit: 10)

      offset_logs = Logs.list_logs(integration_id: integration.id, offset: 2, limit: 10)

      assert length(offset_logs) == length(all_logs) - 2
    end
  end

  describe "list_logs/1 with order options" do
    test "orders by duration_ms ascending" do
      integration = integration_fixture()

      _slow = log_fixture(integration, %{duration_ms: 500})
      fast = log_fixture(integration, %{duration_ms: 100})

      result = Logs.list_logs(
        integration_id: integration.id,
        order_by: :duration_ms,
        order: :asc
      )

      assert List.first(result).id == fast.id
    end

    test "orders by duration_ms descending" do
      integration = integration_fixture()

      slow = log_fixture(integration, %{duration_ms: 500})
      _fast = log_fixture(integration, %{duration_ms: 100})

      result = Logs.list_logs(
        integration_id: integration.id,
        order_by: :duration_ms,
        order: :desc
      )

      assert List.first(result).id == slow.id
    end
  end

  describe "list_logs_by_integration/2" do
    test "lists logs for specific integration" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      log1 = log_fixture(integration1)
      _log2 = log_fixture(integration2)

      result = Logs.list_logs_by_integration(integration1.id)

      assert Enum.all?(result, fn l -> l.integration_id == integration1.id end)
      assert Enum.any?(result, fn l -> l.id == log1.id end)
    end

    test "accepts additional options" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ -> log_fixture(integration) end)

      result = Logs.list_logs_by_integration(integration.id, limit: 2)

      assert length(result) == 2
    end
  end

  describe "list_recent_errors/1" do
    test "lists only logs with errors" do
      integration = integration_fixture()

      error_log = log_fixture(integration, %{error_message: "Error occurred"})
      _success_log = log_fixture(integration, %{error_message: nil})

      result = Logs.list_recent_errors()

      assert Enum.all?(result, fn l -> l.error_message != nil end)
      assert Enum.any?(result, fn l -> l.id == error_log.id end)
    end

    test "accepts limit option" do
      integration = integration_fixture()

      Enum.each(1..5, fn i ->
        log_fixture(integration, %{error_message: "Error #{i}"})
      end)

      result = Logs.list_recent_errors(limit: 2)

      assert length(result) == 2
    end
  end

  describe "list_slow_requests/2" do
    test "lists requests above threshold" do
      integration = integration_fixture()

      slow1 = log_fixture(integration, %{duration_ms: 1500})
      slow2 = log_fixture(integration, %{duration_ms: 2000})
      _fast = log_fixture(integration, %{duration_ms: 100})

      result = Logs.list_slow_requests(1000)

      assert length(result) >= 2
      assert Enum.all?(result, fn l -> l.duration_ms >= 1000 end)
      assert Enum.any?(result, fn l -> l.id == slow1.id end)
      assert Enum.any?(result, fn l -> l.id == slow2.id end)
    end

    test "accepts additional options" do
      integration = integration_fixture()

      Enum.each(1..5, fn i ->
        log_fixture(integration, %{duration_ms: 1000 + (i * 100)})
      end)

      result = Logs.list_slow_requests(1000, limit: 2)

      assert length(result) == 2
    end
  end

  describe "list_logs_by_period/3" do
    test "lists logs within time range" do
      integration = integration_fixture()

      now = DateTime.utc_now()
      start = DateTime.add(now, -1, :hour)
      finish = DateTime.add(now, 1, :hour)

      log = log_fixture(integration)

      result = Logs.list_logs_by_period(start, finish)

      assert Enum.any?(result, fn l -> l.id == log.id end)
    end
  end

  describe "count_logs/1" do
    test "counts all logs without filters" do
      integration = integration_fixture()

      log_fixture(integration)
      log_fixture(integration)

      count = Logs.count_logs()

      assert count >= 2
    end

    test "counts logs with filters" do
      integration = integration_fixture()

      log_fixture(integration, %{method: "POST"})
      log_fixture(integration, %{method: "POST"})
      log_fixture(integration, %{method: "GET"})

      count = Logs.count_logs(method: "POST")

      assert count >= 2
    end
  end

  describe "average_duration/1" do
    test "calculates average duration" do
      integration = integration_fixture()

      log_fixture(integration, %{duration_ms: 100})
      log_fixture(integration, %{duration_ms: 200})
      log_fixture(integration, %{duration_ms: 300})

      avg = Logs.average_duration(integration_id: integration.id)

      assert avg == 200.0
    end

    test "returns 0.0 when no logs match" do
      avg = Logs.average_duration(integration_id: Ecto.UUID.generate())

      assert avg == 0.0
    end
  end

  describe "error_rate/1" do
    test "calculates error percentage" do
      integration = integration_fixture()

      Enum.each(1..2, fn _ -> log_fixture(integration, %{error_message: "Error"}) end)
      Enum.each(1..8, fn _ -> log_fixture(integration, %{error_message: nil}) end)

      rate = Logs.error_rate(integration_id: integration.id)

      assert rate == 20.0
    end

    test "returns 0.0 when no logs exist" do
      rate = Logs.error_rate(integration_id: Ecto.UUID.generate())

      assert rate == 0.0
    end

    test "returns 100.0 when all logs have errors" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ -> log_fixture(integration, %{error_message: "Error"}) end)

      rate = Logs.error_rate(integration_id: integration.id)

      assert rate == 100.0
    end
  end

  describe "count_by_status/1" do
    test "groups logs by status code" do
      integration = integration_fixture()

      log_fixture(integration, %{response_status: 200})
      log_fixture(integration, %{response_status: 200})
      log_fixture(integration, %{response_status: 404})
      log_fixture(integration, %{response_status: 500})

      result = Logs.count_by_status(integration_id: integration.id)

      assert result[200] == 2
      assert result[404] == 1
      assert result[500] == 1
    end

    test "returns empty map when no logs exist" do
      result = Logs.count_by_status(integration_id: Ecto.UUID.generate())

      assert result == %{}
    end
  end

  describe "count_by_method/1" do
    test "groups logs by HTTP method" do
      integration = integration_fixture()

      log_fixture(integration, %{method: "GET"})
      log_fixture(integration, %{method: "POST"})
      log_fixture(integration, %{method: "POST"})
      log_fixture(integration, %{method: "POST"})

      result = Logs.count_by_method(integration_id: integration.id)

      assert result["GET"] == 1
      assert result["POST"] == 3
    end

    test "returns empty map when no logs exist" do
      result = Logs.count_by_method(integration_id: Ecto.UUID.generate())

      assert result == %{}
    end
  end
end
