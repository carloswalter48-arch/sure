# frozen_string_literal: true

require "test_helper"

class Argentina::SyncTest < ActiveSupport::TestCase
  test "stores quotes and the CPI, then rewrites USD/ARS when a family opted in" do
    families(:empty).update!(argentina_fx_enabled: true, argentina_fx_kind: "blue", country: "AR", currency: "ARS")

    client = Struct.new(:current, :history, :index) do
      def current_dollar_quotes = current
      def historical_dollar_quotes(_casa) = history
      def price_index = index
    end.new(
      [ { kind: "blue", quoted_on: Date.new(2026, 11, 15), buy_rate: "1550", sell_rate: "1600", source: "dolarapi" } ],
      [ { kind: "blue", quoted_on: Date.new(2026, 11, 14), buy_rate: "1500", sell_rate: "1540", source: "argentinadatos" } ],
      [ { period_on: Date.new(2026, 10, 1), index_value: "100", source: "indec" } ]
    )

    result = Argentina::Sync.new(client: client).call

    assert_equal 2, Argentina::DollarQuote.where(kind: "blue").count
    assert_equal BigDecimal("1600"), Argentina::DollarQuote.find_by!(kind: "blue", quoted_on: Date.new(2026, 11, 15)).sell_rate
    assert_equal BigDecimal("100"), Argentina::PriceIndex.find_by!(period_on: Date.new(2026, 10, 1)).index_value
    assert_equal 2, result[:rates]
    assert_equal BigDecimal("1600"), ExchangeRate.find_by!(from_currency: "USD", to_currency: "ARS", date: Date.new(2026, 11, 15)).rate
    assert_equal BigDecimal("1540"), ExchangeRate.find_by!(from_currency: "USD", to_currency: "ARS", date: Date.new(2026, 11, 14)).rate
  end
end