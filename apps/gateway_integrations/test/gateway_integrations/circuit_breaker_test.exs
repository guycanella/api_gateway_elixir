defmodule GatewayIntegrations.CircuitBreakerTest do
  use ExUnit.Case, async: true
  alias GatewayIntegrations.CircuitBreaker
  alias GatewayDb.{Repo, Integration, CircuitBreakers}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, integration} =
      %Integration{}
      |> Integration.changeset(%{
        name: "test_service",
        type: "other",
        base_url: "https://api.test.com",
        is_active: true,
        config: %{}
      })
      |> Repo.insert()

    %{integration_id: integration.id}
  end

  describe "check_request/1" do
    test "allows request when circuit is closed", %{integration_id: integration_id} do
      assert :allow = CircuitBreaker.check_request(integration_id)
    end

    test "creates initial state on first request", %{integration_id: integration_id} do
      assert :allow = CircuitBreaker.check_request(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "denies request when circuit is open", %{integration_id: integration_id} do
      next_retry = DateTime.add(DateTime.utc_now(), 60, :second)
      CircuitBreakers.open_circuit(integration_id, next_retry)

      assert {:deny, message} = CircuitBreaker.check_request(integration_id)
      assert message =~ "Circuit breaker is open"
      assert message =~ "Retry in"
    end

    test "allows request in half_open state", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")
      CircuitBreakers.half_open_circuit(integration_id)

      assert :allow = CircuitBreaker.check_request(integration_id)
    end

    test "transitions to half_open after timeout", %{integration_id: integration_id} do
      past_time = DateTime.add(DateTime.utc_now(), -1, :second)
      CircuitBreakers.open_circuit(integration_id, past_time)

      assert :allow = CircuitBreaker.check_request(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "half_open"
    end
  end

  describe "record_success/1" do
    test "resets state to closed from half_open", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "half_open")

      :ok = CircuitBreaker.record_success(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 0
    end

    test "resets failure count in closed state", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")
      CircuitBreakers.increment_failure(integration_id, "error")
      CircuitBreakers.increment_failure(integration_id, "error")

      {:ok, state_before} = CircuitBreakers.get_state(integration_id)
      assert state_before.failure_count == 2

      :ok = CircuitBreaker.record_success(integration_id)

      {:ok, state_after} = CircuitBreakers.get_state(integration_id)
      assert state_after.failure_count == 0
      assert state_after.state == "closed"
    end
  end

  describe "record_failure/2" do
    test "increments failure count in closed state", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      :ok = CircuitBreaker.record_failure(integration_id, "Connection timeout")

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.failure_count == 1
      assert state.state == "closed"
    end

    test "opens circuit after threshold failures", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..4 do
        :ok = CircuitBreaker.record_failure(integration_id, "error")
      end

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 4

      :ok = CircuitBreaker.record_failure(integration_id, "final error")

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
      assert state.failure_count == 5
      assert state.opened_at != nil
      assert state.next_retry_at != nil
    end

    test "reopens circuit on failure in half_open state", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "half_open")

      :ok = CircuitBreaker.record_failure(integration_id, "still failing")

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
      assert state.next_retry_at != nil
    end

    test "sets next_retry_at in the future when opening", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..5 do
        :ok = CircuitBreaker.record_failure(integration_id, "error")
      end

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      now = DateTime.utc_now()

      assert DateTime.compare(state.next_retry_at, now) == :gt
    end
  end

  describe "state persistence" do
    test "state survives across function calls", %{integration_id: integration_id} do
      CircuitBreaker.check_request(integration_id)

      for _ <- 1..3 do
        CircuitBreaker.record_failure(integration_id, "error")
      end

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.failure_count == 3
    end

    test "opened_at is recorded when circuit opens", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..5 do
        CircuitBreaker.record_failure(integration_id, "error")
      end

      {:ok, state} = CircuitBreakers.get_state(integration_id)

      assert state.state == "open", "Expected state to be 'open', got '#{state.state}'"
      assert state.opened_at != nil, "opened_at should not be nil when circuit is open"

      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(now, state.opened_at, :second)
      assert diff_seconds >= 0 and diff_seconds < 5
    end
  end

  describe "get_state/1" do
    test "returns current state", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")
      CircuitBreakers.increment_failure(integration_id, "error")

      {:ok, state} = CircuitBreaker.get_state(integration_id)
      assert state.state == "closed"
      assert state.failure_count == 1
    end

    test "returns error when state not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = CircuitBreaker.get_state(non_existent_id)
    end
  end

  describe "reset/1" do
    test "resets circuit breaker to closed state", %{integration_id: integration_id} do
      next_retry = DateTime.add(DateTime.utc_now(), 60, :second)
      CircuitBreakers.open_circuit(integration_id, next_retry)

      {:ok, state_before} = CircuitBreakers.get_state(integration_id)
      assert state_before.state == "open"

      {:ok, _state} = CircuitBreaker.reset(integration_id)

      {:ok, state_after} = CircuitBreakers.get_state(integration_id)
      assert state_after.state == "closed"
      assert state_after.failure_count == 0
      assert state_after.opened_at == nil
      assert state_after.next_retry_at == nil
    end
  end

  describe "open/1" do
    test "manually opens circuit breaker", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      {:ok, _state} = CircuitBreaker.open(integration_id)

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"
      assert state.next_retry_at != nil
    end
  end

  describe "integration scenario" do
    test "complete circuit breaker lifecycle", %{integration_id: integration_id} do
      assert :allow = CircuitBreaker.check_request(integration_id)

      for _ <- 1..3 do
        CircuitBreaker.record_failure(integration_id, "error")
      end

      assert :allow = CircuitBreaker.check_request(integration_id)

      for _ <- 1..2 do
        CircuitBreaker.record_failure(integration_id, "error")
      end

      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "open"

      assert {:deny, _} = CircuitBreaker.check_request(integration_id)

      CircuitBreakers.transition_to_half_open(integration_id)

      assert :allow = CircuitBreaker.check_request(integration_id)

      CircuitBreaker.record_success(integration_id)

      {:ok, final_state} = CircuitBreakers.get_state(integration_id)
      assert final_state.state == "closed"
      assert final_state.failure_count == 0
    end

    test "circuit stays open on failure in half_open", %{integration_id: integration_id} do
      CircuitBreakers.create_state(integration_id, "closed")

      for _ <- 1..5 do
        CircuitBreaker.record_failure(integration_id, "error")
      end

      CircuitBreakers.transition_to_half_open(integration_id)
      {:ok, state} = CircuitBreakers.get_state(integration_id)
      assert state.state == "half_open"

      CircuitBreaker.record_failure(integration_id, "still broken")

      {:ok, final_state} = CircuitBreakers.get_state(integration_id)
      assert final_state.state == "open"
    end
  end
end
