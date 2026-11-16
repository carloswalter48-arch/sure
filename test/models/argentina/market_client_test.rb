# frozen_string_literal: true

require "test_helper"

class Argentina::MarketClientTest < ActiveSupport::TestCase
  setup do
    @client = Argentina::MarketClient.new
  end

  test "parses live dolarapi quotes and keeps oficial, blue and MEP" do
    quotes = @client.parse_current_quotes([
      { "casa" => "oficial", "compra" => 1520, "venta" => 1570, "fechaActualizacion" => "2026-11-13T18:55:00.000Z" },
      { "casa" => "blue", "compra" => 1555, "venta" => 1575, "fechaActualizacion" => "2026-11-15T20:57:00.000Z" },
      { "casa" => "bolsa", "compra" => 1575.5, "venta" => 1580.9, "fechaActualizacion" => "2026-11-15T20:57:00.000Z" },
      { "casa" => "tarjeta", "compra" => 0, "venta" => 10, "fechaActualizacion" => "2026-11-15T20:57:00.000Z" }
    ])

    assert_equal %w[oficial blue bolsa], quotes.map { |quote| quote[:kind] }
    blue = quotes.find { |quote| quote[:kind] == "blue" }
    assert_equal Date.new(2026, 11, 15), blue[:quoted_on]
    assert_equal BigDecimal("1575"), blue[:sell_rate]
    assert_equal "dolarapi", blue[:source]
  end

  test "parses historical quotes" do
    quotes = @client.parse_historical_quotes([
      { "casa" => "blue", "compra" => 4, "venta" => 4.5, "fecha" => "2011-01-03" }
    ], source: "argentinadatos")

    assert_equal 1, quotes.size
    assert_equal Date.new(2011, 1, 3), quotes.first[:quoted_on]
    assert_equal BigDecimal("4.5"), quotes.first[:sell_rate]
  end

  test "parses the INDEC IPC series" do
    indexes = @client.parse_price_index(
      "data" => [ [ "2026-09-01", "12514.1508" ], [ "2026-10-01", "12785.9321" ], [ "bad", nil ] ]
    )

    assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 10, 1) ], indexes.map { |row| row[:period_on] }
    assert_equal BigDecimal("12785.9321"), indexes.last[:index_value]
    assert_equal "indec", indexes.last[:source]
  end

  test "drops quotes with a missing or non-positive price" do
    quotes = @client.parse_current_quotes([
      { "casa" => "oficial", "compra" => nil, "venta" => 10, "fechaActualizacion" => "2026-11-15T12:00:00Z" },
      { "casa" => "blue", "compra" => -1, "venta" => 10, "fechaActualizacion" => "2026-11-15T12:00:00Z" }
    ])

    assert_empty quotes
  end
end
