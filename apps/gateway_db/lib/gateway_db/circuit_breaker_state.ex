defmodule GatewayDb.CircuitBreakerState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_states ~w(closed open half_open)

  @required_fields ~w(integration_id state failure_count)a
  @optional_fields ~w(last_failure_at opened_at next_retry_at)a

  schema "circuit_breaker_states" do
    belongs_to :integration, GatewayDb.Integration
    field :state, :string, default: "closed"
    field :failure_count, :integer, default: 0
    field :last_failure_at, :utc_datetime
    field :opened_at, :utc_datetime
    field :next_retry_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(circuit_breaker, attrs) do
    circuit_breaker
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:state, @valid_states,
         message: "should be closed, open or half_open")
    |> validate_number(:failure_count, greater_than_or_equal_to: 0,
         message: "cannot be negative")
    |> validate_state_consistency()
    |> unique_constraint(:integration_id,
         message: "a circuit breaker already exists for this integration")
    |> assoc_constraint(:integration,
         message: "integration not found")
  end

  def record_failure_changeset(circuit_breaker) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    circuit_breaker
    |> change(%{
      failure_count: circuit_breaker.failure_count + 1,
      last_failure_at: now
    })
  end

  def open_changeset(circuit_breaker, opts \\ []) do
    retry_after_seconds = Keyword.get(opts, :retry_after_seconds, 60)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    next_retry = DateTime.add(now, retry_after_seconds, :second)

    circuit_breaker
    |> change(%{
      state: "open",
      opened_at: now,
      next_retry_at: next_retry
    })
  end


  def close_changeset(circuit_breaker) do
    circuit_breaker
    |> change(%{
      state: "closed",
      failure_count: 0,
      last_failure_at: nil,
      opened_at: nil,
      next_retry_at: nil
    })
  end

  def half_open_changeset(circuit_breaker) do
    circuit_breaker
    |> change(%{
      state: "half_open",
      next_retry_at: nil
    })
  end

  defp validate_state_consistency(changeset) do
    state = get_change(changeset, :state) || get_field(changeset, :state)

    case state do
      "open" ->
        changeset
        |> validate_required_when_open(:opened_at)
        |> validate_required_when_open(:next_retry_at)

      _ ->
        changeset
    end
  end

  defp validate_required_when_open(changeset, field) do
    value = get_change(changeset, field) || get_field(changeset, field)

    if value == nil do
      add_error(changeset, field, "must be present when state = 'open'")
    else
      changeset
    end
  end

  def closed?(%__MODULE__{state: "closed"}), do: true
  def closed?(%__MODULE__{}), do: false

  def open?(%__MODULE__{state: "open"}), do: true
  def open?(%__MODULE__{}), do: false

  def half_open?(%__MODULE__{state: "half_open"}), do: true
  def half_open?(%__MODULE__{}), do: false

  def ready_to_retry?(%__MODULE__{state: "open", next_retry_at: nil}), do: false
  def ready_to_retry?(%__MODULE__{state: "open", next_retry_at: next_retry}) do
    DateTime.compare(DateTime.utc_now(), next_retry) != :lt
  end
  def ready_to_retry?(%__MODULE__{}), do: false

  def should_open?(circuit_breaker, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 5)
    circuit_breaker.failure_count >= threshold
  end

  def status_message(%__MODULE__{state: "closed"}) do
    "Circuit breaker CLOSED - operating normally"
  end
  def status_message(%__MODULE__{state: "open", next_retry_at: next_retry}) do
    "Circuit breaker OPEN - blocking requests until #{format_datetime(next_retry)}"
  end
  def status_message(%__MODULE__{state: "half_open"}) do
    "Circuit breaker HALF_OPEN - testing recovery"
  end

  defp format_datetime(nil), do: "unknown"
  defp format_datetime(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
