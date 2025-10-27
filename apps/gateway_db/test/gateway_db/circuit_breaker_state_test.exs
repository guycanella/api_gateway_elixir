defmodule GatewayDb.CircuitBreakerStateTest do
  use ExUnit.Case, async: true
  import Ecto.Changeset

  alias GatewayDb.{Integration, CircuitBreakerState, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, integration} = create_integration(%{
      name: "test_service",
      type: "payment",
      base_url: "https://api.test.com"
    })

    %{integration: integration}
  end

  describe "changeset/2 - valid data" do
    test "creates a valid changeset with required fields", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :integration_id) == integration.id
      cb = apply_changes(changeset)
      assert cb.state == "closed"
      assert cb.failure_count == 0
    end

    test "creates a valid changeset with all fields", %{integration: integration} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      next_retry = DateTime.add(now, 60, :second)

      attrs = %{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        last_failure_at: now,
        opened_at: now,
        next_retry_at: next_retry
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :failure_count) == 5
      assert get_change(changeset, :opened_at) == now
    end

    test "accepts all valid states", %{integration: integration} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs_closed = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      }
      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs_closed)
      assert changeset.valid?, "State 'closed' should be valid"

      attrs_open = %{
        integration_id: integration.id,
        state: "open",
        failure_count: 0,
        opened_at: now,
        next_retry_at: DateTime.add(now, 60, :second)
      }
      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs_open)
      assert changeset.valid?, "State 'open' should be valid"

      attrs_half = %{
        integration_id: integration.id,
        state: "half_open",
        failure_count: 0
      }
      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs_half)
      assert changeset.valid?, "State 'half_open' should be valid"
    end

    test "sets default values", %{integration: integration} do
      attrs = %{
        integration_id: integration.id
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)
      cb = apply_changes(changeset)

      assert cb.state == "closed"
      assert cb.failure_count == 0
    end
  end

  describe "changeset/2 - validations" do
    test "requires integration_id", %{integration: _integration} do
      attrs = %{
        state: "closed",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).integration_id
    end

    test "rejects invalid state", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "invalid_state",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      refute changeset.valid?
      assert "should be closed, open or half_open" in errors_on(changeset).state
    end

    test "rejects negative failure_count", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: -1
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      refute changeset.valid?
      assert "cannot be negative" in errors_on(changeset).failure_count
    end

    test "accepts zero failure_count", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      assert changeset.valid?
    end

    test "requires opened_at and next_retry_at when state is open", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      refute changeset.valid?
      assert "must be present when state = 'open'" in errors_on(changeset).opened_at
      assert "must be present when state = 'open'" in errors_on(changeset).next_retry_at
    end

    test "does not require opened_at and next_retry_at when state is closed", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      assert changeset.valid?
    end
  end

  describe "Repo.insert/1" do
    test "successfully inserts a valid circuit breaker", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      assert {:ok, cb} = Repo.insert(changeset)
      assert cb.id != nil
      assert cb.integration_id == integration.id
      assert cb.state == "closed"
      assert cb.inserted_at != nil
      assert cb.updated_at != nil
    end

    test "enforces unique constraint on integration_id", %{integration: integration} do
      attrs = %{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      }

      changeset1 = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)
      assert {:ok, _cb} = Repo.insert(changeset1)

      changeset2 = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)
      assert {:error, changeset} = Repo.insert(changeset2)

      assert "a circuit breaker already exists for this integration" in errors_on(changeset).integration_id
    end

    test "enforces foreign key constraint", %{integration: _integration} do
      fake_uuid = Ecto.UUID.generate()

      attrs = %{
        integration_id: fake_uuid,
        state: "closed",
        failure_count: 0
      }

      changeset = CircuitBreakerState.changeset(%CircuitBreakerState{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert "integration not found" in errors_on(changeset).integration
    end
  end

  describe "record_failure_changeset/1" do
    test "increments failure_count", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 2
      })

      changeset = CircuitBreakerState.record_failure_changeset(cb)

      assert changeset.valid?
      assert get_change(changeset, :failure_count) == 3
      assert get_change(changeset, :last_failure_at) != nil
    end

    test "updates last_failure_at", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      })

      changeset = CircuitBreakerState.record_failure_changeset(cb)
      {:ok, updated_cb} = Repo.update(changeset)

      assert updated_cb.last_failure_at != nil
    end
  end

  describe "open_changeset/2" do
    test "sets state to open", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 5
      })

      changeset = CircuitBreakerState.open_changeset(cb)

      assert changeset.valid?
      assert get_change(changeset, :state) == "open"
    end

    test "sets opened_at and next_retry_at", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 5
      })

      changeset = CircuitBreakerState.open_changeset(cb)
      {:ok, updated_cb} = Repo.update(changeset)

      assert updated_cb.opened_at != nil
      assert updated_cb.next_retry_at != nil
    end

    test "respects custom retry_after_seconds", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 5
      })

      now = DateTime.utc_now()
      changeset = CircuitBreakerState.open_changeset(cb, retry_after_seconds: 120)
      {:ok, updated_cb} = Repo.update(changeset)

      diff = DateTime.diff(updated_cb.next_retry_at, now, :second)
      assert diff >= 119 && diff <= 121
    end

    test "uses default retry_after_seconds of 60", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 5
      })

      now = DateTime.utc_now()
      changeset = CircuitBreakerState.open_changeset(cb)
      {:ok, updated_cb} = Repo.update(changeset)

      diff = DateTime.diff(updated_cb.next_retry_at, now, :second)
      assert diff >= 59 && diff <= 61
    end
  end

  describe "close_changeset/1" do
    test "sets state to closed", %{integration: integration} do
      now = DateTime.utc_now()
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        opened_at: now,
        next_retry_at: DateTime.add(now, 60, :second)
      })

      changeset = CircuitBreakerState.close_changeset(cb)

      assert changeset.valid?
      assert get_change(changeset, :state) == "closed"
    end

    test "resets failure_count", %{integration: integration} do
      now = DateTime.utc_now()
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        opened_at: now,
        next_retry_at: DateTime.add(now, 60, :second)
      })

      changeset = CircuitBreakerState.close_changeset(cb)

      assert get_change(changeset, :failure_count) == 0
    end

    test "clears timestamps", %{integration: integration} do
      now = DateTime.utc_now()
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        last_failure_at: now,
        opened_at: now,
        next_retry_at: DateTime.add(now, 60, :second)
      })

      changeset = CircuitBreakerState.close_changeset(cb)
      {:ok, updated_cb} = Repo.update(changeset)

      assert updated_cb.state == "closed"
      assert updated_cb.failure_count == 0
      assert updated_cb.last_failure_at == nil
      assert updated_cb.opened_at == nil
      assert updated_cb.next_retry_at == nil
    end
  end

  describe "half_open_changeset/1" do
    test "sets state to half_open", %{integration: integration} do
      now = DateTime.utc_now()
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        opened_at: now,
        next_retry_at: DateTime.add(now, -10, :second)
      })

      changeset = CircuitBreakerState.half_open_changeset(cb)

      assert changeset.valid?
      assert get_change(changeset, :state) == "half_open"
    end

    test "clears next_retry_at", %{integration: integration} do
      now = DateTime.utc_now()
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        opened_at: now,
        next_retry_at: DateTime.add(now, -10, :second)
      })

      changeset = CircuitBreakerState.half_open_changeset(cb)
      {:ok, updated_cb} = Repo.update(changeset)

      assert updated_cb.state == "half_open"
      assert updated_cb.next_retry_at == nil
    end

    test "keeps failure_count", %{integration: integration} do
      now = DateTime.utc_now()
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "open",
        failure_count: 5,
        opened_at: now,
        next_retry_at: DateTime.add(now, 60, :second)
      })

      changeset = CircuitBreakerState.half_open_changeset(cb)
      {:ok, updated_cb} = Repo.update(changeset)

      assert updated_cb.failure_count == 5
    end
  end

  describe "closed?/1" do
    test "returns true when state is closed" do
      cb = %CircuitBreakerState{state: "closed"}
      assert CircuitBreakerState.closed?(cb)
    end

    test "returns false when state is not closed" do
      refute CircuitBreakerState.closed?(%CircuitBreakerState{state: "open"})
      refute CircuitBreakerState.closed?(%CircuitBreakerState{state: "half_open"})
    end
  end

  describe "open?/1" do
    test "returns true when state is open" do
      cb = %CircuitBreakerState{state: "open"}
      assert CircuitBreakerState.open?(cb)
    end

    test "returns false when state is not open" do
      refute CircuitBreakerState.open?(%CircuitBreakerState{state: "closed"})
      refute CircuitBreakerState.open?(%CircuitBreakerState{state: "half_open"})
    end
  end

  describe "half_open?/1" do
    test "returns true when state is half_open" do
      cb = %CircuitBreakerState{state: "half_open"}
      assert CircuitBreakerState.half_open?(cb)
    end

    test "returns false when state is not half_open" do
      refute CircuitBreakerState.half_open?(%CircuitBreakerState{state: "closed"})
      refute CircuitBreakerState.half_open?(%CircuitBreakerState{state: "open"})
    end
  end

  describe "ready_to_retry?/1" do
    test "returns true when state is open and next_retry_at is in the past" do
      past = DateTime.utc_now() |> DateTime.add(-10, :second)
      cb = %CircuitBreakerState{state: "open", next_retry_at: past}

      assert CircuitBreakerState.ready_to_retry?(cb)
    end

    test "returns false when state is open and next_retry_at is in the future" do
      future = DateTime.utc_now() |> DateTime.add(60, :second)
      cb = %CircuitBreakerState{state: "open", next_retry_at: future}

      refute CircuitBreakerState.ready_to_retry?(cb)
    end

    test "returns false when state is open but next_retry_at is nil" do
      cb = %CircuitBreakerState{state: "open", next_retry_at: nil}

      refute CircuitBreakerState.ready_to_retry?(cb)
    end

    test "returns false when state is not open" do
      past = DateTime.utc_now() |> DateTime.add(-10, :second)

      refute CircuitBreakerState.ready_to_retry?(%CircuitBreakerState{state: "closed", next_retry_at: past})
      refute CircuitBreakerState.ready_to_retry?(%CircuitBreakerState{state: "half_open", next_retry_at: past})
    end
  end

  describe "should_open?/2" do
    test "returns true when failure_count reaches threshold" do
      cb = %CircuitBreakerState{failure_count: 5}

      assert CircuitBreakerState.should_open?(cb, threshold: 5)
    end

    test "returns true when failure_count exceeds threshold" do
      cb = %CircuitBreakerState{failure_count: 10}

      assert CircuitBreakerState.should_open?(cb, threshold: 5)
    end

    test "returns false when failure_count is below threshold" do
      cb = %CircuitBreakerState{failure_count: 3}

      refute CircuitBreakerState.should_open?(cb, threshold: 5)
    end

    test "uses default threshold of 5" do
      assert CircuitBreakerState.should_open?(%CircuitBreakerState{failure_count: 5})
      refute CircuitBreakerState.should_open?(%CircuitBreakerState{failure_count: 4})
    end
  end

  describe "status_message/1" do
    test "returns message for closed state" do
      cb = %CircuitBreakerState{state: "closed"}

      assert CircuitBreakerState.status_message(cb) == "Circuit breaker CLOSED - operating normally"
    end

    test "returns message for open state with next_retry_at" do
      next_retry = DateTime.utc_now() |> DateTime.add(60, :second)
      cb = %CircuitBreakerState{state: "open", next_retry_at: next_retry}

      message = CircuitBreakerState.status_message(cb)
      assert String.contains?(message, "Circuit breaker OPEN")
      assert String.contains?(message, "blocking requests until")
    end

    test "returns message for half_open state" do
      cb = %CircuitBreakerState{state: "half_open"}

      assert CircuitBreakerState.status_message(cb) == "Circuit breaker HALF_OPEN - testing recovery"
    end
  end

  describe "state transitions" do
    test "complete flow: closed -> open -> half_open -> closed", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      })

      assert CircuitBreakerState.closed?(cb)

      cb = Enum.reduce(1..5, cb, fn _, acc ->
        changeset = CircuitBreakerState.record_failure_changeset(acc)
        {:ok, updated} = Repo.update(changeset)
        updated
      end)

      assert cb.failure_count == 5
      assert CircuitBreakerState.should_open?(cb)

      changeset = CircuitBreakerState.open_changeset(cb)
      {:ok, cb} = Repo.update(changeset)

      assert CircuitBreakerState.open?(cb)
      assert cb.opened_at != nil
      assert cb.next_retry_at != nil

      past = DateTime.utc_now() |> DateTime.add(-10, :second)
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE circuit_breaker_states SET next_retry_at = $1 WHERE id = $2",
        [past, Ecto.UUID.dump!(cb.id)]
      )

      cb = Repo.get!(CircuitBreakerState, cb.id)
      assert CircuitBreakerState.ready_to_retry?(cb)

      changeset = CircuitBreakerState.half_open_changeset(cb)
      {:ok, cb} = Repo.update(changeset)

      assert CircuitBreakerState.half_open?(cb)
      assert cb.next_retry_at == nil

      changeset = CircuitBreakerState.close_changeset(cb)
      {:ok, cb} = Repo.update(changeset)

      assert CircuitBreakerState.closed?(cb)
      assert cb.failure_count == 0
      assert cb.opened_at == nil
    end

    test "flow: half_open -> open (falha na tentativa)", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "half_open",
        failure_count: 5
      })

      assert CircuitBreakerState.half_open?(cb)

      changeset = CircuitBreakerState.record_failure_changeset(cb)
      {:ok, cb} = Repo.update(changeset)

      assert cb.failure_count == 6

      changeset = CircuitBreakerState.open_changeset(cb)
      {:ok, cb} = Repo.update(changeset)

      assert CircuitBreakerState.open?(cb)
    end
  end

  describe "belongs_to :integration" do
    test "association is defined" do
      assert %Ecto.Association.BelongsTo{} = CircuitBreakerState.__schema__(:association, :integration)
    end

    test "can preload integration", %{integration: integration} do
      {:ok, cb} = create_circuit_breaker(%{
        integration_id: integration.id,
        state: "closed",
        failure_count: 0
      })

      cb_with_integration = Repo.preload(cb, :integration)

      assert cb_with_integration.integration.id == integration.id
      assert cb_with_integration.integration.name == "test_service"
    end
  end

  defp create_integration(attrs) do
    %Integration{}
    |> Integration.changeset(attrs)
    |> Repo.insert()
  end

  defp create_circuit_breaker(attrs) do
    %CircuitBreakerState{}
    |> CircuitBreakerState.changeset(attrs)
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
