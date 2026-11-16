# frozen_string_literal: true

require "test_helper"

class Argentina::InflationTest < ActiveSupport::TestCase
  setup do
    @inflation = Argentina::Inflation.new([
      [ Date.new(2026, 9, 1), BigDecimal("100") ],
      [ Date.new(2026, 10, 1), BigDecimal("110") ]
    ])
  end

  test "scales a past month to the latest published index" do
    assert_in_delta BigDecimal("1.1"), @inflation.factor(on: Date.new(2026, 9, 15), as_of: Date.new(2026, 11, 16)), 0.000_1

    adjusted = @inflation.adjust(Money.new(1_000, "ARS"), on: Date.new(2026, 9, 15), as_of: Date.new(2026, 11, 16))
    assert_equal BigDecimal("1100"), adjusted.amount
    assert_equal "ARS", adjusted.currency.iso_code
  end

  test "a month that already uses the latest index is unchanged" do
    ratio = @inflation.factor(on: Date.new(2026, 10, 20), as_of: Date.new(2026, 11, 16))
    assert_equal BigDecimal("1"), ratio

    nominal = BigDecimal("250.5")
    assert_equal nominal, @inflation.adjust(nominal, on: Date.new(2026, 10, 2), as_of: Date.new(2026, 11, 16))
  end

  test "leaves other currencies alone and skips a missing index" do
    dollars = Money.new(10, "USD")
    assert_equal dollars.amount, @inflation.adjust(dollars, on: Date.new(2026, 9, 1)).amount

    empty = Argentina::Inflation.new([])
    assert_nil empty.factor(on: Date.new(2026, 9, 1))
    assert_equal BigDecimal("10"), empty.adjust(BigDecimal("10"), on: Date.new(2026, 9, 1))
  end

  test "stored indexes adjust a september amount to october pesos" do
    Argentina::PriceIndex.create!(period_on: Date.new(2026, 9, 1), index_value: 100, source: "indec")
    Argentina::PriceIndex.create!(period_on: Date.new(2026, 10, 1), index_value: 125, source: "indec")

    adjusted = Argentina::Inflation.for_today.adjust(Money.new(80, "ARS"), on: Date.new(2026, 9, 30), as_of: Date.new(2026, 10, 31))
    assert_equal BigDecimal("100"), adjusted.amount
  end
end
