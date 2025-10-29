defmodule GatewayDb.CircuitBreakersTest do
  use GatewayDb.DataCase, async: true

  alias GatewayDb.{CircuitBreakers, Integrations}

  defp integration_fixture do
    {:ok, integration} =
      Integrations.create_integration(%{
        name: "test_integration_#{System.unique_integer([:positive])}",
        type: "payment",
        base_url: "https://api.test.com"
      })

    integration
  end

  describe "get_state/1" do
    test "returns state when it exists" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert {:ok, found} = CircuitBreakers.get_state(integration.id)
      assert found.id == state.id
      assert found.integration_id == integration.id
    end

    test "returns error when state does not exist" do
      integration = integration_fixture()

      assert {:error, :not_found} = CircuitBreakers.get_state(integration.id)
    end
  end

  describe "get_state!/1" do
    test "returns state when it exists" do
      integration = integration_fixture()
      {:ok, _state} = CircuitBreakers.get_or_initialize_state(integration.id)

      found = CircuitBreakers.get_state!(integration.id)
      assert found.integration_id == integration.id
    end

    test "raises when state does not exist" do
      integration = integration_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        CircuitBreakers.get_state!(integration.id)
      end
    end
  end

  describe "get_or_initialize_state/1" do
    test "returns existing state if it exists" do
      integration = integration_fixture()

      {:ok, state1} = CircuitBreakers.get_or_initialize_state(integration.id)
      {:ok, state2} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert state1.id == state2.id
    end

    test "creates new state in closed if it doesn't exist" do
      integration = integration_fixture()

      assert {:error, :not_found} = CircuitBreakers.get_state(integration.id)

      assert {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)
      assert state.integration_id == integration.id
      assert state.state == "closed"
      assert state.failure_count == 0
    end
  end

  describe "list_states/0" do
    test "returns all circuit breaker states" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      {:ok, state1} = CircuitBreakers.get_or_initialize_state(integration1.id)
      {:ok, state2} = CircuitBreakers.get_or_initialize_state(integration2.id)

      states = CircuitBreakers.list_states()

      assert length(states) >= 2
      assert Enum.any?(states, fn s -> s.id == state1.id end)
      assert Enum.any?(states, fn s -> s.id == state2.id end)
    end

    test "returns empty list when no states exist" do
      assert CircuitBreakers.list_states() == []
    end
  end

  describe "list_open_circuits/0" do
    test "returns only open circuits" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      {:ok, _closed} = CircuitBreakers.get_or_initialize_state(integration1.id)
      {:ok, open} = CircuitBreakers.open_circuit(integration2.id)

      result = CircuitBreakers.list_open_circuits()

      assert Enum.all?(result, fn s -> s.state == "open" end)
      assert Enum.any?(result, fn s -> s.id == open.id end)
    end

    test "returns empty list when no open circuits exist" do
      integration = integration_fixture()
      {:ok, _closed} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert CircuitBreakers.list_open_circuits() == []
    end
  end

  describe "list_half_open_circuits/0" do
    test "returns only half-open circuits" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      {:ok, _closed} = CircuitBreakers.get_or_initialize_state(integration1.id)
      {:ok, half_open} = CircuitBreakers.half_open_circuit(integration2.id)

      result = CircuitBreakers.list_half_open_circuits()

      assert Enum.all?(result, fn s -> s.state == "half_open" end)
      assert Enum.any?(result, fn s -> s.id == half_open.id end)
    end

    test "returns empty list when no half-open circuits exist" do
      integration = integration_fixture()
      {:ok, _closed} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert CircuitBreakers.list_half_open_circuits() == []
    end
  end

  describe "should_allow_request?/1" do
    test "allows request when circuit is closed" do
      integration = integration_fixture()
      {:ok, _state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert {:ok, :allow} = CircuitBreakers.should_allow_request?(integration.id)
    end

    test "allows request when circuit is half-open" do
      integration = integration_fixture()
      {:ok, _state} = CircuitBreakers.half_open_circuit(integration.id)

      assert {:ok, :allow} = CircuitBreakers.should_allow_request?(integration.id)
    end

    test "blocks request when circuit is open and timeout not reached" do
      integration = integration_fixture()
      {:ok, _state} = CircuitBreakers.open_circuit(integration.id, timeout: 3600)

      assert {:error, :not_ready} = CircuitBreakers.should_allow_request?(integration.id)
    end

    test "transitions to half-open when circuit is open and timeout reached" do
      integration = integration_fixture()

      # Open circuit with 0 second timeout (immediately expired)
      {:ok, state} = CircuitBreakers.open_circuit(integration.id, timeout: 0)
      assert state.state == "open"

      # Small delay to ensure timeout has passed
      Process.sleep(10)

      # Should transition to half_open and allow request
      assert {:ok, :allow} = CircuitBreakers.should_allow_request?(integration.id)

      # Verify state transitioned
      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "half_open"
    end

    test "creates state if it doesn't exist" do
      integration = integration_fixture()

      assert {:error, :not_found} = CircuitBreakers.get_state(integration.id)
      assert {:ok, :allow} = CircuitBreakers.should_allow_request?(integration.id)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "closed"
    end
  end

  # ============================================================================
  # State Update Tests
  # ============================================================================

  describe "update_state/2" do
    test "updates state attributes" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert {:ok, updated} =
        CircuitBreakers.update_state(state, %{failure_count: 3})

      assert updated.failure_count == 3
    end

    test "returns error with invalid attributes" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert {:error, changeset} =
        CircuitBreakers.update_state(state, %{state: "invalid"})

      assert "should be closed, open or half_open" in errors_on(changeset).state
    end
  end

  describe "delete_state/1" do
    test "deletes the state" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert {:ok, deleted} = CircuitBreakers.delete_state(state)
      assert deleted.id == state.id
      assert {:error, :not_found} = CircuitBreakers.get_state(integration.id)
    end
  end

  describe "record_failure/2" do
    test "increments failure count" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert state.failure_count == 0

      {:ok, updated} = CircuitBreakers.record_failure(integration.id)

      assert updated.failure_count == 1
      assert updated.last_failure_at != nil
    end

    test "opens circuit automatically when threshold reached" do
      integration = integration_fixture()

      Enum.each(1..4, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "closed"
      assert state.failure_count == 4

      {:ok, state} = CircuitBreakers.record_failure(integration.id)

      assert state.state == "open"
      assert state.failure_count == 5
      assert state.opened_at != nil
      assert state.next_retry_at != nil
    end

    test "respects custom threshold" do
      integration = integration_fixture()

      Enum.each(1..2, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id, threshold: 3)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "closed"

      # 3rd failure should open
      {:ok, state} = CircuitBreakers.record_failure(integration.id, threshold: 3)

      assert state.state == "open"
    end

    test "respects custom timeout" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id, timeout: 120)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "open"

      now = DateTime.utc_now()
      diff = DateTime.diff(state.next_retry_at, now, :second)
      assert diff >= 119 && diff <= 121
    end
  end

  describe "record_success/1" do
    test "resets failure count" do
      integration = integration_fixture()

      Enum.each(1..3, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.failure_count == 3

      {:ok, state} = CircuitBreakers.record_success(integration.id)

      assert state.failure_count == 0
      assert state.state == "closed"
    end

    test "closes open circuit" do
      integration = integration_fixture()
      {:ok, _} = CircuitBreakers.open_circuit(integration.id)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "open"

      {:ok, state} = CircuitBreakers.record_success(integration.id)

      assert state.state == "closed"
      assert state.failure_count == 0
      assert state.opened_at == nil
      assert state.next_retry_at == nil
    end

    test "closes half-open circuit" do
      integration = integration_fixture()
      {:ok, _} = CircuitBreakers.half_open_circuit(integration.id)

      {:ok, state} = CircuitBreakers.record_success(integration.id)

      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "clears all timestamps" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.last_failure_at != nil
      assert state.opened_at != nil

      {:ok, state} = CircuitBreakers.record_success(integration.id)

      assert state.last_failure_at == nil
      assert state.opened_at == nil
      assert state.next_retry_at == nil
    end
  end

  describe "open_circuit/2" do
    test "opens a closed circuit" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)

      assert state.state == "closed"

      {:ok, state} = CircuitBreakers.open_circuit(integration.id)

      assert state.state == "open"
      assert state.opened_at != nil
      assert state.next_retry_at != nil
    end

    test "sets next_retry_at with default timeout" do
      integration = integration_fixture()

      now = DateTime.utc_now()
      {:ok, state} = CircuitBreakers.open_circuit(integration.id)

      diff = DateTime.diff(state.next_retry_at, now, :second)
      assert diff >= 59 && diff <= 61
    end

    test "respects custom timeout option" do
      integration = integration_fixture()

      now = DateTime.utc_now()
      {:ok, state} = CircuitBreakers.open_circuit(integration.id, timeout: 300)

      diff = DateTime.diff(state.next_retry_at, now, :second)
      assert diff >= 299 && diff <= 301
    end
  end

  describe "close_circuit/1" do
    test "closes an open circuit" do
      integration = integration_fixture()
      {:ok, _} = CircuitBreakers.open_circuit(integration.id)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "open"

      {:ok, state} = CircuitBreakers.close_circuit(integration.id)

      assert state.state == "closed"
    end

    test "resets all counters and timestamps" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "open"
      assert state.failure_count == 5

      {:ok, state} = CircuitBreakers.close_circuit(integration.id)

      assert state.state == "closed"
      assert state.failure_count == 0
      assert state.last_failure_at == nil
      assert state.opened_at == nil
      assert state.next_retry_at == nil
    end
  end

  describe "half_open_circuit/1" do
    test "transitions open circuit to half-open" do
      integration = integration_fixture()
      {:ok, _} = CircuitBreakers.open_circuit(integration.id)

      {:ok, state} = CircuitBreakers.half_open_circuit(integration.id)

      assert state.state == "half_open"
      assert state.next_retry_at == nil
    end

    test "clears next_retry_at" do
      integration = integration_fixture()
      {:ok, state} = CircuitBreakers.open_circuit(integration.id)

      assert state.next_retry_at != nil

      {:ok, state} = CircuitBreakers.half_open_circuit(integration.id)

      assert state.next_retry_at == nil
    end

    test "keeps failure_count" do
      integration = integration_fixture()

      Enum.each(1..5, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id)
      end)

      {:ok, state} = CircuitBreakers.half_open_circuit(integration.id)

      assert state.failure_count == 5
      assert state.state == "half_open"
    end
  end

  describe "reset/1" do
    test "resets circuit to closed state" do
      integration = integration_fixture()

      {:ok, _} = CircuitBreakers.open_circuit(integration.id)

      {:ok, state} = CircuitBreakers.reset(integration.id)

      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "is alias for close_circuit" do
      integration = integration_fixture()
      {:ok, _} = CircuitBreakers.open_circuit(integration.id)

      {:ok, state1} = CircuitBreakers.reset(integration.id)

      {:ok, _} = CircuitBreakers.open_circuit(integration.id)
      {:ok, state2} = CircuitBreakers.close_circuit(integration.id)

      assert state1.state == state2.state
      assert state1.failure_count == state2.failure_count
    end
  end

  describe "reset_all/0" do
    test "resets all circuit breakers to closed" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()
      integration3 = integration_fixture()

      {:ok, _} = CircuitBreakers.open_circuit(integration1.id)
      {:ok, _} = CircuitBreakers.half_open_circuit(integration2.id)
      {:ok, _} = CircuitBreakers.get_or_initialize_state(integration3.id)

      {count, nil} = CircuitBreakers.reset_all()

      assert count == 3

      {:ok, state1} = CircuitBreakers.get_state(integration1.id)
      {:ok, state2} = CircuitBreakers.get_state(integration2.id)
      {:ok, state3} = CircuitBreakers.get_state(integration3.id)

      assert state1.state == "closed"
      assert state2.state == "closed"
      assert state3.state == "closed"
    end

    test "returns count of updated records" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      {:ok, _} = CircuitBreakers.open_circuit(integration1.id)
      {:ok, _} = CircuitBreakers.open_circuit(integration2.id)

      {count, nil} = CircuitBreakers.reset_all()

      assert count == 2
    end
  end

  describe "close_expired_circuits/0" do
    test "transitions expired open circuits to half-open" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      {:ok, state1} = CircuitBreakers.open_circuit(integration1.id, timeout: 0)
      assert state1.state == "open"

      {:ok, state2} = CircuitBreakers.open_circuit(integration2.id, timeout: 3600)
      assert state2.state == "open"

      Process.sleep(10)

      {count, nil} = CircuitBreakers.close_expired_circuits()

      assert count == 1

      {:ok, state1} = CircuitBreakers.get_state(integration1.id)
      {:ok, state2} = CircuitBreakers.get_state(integration2.id)

      assert state1.state == "half_open"
      assert state2.state == "open"
    end

    test "does not affect closed or half-open circuits" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      {:ok, _} = CircuitBreakers.get_or_initialize_state(integration1.id)
      {:ok, _} = CircuitBreakers.half_open_circuit(integration2.id)

      {count, nil} = CircuitBreakers.close_expired_circuits()

      assert count == 0

      {:ok, state1} = CircuitBreakers.get_state(integration1.id)
      {:ok, state2} = CircuitBreakers.get_state(integration2.id)

      assert state1.state == "closed"
      assert state2.state == "half_open"
    end

    test "returns count of updated records" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()
      integration3 = integration_fixture()

      {:ok, _} = CircuitBreakers.open_circuit(integration1.id, timeout: 0)
      {:ok, _} = CircuitBreakers.open_circuit(integration2.id, timeout: 0)
      {:ok, _} = CircuitBreakers.open_circuit(integration3.id, timeout: 3600)

      Process.sleep(10)

      {count, nil} = CircuitBreakers.close_expired_circuits()

      assert count == 2
    end
  end

  describe "count_by_state/0" do
    test "groups circuit breakers by state" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()
      integration3 = integration_fixture()
      integration4 = integration_fixture()

      {:ok, _} = CircuitBreakers.get_or_initialize_state(integration1.id)
      {:ok, _} = CircuitBreakers.get_or_initialize_state(integration2.id)
      {:ok, _} = CircuitBreakers.open_circuit(integration3.id)
      {:ok, _} = CircuitBreakers.half_open_circuit(integration4.id)

      result = CircuitBreakers.count_by_state()

      assert result["closed"] == 2
      assert result["open"] == 1
      assert result["half_open"] == 1
    end

    test "returns empty map when no states exist" do
      result = CircuitBreakers.count_by_state()

      assert result == %{}
    end
  end

  describe "total_failures/0" do
    test "sums all failure counts" do
      integration1 = integration_fixture()
      integration2 = integration_fixture()

      Enum.each(1..3, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration1.id)
      end)

      Enum.each(1..2, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration2.id)
      end)

      total = CircuitBreakers.total_failures()

      assert total == 5
    end

    test "returns 0 when no states exist" do
      assert CircuitBreakers.total_failures() == 0
    end
  end

  describe "complete circuit breaker flow" do
    test "closed -> failures -> open -> timeout -> half_open -> success -> closed" do
      integration = integration_fixture()

      {:ok, state} = CircuitBreakers.get_or_initialize_state(integration.id)
      assert state.state == "closed"
      assert state.failure_count == 0

      Enum.each(1..4, fn _ ->
        {:ok, _} = CircuitBreakers.record_failure(integration.id, threshold: 5)
      end)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "closed"
      assert state.failure_count == 4

      {:ok, state} = CircuitBreakers.record_failure(integration.id, threshold: 5, timeout: 0)
      assert state.state == "open"

      Process.sleep(10)
      assert {:ok, :allow} = CircuitBreakers.should_allow_request?(integration.id)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "half_open"

      {:ok, state} = CircuitBreakers.record_success(integration.id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "half_open -> failure -> open again" do
      integration = integration_fixture()

      {:ok, _} = CircuitBreakers.open_circuit(integration.id, timeout: 0)
      Process.sleep(10)
      {:ok, :allow} = CircuitBreakers.should_allow_request?(integration.id)

      {:ok, state} = CircuitBreakers.get_state(integration.id)
      assert state.state == "half_open"

      {:ok, state} = CircuitBreakers.record_failure(integration.id, threshold: 1)

      assert state.state == "open"
    end
  end
end
