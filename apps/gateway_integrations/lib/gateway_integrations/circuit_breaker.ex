defmodule GatewayIntegrations.CircuitBreaker do
  alias GatewayDb.CircuitBreakers
  require Logger

  @failure_threshold 5
  @timeout_ms 60_000

  @type state :: :closed | :open | :half_open
  @type check_result :: :allow | {:deny, reason :: String.t()}

  @spec check_request(String.t()) :: check_result()
  def check_request(integration_id) do
    case CircuitBreakers.get_state(integration_id) do
      {:ok, cb_state} ->
        evaluate_state(cb_state, integration_id)

      {:error, :not_found} ->
        # First request, create initial state
        initialize_circuit_breaker(integration_id)
        :allow
    end
  end

  @spec record_success(String.t()) :: :ok
  def record_success(integration_id) do
    case CircuitBreakers.get_state(integration_id) do
      {:ok, cb_state} ->
        handle_success(cb_state, integration_id)

      {:error, :not_found} ->
        :ok
    end
  end

  @spec record_failure(String.t(), String.t()) :: :ok
  def record_failure(integration_id, error_message) do
    case CircuitBreakers.get_state(integration_id) do
      {:ok, cb_state} ->
        handle_failure(cb_state, integration_id, error_message)

      {:error, :not_found} ->
        initialize_circuit_breaker(integration_id)
        handle_first_failure(integration_id, error_message)
    end
  end

  defp evaluate_state(cb_state, integration_id) do
    case cb_state.state do
      "closed" ->
        :allow

      "open" ->
        check_if_should_retry(cb_state, integration_id)

      "half_open" ->
        allow_half_open_request(integration_id)
    end
  end

  defp check_if_should_retry(cb_state, integration_id) do
    now = DateTime.utc_now()

    if DateTime.compare(now, cb_state.next_retry_at) in [:gt, :eq] do
      Logger.info("Circuit breaker transitioning to half_open",
        integration_id: integration_id
      )

      CircuitBreakers.transition_to_half_open(integration_id)
      :allow
    else
      seconds_until_retry = DateTime.diff(cb_state.next_retry_at, now)

      {:deny, "Circuit breaker is open. Retry in #{seconds_until_retry} seconds"}
    end
  end

  defp allow_half_open_request(_integration_id) do
    :allow
  end

  defp handle_success(cb_state, integration_id) do
    case cb_state.state do
      "half_open" ->
        Logger.info("Circuit breaker recovered, transitioning to closed",
          integration_id: integration_id
        )

        CircuitBreakers.reset_state(integration_id)

      "closed" ->
        if cb_state.failure_count > 0 do
          CircuitBreakers.reset_failures(integration_id)
        end

      "open" ->
        :ok
    end

    :ok
  end

  defp handle_failure(cb_state, integration_id, error_message) do
    case cb_state.state do
      "closed" ->
        handle_failure_in_closed_state(cb_state, integration_id, error_message)

      "half_open" ->
        handle_failure_in_half_open_state(integration_id, error_message)

      "open" ->
        Logger.warning("Request failed while circuit breaker is open",
          integration_id: integration_id,
          error: error_message
        )
    end

    :ok
  end

  defp handle_failure_in_closed_state(cb_state, integration_id, error_message) do
    new_failure_count = cb_state.failure_count + 1

    CircuitBreakers.increment_failure(integration_id, error_message)

    if new_failure_count >= @failure_threshold do
      Logger.warning("Circuit breaker opening due to consecutive failures",
        integration_id: integration_id,
        failure_count: new_failure_count,
        threshold: @failure_threshold
      )

      next_retry_at = DateTime.add(DateTime.utc_now(), @timeout_ms, :millisecond)
      CircuitBreakers.open_circuit(integration_id, next_retry_at)
    end

    :ok
  end

  defp handle_failure_in_half_open_state(integration_id, error_message) do
    Logger.warning("Circuit breaker failed in half_open state, reopening",
      integration_id: integration_id,
      error: error_message
    )

    next_retry_at = DateTime.add(DateTime.utc_now(), @timeout_ms, :millisecond)
    CircuitBreakers.open_circuit(integration_id, next_retry_at)

    :ok
  end

  defp initialize_circuit_breaker(integration_id) do
    case CircuitBreakers.create_state(integration_id, "closed") do
      {:ok, _state} ->
        Logger.info("Circuit breaker initialized",
          integration_id: integration_id,
          state: "closed"
        )

      {:error, reason} ->
        Logger.error("Failed to initialize circuit breaker",
          integration_id: integration_id,
          reason: inspect(reason)
        )
    end

    :ok
  end

  defp handle_first_failure(integration_id, error_message) do
    CircuitBreakers.increment_failure(integration_id, error_message)
    :ok
  end

  @spec get_state(String.t()) :: {:ok, map()} | {:error, atom()}
  def get_state(integration_id) do
    CircuitBreakers.get_state(integration_id)
  end

  @spec reset(String.t()) :: {:ok, map()} | {:error, atom()}
  def reset(integration_id) do
    Logger.info("Manually resetting circuit breaker", integration_id: integration_id)
    CircuitBreakers.reset_state(integration_id)
  end

  @spec open(String.t()) :: {:ok, map()} | {:error, atom()}
  def open(integration_id) do
    Logger.info("Manually opening circuit breaker", integration_id: integration_id)
    next_retry_at = DateTime.add(DateTime.utc_now(), @timeout_ms, :millisecond)
    CircuitBreakers.open_circuit(integration_id, next_retry_at)
  end
end
