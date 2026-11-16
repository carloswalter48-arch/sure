# frozen_string_literal: true

require "test_helper"
require "zip"

class Argentina::MercadoPago::StatementTest < ActiveSupport::TestCase
  setup do
    @csv = <<~CSV
      Fecha;Descripción;ID de la operación;Valor;Saldo
      15/03/2024;Supermercado;1001;-1.234,56;10.000,00
      16/03/2024;Transferencia recibida;1002;"2.500,00";"12.500,00"
      ;;;
    CSV
  end

  test "parses Argentine dates, amounts and the running balance" do
    result = Argentina::MercadoPago::Statement.parse(@csv)

    assert_equal 2, result.rows.size
    spend, income = result.rows
    assert_equal "2024-03-15", spend[:date]
    assert_equal "Supermercado (1001)", spend[:description]
    assert_equal "-1234.56", spend[:amount]
    assert_equal "10000.0", spend[:balance]
    assert_equal "ARS", spend[:currency]

    assert_equal "2024-03-16", income[:date]
    assert_equal "2500.0", income[:amount]
    assert_equal "12500.0", income[:balance]
    assert_includes result.csv, "date,description,amount,balance,currency"
  end

  test "parses a settlement file with separate credit and debit columns" do
    csv = <<~CSV
      DATE,DESCRIPTION,NET_CREDIT_AMOUNT,NET_DEBIT_AMOUNT,BALANCE_AMOUNT,CURRENCY
      2024-03-15,Payment received,1500.25,0,8000.00,ARS
      2024-03-16,Fee,0,"1.234,50",6765.50,USD
    CSV

    rows = Argentina::MercadoPago::Statement.parse(csv).rows
    assert_equal "1500.25", rows.first[:amount]
    assert_equal "ARS", rows.first[:currency]
    assert_equal "-1234.5", rows.second[:amount]
    assert_equal "USD", rows.second[:currency]
  end

  test "parses amounts and excel serial dates" do
    assert_equal BigDecimal("-1234.56"), Argentina::MercadoPago::Statement.parse_amount("(1.234,56)")
    assert_equal BigDecimal("1234.56"), Argentina::MercadoPago::Statement.parse_amount("1,234.56")
    assert_equal BigDecimal("1234"), Argentina::MercadoPago::Statement.parse_amount("1.234")
    assert_nil Argentina::MercadoPago::Statement.parse_amount("")

    assert_equal Date.new(2024, 3, 15), Argentina::MercadoPago::Statement.parse_date("15/03/2024")
    assert_equal Date.new(2024, 3, 15), Argentina::MercadoPago::Statement.parse_date((Date.new(2024, 3, 15) - Date.new(1899, 12, 30)).to_i.to_s)
  end

  test "reads an xlsx statement" do
    binary = workbook([
      [ "Fecha", "Descripción", "Valor", "Saldo" ],
      [ "01/04/2024", "Café", "-1.500,00", "20.000,00" ]
    ])

    rows = Argentina::MercadoPago::Statement.parse(binary, filename: "actividad.xlsx").rows
    assert_equal 1, rows.size
    assert_equal "2024-04-01", rows.first[:date]
    assert_equal "Café", rows.first[:description]
    assert_equal "-1500.0", rows.first[:amount]
    assert_equal "20000.0", rows.first[:balance]
  end

  private
    def workbook(table)
      shared = +%(<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">)
      strings = []
      cells = table.each_with_index.map { |row, row_index|
        row.each_with_index.map { |value, column|
          strings << value
          column_letter = ("A".ord + column).chr
          %(<c r="#{column_letter}#{row_index + 1}" t="s"><v>#{strings.size - 1}</v></c>)
        }.join
      }
      shared << strings.map { |value| "<si><t>#{ERB::Util.html_escape(value)}</t></si>" }.join
      shared << "</sst>"
      sheet_rows = cells.each_with_index.map { |xml, index| %(<row r="#{index + 1}">#{xml}</row>) }.join
      sheet = %(<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>)

      buffer = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("xl/sharedStrings.xml")
        zip.write(shared)
        zip.put_next_entry("xl/worksheets/sheet1.xml")
        zip.write(sheet)
      end
      buffer.string
    end
end
