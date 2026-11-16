# frozen_string_literal: true

require "test_helper"

class MercadoPagoImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "default column mappings use Argentine-friendly canonical columns" do
    import = @family.imports.create!(type: "MercadoPagoImport", account: @account)

    assert_equal "inflows_positive", import.signage_convention
    assert_equal "%Y-%m-%d", import.date_format
    assert_equal "1,234.56", import.number_format
    assert_equal "amount", import.amount_col_label
  end

  test "an Actividad CSV becomes signed transactions and keeps the balance in notes" do
    import = @family.imports.create!(
      type: "MercadoPagoImport",
      account: @account,
      raw_file_str: <<~CSV
        Fecha,Descripción,Valor,Saldo
        15/03/2024,Supermercado,"-1.234,56","10.000,00"
        16/03/2024,Transferencia recibida,"2.500,00","12.500,00"
      CSV
    )
    import.preset_for_uploaded_csv
    import.save!
    import.generate_rows_from_csv

    spend, income = import.rows.order(:source_row_number)
    assert_equal "2024-03-15", spend.date
    assert_equal "-1234.56", spend.amount
    assert_equal "Saldo: 10000.0", spend.notes
    assert_equal "ARS", spend.currency
    assert_equal BigDecimal("1234.56"), spend.signed_amount

    assert_equal BigDecimal("-2500.0"), income.signed_amount
    assert_equal "Transferencia recibida", income.name
  end

  test "publishing creates entries on the chosen account" do
    import = @family.imports.create!(
      type: "MercadoPagoImport",
      account: @account,
      raw_file_str: <<~CSV
        date,description,amount,balance,currency
        2024-03-16,Transferencia recibida,2500.0,12500.0,ARS
      CSV
    )
    import.generate_rows_from_csv
    import.import!

    entry = @account.entries.find_by!(name: "Transferencia recibida")
    assert_equal BigDecimal("-2500.0"), entry.amount
    assert_equal "ARS", entry.currency
    assert_equal Date.new(2024, 3, 16), entry.date
    assert_equal import, entry.import
  end
end
