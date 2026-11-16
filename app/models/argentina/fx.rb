# frozen_string_literal: true

# Pesos-per-dollar quotes (sell / venta) and the family's chosen casa.
# Sure stores one USD/ARS rate per day. When a family turns this on, that
# series is rewritten from the chosen quote so reports, balances and
# Money#exchange_to convert with it. Other currency pairs stay with the
# configured exchange-rate provider.
class Argentina::Fx
  KINDS = %w[oficial blue mep].freeze
  CASAS = {
    "oficial" => "oficial",
    "blue" => "blue",
    "mep" => "bolsa"
  }.freeze

  class << self
    def casa_for(kind)
      CASAS.fetch(kind.to_s, "oficial")
    end

    def ars_usd_pair?(from, to)
      [ from, to ].map { |code| code.to_s.upcase }.sort == %w[ARS USD]
    end

    def enabled_for_install?
      Family.where(argentina_fx_enabled: true).exists?
    end

    # The quote written into exchange_rates. One series is shared, so a
    # multi-family install uses the kind chosen most often by families that
    # turned the setting on.
    def installation_kind
      scope = Family.where(argentina_fx_enabled: true)
      scope.group(:argentina_fx_kind).order(Arel.sql("COUNT(*) DESC")).limit(1).pick(:argentina_fx_kind).presence || "oficial"
    end

    def handles_pair?(from, to)
      ars_usd_pair?(from, to) && enabled_for_install? && Argentina::DollarQuote.for_kind(casa_for(installation_kind)).exists?
    end

    # Pesos per 1 USD for the family's kind, on or near `date`. Nil when no
    # quote is stored. Does not call the network.
    def pesos_per_dollar(kind:, date: Date.current)
      quote = Argentina::DollarQuote.on_or_near(casa_for(kind), date)
      quote&.sell_rate
    end

    # Multiplier that converts `from` into `to` (ARS or USD only).
    def multiplier(from:, to:, kind:, date: Date.current)
      from_code = from.to_s.upcase
      to_code = to.to_s.upcase
      return 1 if from_code == to_code

      pesos = pesos_per_dollar(kind: kind, date: date)
      return nil unless pesos&.positive?

      case [ from_code, to_code ]
      when %w[USD ARS] then pesos.to_d
      when %w[ARS USD] then (1.to_d / pesos.to_d)
      end
    end

    def materialize_date!(from:, to:, date:)
      return nil unless handles_pair?(from, to)

      quote = Argentina::DollarQuote.on_or_near(casa_for(installation_kind), date)
      return nil unless quote

      write_rate(from: from, to: to, date: quote.quoted_on, pesos: quote.sell_rate)
    end

    # Rewrites the stored USD/ARS and ARS/USD rows from the installation kind.
    # Returns the number of quote dates written.
    def materialize_all!
      return 0 unless enabled_for_install?

      kind = casa_for(installation_kind)
      rows = Argentina::DollarQuote.for_kind(kind).pluck(:quoted_on, :sell_rate)
      write_rates(rows)
      rows.size
    end

    # Called by ExchangeRate::Importer for an ARS/USD range so the usual
    # provider does not overwrite the chosen Argentine quote.
    def materialize_exchange_rates(from:, to:, start_date:, end_date:)
      return 0 unless handles_pair?(from, to)

      kind = casa_for(installation_kind)
      rows = Argentina::DollarQuote.for_kind(kind).where(quoted_on: start_date..end_date).pluck(:quoted_on, :sell_rate)
      write_rates(rows)
      rows.size
    end

    def snapshot_for(family)
      quote = Argentina::DollarQuote.latest_for(casa_for(family.argentina_fx_kind))
      { quote: quote, index: Argentina::PriceIndex.latest }
    end

    private
      def write_rate(from:, to:, date:, pesos:)
        write_rates([ [ date, pesos ] ])
        from_code = from.to_s.upcase
        to_code = to.to_s.upcase
        ExchangeRate.find_by(from_currency: from_code, to_currency: to_code, date: date)
      end

      # Each row is [date, pesos per dollar]. Both directions are stored.
      def write_rates(rows)
        now = Time.current
        payload = rows.flat_map do |date, pesos|
          sell = pesos.to_d
          next [] unless sell.positive?

          buy = 1.to_d / sell
          [
            { from_currency: "USD", to_currency: "ARS", date: date, rate: sell, created_at: now, updated_at: now },
            { from_currency: "ARS", to_currency: "USD", date: date, rate: buy, created_at: now, updated_at: now }
          ]
        end
        return if payload.empty?

        payload.each_slice(500) do |batch|
          ExchangeRate.upsert_all(batch, unique_by: %i[from_currency to_currency date])
        end
      end
  end
end
