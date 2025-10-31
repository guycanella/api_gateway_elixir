alias GatewayDb.Repo
alias GatewayDb.{Integration, IntegrationCredential, RequestLog, CircuitBreakerState}
alias GatewayDb.Integrations

require Logger

Logger.info("🌱 Starting seeds...")

# ==========================================
# CLEANUP - Delete existing data
# ==========================================

Repo.delete_all(CircuitBreakerState)
Repo.delete_all(RequestLog)
Repo.delete_all(IntegrationCredential)
Repo.delete_all(Integration)

Logger.info("🧹 Cleaned existing data")

# ==========================================
# INTEGRATIONS - Create integrations
# ==========================================

Logger.info("📦 Creating integrations...")

stripe = Repo.insert!(%Integration{
  name: "stripe",
  type: "payment",
  base_url: "https://api.stripe.com",
  is_active: true,
  config: %{
    "timeout_ms" => 5000,
    "rate_limit_per_minute" => 100,
    "retry_attempts" => 3
  }
})

sendgrid = Repo.insert!(%Integration{
  name: "sendgrid",
  type: "email",
  base_url: "https://api.sendgrid.com",
  is_active: true,
  config: %{
    "timeout_ms" => 3000,
    "rate_limit_per_minute" => 50
  }
})

twilio = Repo.insert!(%Integration{
  name: "twilio",
  type: "sms",
  base_url: "https://api.twilio.com",
  is_active: true,
  config: %{
    "timeout_ms" => 4000,
    "rate_limit_per_minute" => 30
  }
})

viacep = Repo.insert!(%Integration{
  name: "viacep",
  type: "other",
  base_url: "https://viacep.com.br/ws",
  is_active: true,
  config: %{
    "timeout_ms" => 2000,
    "rate_limit_per_minute" => 200
  }
})

openweather = Repo.insert!(%Integration{
  name: "openweather",
  type: "other",
  base_url: "https://api.openweathermap.org/data/2.5",
  is_active: true,
  config: %{
    "timeout_ms" => 5000,
    "rate_limit_per_minute" => 60,
    "units" => "metric",
    "language" => "pt_br"
  }
})

integrations = [stripe, sendgrid, twilio, viacep, openweather]

Logger.info("✅ Created #{length(integrations)} integrations")

# ==========================================
# CREDENTIALS - Create encrypted credentials
# ==========================================

Logger.info("🔐 Creating credentials...")

credentials_data = [
  # Stripe
  {stripe, "production", "sk_live_test_fake_key_abc123", "whsec_fake_secret_xyz789"},
  {stripe, "development", "sk_test_fake_key_dev456", "whsec_fake_secret_dev123"},

  # SendGrid
  {sendgrid, "production", "SG.fake_key_production_xyz", "fake_secret_prod_789"},
  {sendgrid, "development", "SG.fake_key_development_abc", "fake_secret_dev_456"},

  # Twilio
  {twilio, "production", "AC_fake_account_sid_prod", "fake_auth_token_prod_123"},
  {twilio, "development", "AC_fake_account_sid_dev", "fake_auth_token_dev_456"},

  # ViaCEP (public API - no real key needed)
  {viacep, "production", "public_api_no_key", "no_secret_needed"},
  {viacep, "development", "public_api_no_key", "no_secret_needed"},

  # OpenWeather - ⚠️ Replace with your actual API key!
  {openweather, "production", "7120f71d86d3b8b11f5bad7b5cc8765b", "no_secret_needed"},
  {openweather, "development", "7120f71d86d3b8b11f5bad7b5cc8765b", "no_secret_needed"}
]

credentials = Enum.map(credentials_data, fn {integration, env, key, secret} ->
  expires_at = if env == "production" do
    DateTime.utc_now() |> DateTime.add(365, :day) |> DateTime.truncate(:second)
  else
    nil
  end

  {:ok, credential} = Integrations.add_credential(integration, %{
    environment: env,
    api_key: key,
    api_secret: secret,
    expires_at: expires_at,
    extra_credentials: %{
      "created_by" => "seeds",
      "notes" => "Fake credentials for #{env} environment"
    }
  })

  credential
end)

Logger.info("✅ Created #{length(credentials)} credentials")

# ==========================================
# REQUEST LOGS - Create fake request logs
# ==========================================

Logger.info("📝 Creating request logs...")

defmodule SeedHelper do
  def create_logs_for_integration(integration, count) do
    methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    status_codes = [200, 201, 204, 400, 401, 404, 422, 500, 502, 503]

    base_time = DateTime.utc_now() |> DateTime.add(-30, :day)

    Enum.map(1..count, fn i ->
      method = Enum.random(methods)
      status = Enum.random(status_codes)
      duration = Faker.random_between(50, 3000)

      {status, error_msg} = if Faker.random_between(1, 10) <= 2 do
        {Enum.random([500, 502, 503, 504]), Faker.Lorem.sentence(5..10)}
      else
        {status, nil}
      end

      timestamp = DateTime.add(base_time, i * 3600, :second) |> DateTime.truncate(:second)

      %{
        integration_id: integration.id,
        request_id: "req_#{integration.name}_#{Faker.UUID.v4() |> String.slice(0..7)}",
        method: method,
        endpoint: generate_endpoint(integration.name, method),
        request_headers: generate_headers(),
        request_body: generate_request_body(method, integration.type),
        response_status: status,
        response_headers: %{"content-type" => "application/json"},
        response_body: generate_response_body(status, integration.type),
        duration_ms: duration,
        error_message: error_msg,
        inserted_at: timestamp,
      }
    end)
  end

  defp generate_endpoint("stripe", "POST"), do: "/v1/charges"
  defp generate_endpoint("stripe", "GET"), do: "/v1/charges/#{Faker.random_between(1000, 9999)}"
  defp generate_endpoint("stripe", _), do: "/v1/customers"

  defp generate_endpoint("sendgrid", "POST"), do: "/v3/mail/send"
  defp generate_endpoint("sendgrid", "GET"), do: "/v3/templates"
  defp generate_endpoint("sendgrid", _), do: "/v3/stats"

  defp generate_endpoint("twilio", "POST"), do: "/2010-04-01/Accounts/#{Faker.UUID.v4() |> String.slice(0..10)}/Messages.json"
  defp generate_endpoint("twilio", "GET"), do: "/2010-04-01/Accounts/#{Faker.UUID.v4() |> String.slice(0..10)}/Messages"
  defp generate_endpoint("twilio", _), do: "/2010-04-01/Accounts"

  defp generate_endpoint("viacep", _), do: "/#{Faker.random_between(10000, 99999)}/json"

  defp generate_endpoint("openweather", _), do: "/data/2.5/weather?q=#{Faker.Address.city()}"

  defp generate_headers do
    user_agents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      "PostmanRuntime/7.32.2",
      "curl/7.84.0"
    ]

    %{
      "content-type" => "application/json",
      "user-agent" => Enum.random(user_agents),
      "x-request-id" => Faker.UUID.v4()
    }
  end

  defp generate_request_body("GET", _), do: %{}
  defp generate_request_body("DELETE", _), do: %{}

  defp generate_request_body(_, "payment") do
    %{
      "amount" => Faker.random_between(1000, 100000),
      "currency" => "usd",
      "description" => Faker.Lorem.sentence(3..6)
    }
  end

  defp generate_request_body(_, "email") do
    %{
      "to" => Faker.Internet.email(),
      "from" => "noreply@example.com",
      "subject" => Faker.Lorem.sentence(3..5),
      "content" => Faker.Lorem.paragraph()
    }
  end

  defp generate_request_body(_, "sms") do
    %{
      "to" => "+55#{Faker.random_between(11000000000, 11999999999)}",
      "from" => "+15555555555",
      "body" => Faker.Lorem.sentence(5..10)
    }
  end

  defp generate_request_body(_, _), do: %{}

  defp generate_response_body(status, _type) when status >= 400 do
    %{
      "error" => %{
        "code" => "error_#{status}",
        "message" => Faker.Lorem.sentence(5..10)
      }
    }
  end

  defp generate_response_body(_, "payment") do
    %{
      "id" => "ch_#{Faker.UUID.v4() |> String.slice(0..15)}",
      "status" => "succeeded",
      "amount" => Faker.random_between(1000, 100000)
    }
  end

  defp generate_response_body(_, "email") do
    %{
      "message_id" => Faker.UUID.v4(),
      "status" => "sent"
    }
  end

  defp generate_response_body(_, "sms") do
    %{
      "sid" => "SM#{Faker.UUID.v4() |> String.slice(0..20)}",
      "status" => "sent"
    }
  end

  defp generate_response_body(_, "other") do
    %{
      "cep" => "#{Faker.random_between(10000, 99999)}-000",
      "logradouro" => Faker.Address.street_name(),
      "bairro" => Faker.Address.secondary_address(),
      "localidade" => Faker.Address.city(),
      "uf" => "SP",
      "temp" => Faker.random_between(15, 35),
      "humidity" => Faker.random_between(30, 90),
      "description" => Enum.random(["clear sky", "few clouds", "scattered clouds", "rain"])
    }
  end
end

logs_per_integration = [
  {stripe, 20},
  {sendgrid, 15},
  {twilio, 15},
  {viacep, 15},
  {openweather, 10}
]

all_logs = Enum.flat_map(logs_per_integration, fn {integration, count} ->
  SeedHelper.create_logs_for_integration(integration, count)
end)

Enum.chunk_every(all_logs, 50)
|> Enum.each(fn chunk ->
  Repo.insert_all(RequestLog, chunk)
end)

Logger.info("✅ Created #{length(all_logs)} request logs")

# ==========================================
# CIRCUIT BREAKER STATES - Create states
# ==========================================

Logger.info("🚦 Creating circuit breaker states...")

Repo.insert!(%CircuitBreakerState{
  integration_id: stripe.id,
  state: "closed",
  failure_count: 0
})

Repo.insert!(%CircuitBreakerState{
  integration_id: sendgrid.id,
  state: "closed",
  failure_count: 2,
  last_failure_at: DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
})

now = DateTime.utc_now() |> DateTime.truncate(:second)
Repo.insert!(%CircuitBreakerState{
  integration_id: twilio.id,
  state: "open",
  failure_count: 5,
  last_failure_at: now,
  opened_at: now,
  next_retry_at: DateTime.add(now, 300, :second)
})

Repo.insert!(%CircuitBreakerState{
  integration_id: viacep.id,
  state: "half_open",
  failure_count: 5,
  last_failure_at: DateTime.utc_now() |> DateTime.add(-600, :second) |> DateTime.truncate(:second),
  opened_at: DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)
})

Repo.insert!(%CircuitBreakerState{
  integration_id: openweather.id,
  state: "closed",
  failure_count: 0
})

Logger.info("✅ Created 5 circuit breaker states")

# ==========================================
# SUMMARY
# ==========================================

Logger.info("""

🎉 Seeds completed successfully!

Summary:
  📦 Integrations: #{Repo.aggregate(Integration, :count, :id)}
  🔐 Credentials: #{Repo.aggregate(IntegrationCredential, :count, :id)}
  📝 Request Logs: #{Repo.aggregate(RequestLog, :count, :id)}
  🚦 Circuit Breakers: #{Repo.aggregate(CircuitBreakerState, :count, :id)}

Integrations created:
  ✅ stripe (payment) - Active
  ✅ sendgrid (email) - Active
  ✅ twilio (sms) - Active
  ✅ viacep (other) - Active
  ✅ openweather (other) - Active

Circuit Breaker States:
  🟢 stripe: closed (healthy)
  🟢 sendgrid: closed (2 failures)
  🔴 twilio: open (failing - 5 failures)
  🟡 viacep: half_open (testing recovery)
  🟢 openweather: closed (healthy)

⚠️  Important:
  • Replace OpenWeather API key in credentials before testing!
  • Get free key at: https://openweathermap.org/api

Next steps:
  • Query database: mix ecto.psql
  • Run app: mix phx.server
  • Test integrations in IEx!
""")
