defmodule GatewayDb.CircuitBreakers do
  import Ecto.Query, warn: false
  alias GatewayDb.Repo
  alias GatewayDb.CircuitBreakerState

  @default_failure_threshold 5
  @default_timeout_seconds 60

  def get_state(integration_id) do
    case Repo.get_by(CircuitBreakerState, integration_id: integration_id) do
      nil -> {:error, :not_found}
      state -> {:ok, state}
    end
  end

  def get_state!(integration_id) do
    Repo.get_by!(CircuitBreakerState, integration_id: integration_id)
  end

  def get_or_initialize_state(integration_id) do
    case get_state(integration_id) do
      {:ok, state} ->
        {:ok, state}

      {:error, :not_found} ->
        create_initial_state(integration_id)
    end
  end

  def list_states do
    Repo.all(CircuitBreakerState)
  end

  def list_open_circuits do
    CircuitBreakerState
    |> where([cb], cb.state == "open")
    |> Repo.all()
  end

  def list_half_open_circuits do
    CircuitBreakerState
    |> where([cb], cb.state == "half_open")
    |> Repo.all()
  end

  def should_allow_request?(integration_id) do
    case get_or_initialize_state(integration_id) do
      {:ok, %{state: "closed"}} ->
        {:ok, :allow}

      {:ok, %{state: "half_open"}} ->
        {:ok, :allow}

      {:ok, %{state: "open", next_retry_at: next_retry}} ->
        now = DateTime.utc_now()
        if DateTime.compare(now, next_retry) == :lt do
          {:error, :not_ready}
        else
          half_open_circuit(integration_id)
          {:ok, :allow}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_state(%CircuitBreakerState{} = state, attrs) do
    state
    |> CircuitBreakerState.changeset(attrs)
    |> Repo.update()
  end

  def delete_state(%CircuitBreakerState{} = state) do
    Repo.delete(state)
  end

  def record_failure(integration_id, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_failure_threshold)
    timeout = Keyword.get(opts, :timeout, @default_timeout_seconds)

    {:ok, state} = get_or_initialize_state(integration_id)
    new_count = state.failure_count + 1
    now = DateTime.utc_now()

    attrs = %{
      failure_count: new_count,
      last_failure_at: now
    }

    attrs = if new_count >= threshold do
      next_retry = DateTime.add(now, timeout, :second)

      Map.merge(attrs, %{
        state: "open",
        opened_at: now,
        next_retry_at: next_retry
      })
    else
      attrs
    end

    update_state(state, attrs)
  end

  def record_success(integration_id) do
    {:ok, state} = get_or_initialize_state(integration_id)

    attrs = %{
      state: "closed",
      failure_count: 0,
      last_failure_at: nil,
      opened_at: nil,
      next_retry_at: nil
    }

    update_state(state, attrs)
  end

  def open_circuit(integration_id, opts) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_seconds)
    {:ok, state} = get_or_initialize_state(integration_id)

    now = DateTime.utc_now()
    next_retry = DateTime.add(now, timeout, :second)

    attrs = %{
      state: "open",
      opened_at: now,
      next_retry_at: next_retry
    }

    update_state(state, attrs)
  end

  def open_circuit(integration_id, %DateTime{} = next_retry_at) do
    {:ok, state} = get_or_initialize_state(integration_id)
    now = DateTime.utc_now()

    attrs = %{
      state: "open",
      opened_at: now,
      next_retry_at: next_retry_at
    }

    update_state(state, attrs)
  end

  def close_circuit(integration_id) do
    {:ok, state} = get_or_initialize_state(integration_id)

    attrs = %{
      state: "closed",
      failure_count: 0,
      last_failure_at: nil,
      opened_at: nil,
      next_retry_at: nil
    }

    update_state(state, attrs)
  end

  def half_open_circuit(integration_id) do
    {:ok, state} = get_or_initialize_state(integration_id)

    attrs = %{
      state: "half_open",
      next_retry_at: nil
    }

    update_state(state, attrs)
  end

  def reset(integration_id) do
    close_circuit(integration_id)
  end

  def reset_all do
    CircuitBreakerState
    |> Repo.update_all(set: [
      state: "closed",
      failure_count: 0,
      last_failure_at: nil,
      opened_at: nil,
      next_retry_at: nil,
      updated_at: DateTime.utc_now()
    ])
  end

  def transition_to_half_open(integration_id) do
    half_open_circuit(integration_id)
  end

  def reset_failures(integration_id) do
    {:ok, state} = get_or_initialize_state(integration_id)

    attrs = %{
      failure_count: 0,
      last_failure_at: nil
    }

    update_state(state, attrs)
  end

  def increment_failure(integration_id, error_message) when is_binary(error_message) do
    {:ok, state} = get_or_initialize_state(integration_id)
    now = DateTime.utc_now()

    attrs = %{
      failure_count: state.failure_count + 1,
      last_failure_at: now
    }

    update_state(state, attrs)
  end

  def create_state(integration_id, initial_state)
      when initial_state in ["closed", "open", "half_open"] do
    attrs = %{
      integration_id: integration_id,
      state: initial_state,
      failure_count: 0
    }

    %CircuitBreakerState{}
    |> CircuitBreakerState.changeset(attrs)
    |> Repo.insert()
  end

  def reset_state(integration_id) do
    close_circuit(integration_id)
  end

  def close_expired_circuits do
    now = DateTime.utc_now()

    CircuitBreakerState
    |> where([cb], cb.state == "open")
    |> where([cb], cb.next_retry_at <= ^now)
    |> Repo.update_all(set: [
      state: "half_open",
      next_retry_at: nil,
      updated_at: now
    ])
  end

  def count_by_state do
    CircuitBreakerState
    |> group_by([cb], cb.state)
    |> select([cb], {cb.state, count(cb.id)})
    |> Repo.all()
    |> Map.new()
  end

  def total_failures do
    CircuitBreakerState
    |> select([cb], sum(cb.failure_count))
    |> Repo.one()
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp create_initial_state(integration_id) do
    attrs = %{
      integration_id: integration_id,
      state: "closed",
      failure_count: 0
    }

    %CircuitBreakerState{}
    |> CircuitBreakerState.changeset(attrs)
    |> Repo.insert()
  end
end
