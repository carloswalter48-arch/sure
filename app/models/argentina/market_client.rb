# frozen_string_literal: true

# Free public Argentine market data. No API key.
#
# Dollar quotes: https://dolarapi.com/v1/dolares (live) and
# https://api.argentinadatos.com/v1/cotizaciones/dolares/:casa (history).
# CPI: INDEC IPC nivel general, base December 2016, via datos.gob.ar.
class Argentina::MarketClient
  extend SslConfigurable

  class Error < StandardError; end

  CURRENT_QUOTES_URL = "https://dolarapi.com/v1/dolares"
  HISTORY_URL = "https://api.argentinadatos.com/v1/cotizaciones/dolares"
  CPI_URL = "https://apis.datos.gob.ar/series/api/series/"
  CPI_SERIES = "148.3_INIVELNAL_DICI_M_26"
  HISTORY_CASAS = %w[oficial blue bolsa].freeze
  BUENOS_AIRES = "America/Argentina/Buenos_Aires"

  def current_dollar_quotes
    parse_current_quotes(get_json(CURRENT_QUOTES_URL))
  end

  def historical_dollar_quotes(casa)
    casa = casa.to_s
    raise Error, "Unknown dollar casa #{casa}" unless HISTORY_CASAS.include?(casa)

    parse_historical_quotes(get_json("#{HISTORY_URL}/#{casa}"), source: "argentinadatos")
  end

  def price_index
    parse_price_index(get_json(CPI_URL, ids: CPI_SERIES, format: "json", limit: 5000))
  end

  def parse_current_quotes(payload)
    rows = payload.is_a?(Array) ? payload : []
    rows.filter_map { |row| quote_row(row, date_key: "fechaActualizacion", source: "dolarapi") }
  end

  def parse_historical_quotes(payload, source:)
    rows = payload.is_a?(Array) ? payload : []
    rows.filter_map { |row| quote_row(row, date_key: "fecha", source: source) }
  end

  def parse_price_index(payload)
    data = payload.is_a?(Hash) ? payload["data"] : nil
    return [] unless data.is_a?(Array)

    data.filter_map do |point|
      next unless point.is_a?(Array) && point.size >= 2

      period = parse_date(point[0])
      value = decimal(point[1])
      next if period.nil? || value.nil? || !value.positive?

      { period_on: period.beginning_of_month, index_value: value, source: "indec" }
    end
  end

  private
    def quote_row(row, date_key:, source:)
      return nil unless row.is_a?(Hash)

      kind = row["casa"].to_s.downcase
      return nil unless Argentina::DollarQuote::KINDS.include?(kind)

      buy = decimal(row["compra"])
      sell = decimal(row["venta"])
      return nil if buy.nil? || sell.nil? || !buy.positive? || !sell.positive?

      quoted_on = parse_quoted_on(row[date_key])
      return nil if quoted_on.nil?

      { kind: kind, quoted_on: quoted_on, buy_rate: buy, sell_rate: sell, source: source }
    end

    def parse_quoted_on(value)
      text = value.to_s
      return nil if text.blank?
      return Date.iso8601(text) if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Time.iso8601(text).in_time_zone(BUENOS_AIRES).to_date
    rescue ArgumentError, TypeError
      parse_date(text)
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error, TypeError
      nil
    end

    def decimal(value)
      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def get_json(url, params = {})
      response = connection.get(url) do |req|
        params.each { |key, value| req.params[key.to_s] = value }
      end
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON from #{url}: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "Request failed for #{url}: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(ssl: self.class.faraday_ssl_options) do |faraday|
        faraday.options.open_timeout = 5
        faraday.options.timeout = 30
        faraday.request :retry, {
          max: 2,
          interval: 0.5,
          backoff_factor: 2,
          exceptions: Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS + [ Faraday::ConnectionFailed ]
        }
        faraday.response :raise_error
        faraday.headers["Accept"] = "application/json"
        faraday.headers["User-Agent"] = "sure-argentina"
      end
    end
end
