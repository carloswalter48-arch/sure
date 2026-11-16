# frozen_string_literal: true

# Fetches dollar quotes and the CPI, stores them, and (when a family asked
# for it) copies the chosen quote into the shared USD/ARS exchange rates.
class Argentina::Sync
  CURRENT_CACHE = "argentina/dolarapi/current/v1"
  HISTORY_CACHE = "argentina/cotizaciones/%s/v1"
  CPI_CACHE = "argentina/ipc/v1"
  CURRENT_TTL = 30.minutes
  HISTORY_TTL = 12.hours

  def self.call
    new.call
  end

  def initialize(client: Argentina::MarketClient.new)
    @client = client
  end

  def call
    quote_count = store_quotes
    index_count = store_index
    rate_count = Argentina::Fx.materialize_all!
    { quotes: quote_count, indexes: index_count, rates: rate_count }
  end

  private
    attr_reader :client

    def store_quotes
      # Live rows come first. upsert_quotes! keeps the first row for a day,
      # so today's dolarapi quote wins over the historical series.
      rows = safe_fetch(CURRENT_CACHE, CURRENT_TTL, "dollar quotes") { client.current_dollar_quotes }
      Argentina::MarketClient::HISTORY_CASAS.each do |casa|
        rows.concat(safe_fetch(HISTORY_CACHE % casa, HISTORY_TTL, "#{casa} history") { client.historical_dollar_quotes(casa) })
      end
      Argentina::DollarQuote.upsert_quotes!(rows)
    end

    def store_index
      rows = safe_fetch(CPI_CACHE, HISTORY_TTL, "INDEC CPI") { client.price_index }
      Argentina::PriceIndex.upsert_indexes!(rows)
    end

    def safe_fetch(key, ttl, label)
      cached(key, ttl) { yield }
    rescue Argentina::MarketClient::Error => e
      capture("Could not fetch Argentine #{label}: #{e.message}")
      []
    end

    def cached(key, ttl)
      Rails.cache.fetch(key, expires_in: ttl) do
        value = yield
        raise Argentina::MarketClient::Error, "Empty response for #{key}" if value.blank?

        value
      end
    end

    def capture(message)
      DebugLogEntry.capture(
        category: "exchange_rates",
        level: "warn",
        message: message,
        source: self.class.name,
        provider_key: "dolarapi"
      )
      Rails.logger.warn(message)
    end
end
