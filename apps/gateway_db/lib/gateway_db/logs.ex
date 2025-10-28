defmodule GatewayDb.Logs do
  import Ecto.Query, warn: false
  alias GatewayDb.Repo
  alias GatewayDb.RequestLog

  def create_log(attrs \\ %{}) do
    %RequestLog{}
    |> RequestLog.changeset(attrs)
    |> Repo.insert()
  end

  def get_log(id) do
    case Repo.get(RequestLog, id) do
      nil -> {:error, :not_found}
      log -> {:ok, log}
    end
  end

  def get_log!(id) do
    Repo.get!(RequestLog, id)
  end

  def get_log_by_request_id(request_id) do
    case Repo.get_by(RequestLog, request_id: request_id) do
      nil -> {:error, :not_found}
      log -> {:ok, log}
    end
  end

  def list_logs do
    RequestLog
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  def list_logs(opts) when is_list(opts) do
    {filters, options} = split_filters_and_options(opts)

    RequestLog
    |> apply_filters(filters)
    |> apply_options(options)
    |> Repo.all()
  end

  def list_logs_by_integration(integration_id, opts \\ []) do
    list_logs([{:integration_id, integration_id} | opts])
  end

  def list_recent_errors(opts \\ []) do
    list_logs([{:has_error, true} | opts])
  end

  def list_slow_requests(threshold_ms, opts \\ []) do
    list_logs([{:min_duration, threshold_ms} | opts])
  end

  def list_logs_by_period(from, to, opts \\ []) do
    list_logs([{:from, from}, {:to, to} | opts])
  end

  def count_logs(filters \\ []) do
    RequestLog
    |> apply_filters(filters)
    |> select([l], count(l.id))
    |> Repo.one()
  end

  def average_duration(filters \\ []) do
    RequestLog
    |> apply_filters(filters)
    |> select([l], avg(l.duration_ms))
    |> Repo.one()
    |> case do
      nil -> 0.0
      value -> Decimal.to_float(value)
    end
  end

  def error_rate(filters \\ []) do
    total = count_logs(filters)

    if total == 0 do
      0.0
    else
      errors = count_logs([{:has_error, true} | filters])
      (errors / total) * 100.0
    end
  end

  def count_by_status(filters \\ []) do
    RequestLog
    |> apply_filters(filters)
    |> group_by([l], l.response_status)
    |> select([l], {l.response_status, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  def count_by_method(filters \\ []) do
    RequestLog
    |> apply_filters(filters)
    |> group_by([l], l.method)
    |> select([l], {l.method, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp split_filters_and_options(opts) do
    option_keys = [:limit, :offset, :order_by, :order]
    {options, filters} = Keyword.split(opts, option_keys)
    {filters, options}
  end

  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:integration_id, value} | rest]) do
    query
    |> where([l], l.integration_id == ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:method, value} | rest]) do
    query
    |> where([l], l.method == ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:status, value} | rest]) do
    query
    |> where([l], l.response_status == ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:status_range, first..last} | rest]) do
    query
    |> where([l], l.response_status >= ^first and l.response_status <= ^last)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:min_duration, value} | rest]) do
    query
    |> where([l], l.duration_ms >= ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:max_duration, value} | rest]) do
    query
    |> where([l], l.duration_ms <= ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:from, value} | rest]) do
    query
    |> where([l], l.inserted_at >= ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:to, value} | rest]) do
    query
    |> where([l], l.inserted_at <= ^value)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:has_error, true} | rest]) do
    query
    |> where([l], not is_nil(l.error_message))
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:has_error, false} | rest]) do
    query
    |> where([l], is_nil(l.error_message))
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_unknown | rest]) do
    apply_filters(query, rest)
  end

  defp apply_options(query, []), do: query |> order_by([l], desc: l.inserted_at)

  defp apply_options(query, opts) do
    query
    |> apply_limit(opts[:limit])
    |> apply_offset(opts[:offset])
    |> apply_order(opts[:order_by], opts[:order])
  end

  defp apply_limit(query, nil), do: limit(query, 100)
  defp apply_limit(query, value), do: limit(query, ^value)

  defp apply_offset(query, nil), do: query
  defp apply_offset(query, value), do: offset(query, ^value)

  defp apply_order(query, nil, _), do: order_by(query, [l], desc: l.inserted_at)
  defp apply_order(query, field, :asc), do: order_by(query, [l], asc: field(l, ^field))
  defp apply_order(query, field, :desc), do: order_by(query, [l], desc: field(l, ^field))
  defp apply_order(query, field, _), do: order_by(query, [l], desc: field(l, ^field))
end
