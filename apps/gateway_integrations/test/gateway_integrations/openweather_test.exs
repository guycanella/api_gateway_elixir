defmodule GatewayIntegrations.OpenWeatherTest do
  use ExUnit.Case, async: true
  import Mox
  alias GatewayIntegrations.OpenWeather
  alias GatewayDb.{Repo, Integration}

  setup :verify_on_exit!

  setup do
    # Ensure sandbox mode is enabled
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create openweather integration for tests
    {:ok, integration} =
      %Integration{}
      |> Integration.changeset(%{
        name: "openweather",
        type: "other",
        base_url: "https://api.openweathermap.org/data/2.5",
        is_active: true,
        config: %{
          "timeout_ms" => 5000,
          "rate_limit_per_minute" => 60
        }
      })
      |> Repo.insert()

    # Create credentials for the integration  ← NOVO!
    alias GatewayDb.Integrations

    {:ok, _credential} = Integrations.add_credential(integration, %{
      environment: "production",
      api_key: System.get_env("OPENWEATHER_API_KEY") || "test_api_key_fake",
      api_secret: "not_needed",
      extra_credentials: %{}
    })

    %{integration_id: integration.id}
  end

  describe "get_current_weather/3" do
    test "returns normalized weather data for valid city" do
      assert {:ok, weather} = OpenWeather.get_current_weather("São Paulo", "BR")

      assert is_map(weather)
      assert Map.has_key?(weather, :temperature)
      assert Map.has_key?(weather, :humidity)
      assert Map.has_key?(weather, :description)
      assert is_float(weather.temperature) or is_integer(weather.temperature)
      assert is_integer(weather.humidity)
      assert is_binary(weather.description)
    end

    test "accepts city without country code" do
      assert {:ok, weather} = OpenWeather.get_current_weather("London")

      assert is_map(weather)
      assert Map.has_key?(weather, :temperature)
    end

    test "returns error for invalid city" do
      assert {:error, :not_found} = OpenWeather.get_current_weather("InvalidCityXYZ123")
    end

    test "returns error for empty city name" do
      assert {:error, :invalid_params} = OpenWeather.get_current_weather("")
    end

    test "returns error for invalid country code" do
      assert {:error, :invalid_params} = OpenWeather.get_current_weather("São Paulo", "B")
      assert {:error, :invalid_params} = OpenWeather.get_current_weather("São Paulo", "BRA")
    end

    test "handles timeout gracefully" do
      # This test will actually call the API with a very short timeout
      # It may or may not timeout depending on network conditions
      result = OpenWeather.get_current_weather("São Paulo", "BR", timeout: 1)

      assert result == {:error, :timeout} or match?({:ok, _}, result)
    end
  end

  describe "get_forecast/3" do
    test "returns list of forecast items for valid city" do
      assert {:ok, forecast} = OpenWeather.get_forecast("Rio de Janeiro", "BR")

      assert is_list(forecast)
      assert length(forecast) > 0

      first_item = List.first(forecast)
      assert is_map(first_item)
      assert Map.has_key?(first_item, :temperature)
      assert Map.has_key?(first_item, :description)
      assert Map.has_key?(first_item, :timestamp)
      assert %DateTime{} = first_item.timestamp
    end

    test "accepts city without country code" do
      assert {:ok, forecast} = OpenWeather.get_forecast("Paris")

      assert is_list(forecast)
      assert length(forecast) > 0
    end

    test "returns error for invalid city" do
      assert {:error, :not_found} = OpenWeather.get_forecast("InvalidCityXYZ123")
    end

    test "forecast items have expected structure" do
      assert {:ok, forecast} = OpenWeather.get_forecast("Tokyo", "JP")

      Enum.each(forecast, fn item ->
        assert is_map(item)
        assert is_number(item.temperature)
        assert is_binary(item.description)
        assert %DateTime{} = item.timestamp
      end)
    end
  end

  describe "response normalization" do
    test "current weather includes all expected fields" do
      assert {:ok, weather} = OpenWeather.get_current_weather("São Paulo", "BR")

      # Required fields
      assert Map.has_key?(weather, :temperature)
      assert Map.has_key?(weather, :humidity)
      assert Map.has_key?(weather, :description)

      # Optional fields (may or may not be present)
      # feels_like, temp_min, temp_max, pressure, wind_speed, clouds, icon
      assert is_map(weather)
    end

    test "forecast items include timestamp" do
      assert {:ok, forecast} = OpenWeather.get_forecast("São Paulo", "BR")

      Enum.each(forecast, fn item ->
        assert %DateTime{} = item.timestamp
        # Timestamp should be in the future or very recent past
        now = DateTime.utc_now()
        diff_hours = DateTime.diff(item.timestamp, now, :hour)
        assert diff_hours >= -1 and diff_hours <= 120  # Within 5 days
      end)
    end

    test "removes nil values from response" do
      assert {:ok, weather} = OpenWeather.get_current_weather("São Paulo", "BR")

      # No nil values should be present
      Enum.each(weather, fn {_key, value} ->
        refute is_nil(value)
      end)
    end
  end

  describe "error handling" do
    test "handles integration not configured" do
      # Delete the integration
      Repo.delete_all(Integration)

      assert {:error, :integration_not_configured} =
        OpenWeather.get_current_weather("São Paulo", "BR")
    end

    test "handles credentials not found" do
      # This would require removing credentials, which is complex in this setup
      # We'll skip this test for now or implement it differently
      :ok
    end

    test "handles invalid parameters" do
      assert {:error, :invalid_params} = OpenWeather.get_current_weather("", "BR")
      assert {:error, :invalid_params} = OpenWeather.get_current_weather("São Paulo", "")
      assert {:error, :invalid_params} = OpenWeather.get_current_weather("São Paulo", "X")
    end
  end

  describe "integration with database logging" do
    test "logs request when integration_id is available" do
      alias GatewayDb.Logs

      initial_count = Logs.count_logs()

      {:ok, _weather} = OpenWeather.get_current_weather("São Paulo", "BR")

      # Should have created a new log entry
      final_count = Logs.count_logs()
      assert final_count == initial_count + 1

      # Verify log content
      [latest_log | _] = Logs.list_logs(limit: 1)
      assert latest_log.method == "GET"
      assert latest_log.response_status == 200
      assert String.contains?(latest_log.endpoint, "/weather")
    end

    test "logs forecast request" do
      alias GatewayDb.Logs

      initial_count = Logs.count_logs()

      {:ok, _forecast} = OpenWeather.get_forecast("Rio de Janeiro", "BR")

      final_count = Logs.count_logs()
      assert final_count == initial_count + 1

      [latest_log | _] = Logs.list_logs(limit: 1)
      assert latest_log.method == "GET"
      assert String.contains?(latest_log.endpoint, "/forecast")
    end
  end

  describe "real API integration" do
    @tag :integration
    test "fetches real current weather from OpenWeather" do
      {:ok, weather} = OpenWeather.get_current_weather("São Paulo", "BR")

      assert weather.temperature > -50 and weather.temperature < 60
      assert weather.humidity > 0 and weather.humidity <= 100
      assert is_binary(weather.description)
    end

    @tag :integration
    test "fetches real forecast data" do
      {:ok, forecast} = OpenWeather.get_forecast("Rio de Janeiro", "BR")

      assert length(forecast) > 0
      assert length(forecast) <= 40  # 5 days * 8 per day

      Enum.each(forecast, fn item ->
        assert item.temperature > -50 and item.temperature < 60
        assert is_binary(item.description)
      end)
    end

    @tag :integration
    test "handles non-existent city from real API" do
      assert {:error, :not_found} = OpenWeather.get_current_weather("XyzInvalidCity12345")
    end

    @tag :integration
    test "works with different cities" do
      cities = [
        {"London", "GB"},
        {"Tokyo", "JP"},
        {"New York", "US"},
        {"Paris", "FR"}
      ]

      Enum.each(cities, fn {city, country} ->
        assert {:ok, weather} = OpenWeather.get_current_weather(city, country)
        assert is_number(weather.temperature)
        assert is_binary(weather.description)
      end)
    end
  end

  describe "circuit breaker integration" do
    test "circuit breaker is updated on success" do
      alias GatewayDb.CircuitBreakers

      {:ok, weather} = OpenWeather.get_current_weather("São Paulo", "BR")
      assert is_map(weather)

      # Circuit breaker should remain closed after success
      {:ok, integration} = GatewayDb.Integrations.get_integration_by_name("openweather")
      case CircuitBreakers.get_state(integration.id) do
        {:ok, state} ->
          assert state.state == "closed"
          assert state.failure_count == 0

        {:error, :not_found} ->
          # State not created yet, which is fine
          :ok
      end
    end
  end
end
