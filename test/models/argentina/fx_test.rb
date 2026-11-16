# frozen_string_literal: true

require "test_helper"

class Argentina::FxTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @family.update!(argentina_fx_enabled: true, argentina_fx_kind: "blue")
    Argentina::DollarQuote.create!(kind: "blue", quoted_on: Date.new(2026, 11, 15), buy_rate: 1555, sell_rate: 1575, source: "dolarapi")
    Argentina::DollarQuote.create!(kind: "oficial", quoted_on: Date.new(2026, 11, 15), buy_rate: 1520, sell_rate: 1400, source: "dolarapi")
    Argentina::DollarQuote.create!(kind: "bolsa", quoted_on: Date.new(2026, 11, 15), buy_rate: "1575.5", sell_rate: "1580.9", source: "dolarapi")
  end

  test "converts with the family's sell quote" do
    assert_equal BigDecimal("1575"), Argentina::Fx.pesos_per_dollar(kind: "blue", date: Date.new(2026, 11, 15))
    assert_equal BigDecimal("1575"), Argentina::Fx.multiplier(from: "USD", to: "ARS", kind: "blue", date: Date.new(2026, 11, 15))

    usd = Argentina::Fx.multiplier(from: "ARS", to: "USD", kind: "blue", date: Date.new(2026, 11, 15))
    assert_in_delta BigDecimal("1") / 1575, usd, 0.000_000_1

    @family.update!(argentina_fx_kind: "mep")
    assert_equal BigDecimal("1580.9"), Argentina::Fx.pesos_per_dollar(kind: @family.argentina_fx_kind, date: Date.new(2026, 11, 16))
  end

  test "materialize writes both directions from the enabled kind" do
    count = Argentina::Fx.materialize_all!
    assert_equal 1, count

    usd_to_ars = ExchangeRate.find_by!(from_currency: "USD", to_currency: "ARS", date: Date.new(2026, 11, 15))
    ars_to_usd = ExchangeRate.find_by!(from_currency: "ARS", to_currency: "USD", date: Date.new(2026, 11, 15))
    assert_equal BigDecimal("1575"), usd_to_ars.rate
    assert_in_delta BigDecimal("1") / 1575, ars_to_usd.rate, 0.000_000_1

    @family.update!(argentina_fx_kind: "oficial")
    Argentina::Fx.materialize_all!
    assert_equal BigDecimal("1400"), usd_to_ars.reload.rate
  end

  test "a missing rate lookup stores the Argentine quote instead of calling the provider" do
    ExchangeRate.where(from_currency: %w[USD ARS], to_currency: %w[USD ARS], date: Date.new(2026, 11, 15)).delete_all

    record = ExchangeRate.find_or_fetch_rate(from: "USD", to: "ARS", date: Date.new(2026, 11, 15), cache: true)

    assert_equal BigDecimal("1575"), record.rate
    assert_equal Date.new(2026, 11, 15), record.date
  end

  test "the exchange rate importer delegates ARS pairs while the setting is on" do
    importer = ExchangeRate::Importer.new(
      exchange_rate_provider: Object.new,
      from: "USD",
      to: "ARS",
      start_date: Date.new(2026, 11, 1),
      end_date: Date.new(2026, 11, 30)
    )

    assert_equal 1, importer.import_provider_rates
    assert_equal BigDecimal("1575"), ExchangeRate.find_by!(from_currency: "USD", to_currency: "ARS", date: Date.new(2026, 11, 15)).rate
  end
end
