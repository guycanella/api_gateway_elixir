# 🌤️ OpenWeather Integration - Setup Guide

## ✅ Arquivos Criados

1. **`openweather.ex`** - Cliente OpenWeather API
2. **`openweather_seeds.exs`** - Seeds para adicionar no banco

---

## 🔑 Obter API Key da OpenWeather

1. Acesse: https://openweathermap.org/api
2. Crie uma conta gratuita
3. Vá em **API Keys** no dashboard
4. Copie sua API Key

**Plano gratuito**: 60 chamadas/minuto, 1.000.000 chamadas/mês

---

## 📝 Adicionar ao Seeds

Abra o arquivo `apps/gateway_db/priv/repo/seeds.exs` e adicione:

```elixir
# OpenWeather Integration
{:ok, openweather} = Integrations.create_integration(%{
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

IO.puts("✅ OpenWeather integration created: #{openweather.id}")

# OpenWeather Credentials
{:ok, _openweather_cred_prod} = Integrations.create_credential(%{
  integration_id: openweather.id,
  environment: "production",
  api_key: "SUA_API_KEY_AQUI",  # ⚠️ Substitua!
  extra_credentials: %{}
})

{:ok, _openweather_cred_dev} = Integrations.create_credential(%{
  integration_id: openweather.id,
  environment: "development",
  api_key: "SUA_API_KEY_AQUI",  # ⚠️ Substitua!
  extra_credentials: %{}
})

IO.puts("✅ OpenWeather credentials created (prod + dev)")
```

---

## 🚀 Rodar Seeds

```bash
make seed
```

---

## 🧪 Testar Manualmente no IEx

```elixir
# Iniciar console
iex -S mix

# Importar módulo
alias GatewayIntegrations.OpenWeather

# Testar clima atual
OpenWeather.get_current_weather("São Paulo", "BR")
# {:ok, %{temperature: 25.3, description: "céu limpo", ...}}

# Testar previsão
OpenWeather.get_forecast("Rio de Janeiro", "BR")
# {:ok, [%{temperature: 28.5, ...}, ...]}

# Verificar logs no banco
alias GatewayDb.Logs
Logs.list_logs(limit: 5)
```

---

## 📋 Endpoints Implementados

### 1. `get_current_weather/3`
Retorna clima atual para uma cidade.

**Parâmetros**:
- `city` - Nome da cidade (ex: "São Paulo")
- `country_code` - Código do país ISO 3166 (ex: "BR") - opcional
- `opts` - Opções adicionais (timeout, etc.)

**Retorno**:
```elixir
{:ok, %{
  temperature: 25.3,      # Temperatura em °C
  feels_like: 26.1,       # Sensação térmica
  temp_min: 23.0,         # Temperatura mínima
  temp_max: 28.0,         # Temperatura máxima
  pressure: 1013,         # Pressão atmosférica (hPa)
  humidity: 65,           # Umidade (%)
  description: "céu limpo", # Descrição em português
  icon: "01d",            # Ícone do clima
  wind_speed: 3.5,        # Velocidade do vento (m/s)
  clouds: 10,             # Nebulosidade (%)
  timestamp: ~U[...]      # Timestamp da consulta
}}
```

### 2. `get_forecast/3`
Retorna previsão de 5 dias (dados a cada 3 horas).

**Parâmetros**:
- `city` - Nome da cidade
- `country_code` - Código do país (opcional)
- `opts` - Opções adicionais

**Retorno**:
```elixir
{:ok, [
  %{
    temperature: 28.5,
    feels_like: 30.2,
    humidity: 70,
    description: "chuva leve",
    icon: "10d",
    timestamp: ~U[2025-10-31 12:00:00Z]
  },
  # ... 39 mais itens (40 total = 5 dias * 8 por dia)
]}
```

---

## ⚠️ Tratamento de Erros

```elixir
# Cidade não encontrada
{:error, :not_found}

# API Key inválida
{:error, :invalid_api_key}

# Integração não configurada
{:error, :integration_not_configured}

# Credenciais não encontradas
{:error, :credentials_not_found}

# Parâmetros inválidos
{:error, :invalid_params}

# Timeout ou erro de conexão
{:error, :timeout}
{:error, :connection_refused}

# Circuit breaker aberto
{:error, :circuit_breaker_open}
```

---

## 🛡️ Integração com Circuit Breaker

A integração já está protegida pelo Circuit Breaker através do `HttpClient`:
- ✅ Abre após 5 falhas consecutivas
- ✅ Bloqueia requisições quando aberto
- ✅ Fecha automaticamente após sucesso

---

## 📊 Features Implementadas

- ✅ Clima atual por cidade
- ✅ Previsão de 5 dias
- ✅ Temperatura em Celsius
- ✅ Descrições em português
- ✅ Normalização de respostas
- ✅ Tratamento de erros
- ✅ Integração com Circuit Breaker
- ✅ Logging automático no banco
- ✅ Suporte a country code

---

## 🎯 Próximos Passos

1. ✅ Criar testes unitários
2. ✅ Testar com API real
3. ✅ Verificar Circuit Breaker funcionando