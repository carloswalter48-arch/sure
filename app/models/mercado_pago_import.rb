# frozen_string_literal: true

# Mercado Pago Actividad / account statement. The upload is normalized to a
# canonical CSV (see Argentina::MercadoPago::Statement) and then follows the
# same row, mapping and publish flow as the other CSV imports.
class MercadoPagoImport < Import
  after_create :set_mappings

  DEFAULT_COLUMN_MAPPINGS = {
    signage_convention: "inflows_positive",
    date_col_label: "date",
    date_format: "%Y-%m-%d",
    name_col_label: "description",
    amount_col_label: "amount",
    currency_col_label: "currency",
    notes_col_label: "balance",
    number_format: "1,234.56",
    col_sep: ","
  }.freeze

  def self.default_column_mappings
    DEFAULT_COLUMN_MAPPINGS
  end

  def preset_for_uploaded_csv
    parsed = Argentina::MercadoPago::Statement.parse(raw_file_str)
    return if parsed.rows.empty?

    self.raw_file_str = parsed.csv
    assign_attributes(self.class.default_column_mappings)
  end

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.each_with_index.filter_map do |row, index|
      amount = sanitize_number(row[amount_col_label])
      next if row[date_col_label].blank? || amount.blank?

      balance = row["balance"].to_s.strip
      {
        source_row_number: index + 1,
        account: account&.name.to_s,
        date: row[date_col_label].to_s,
        amount: amount,
        currency: (row[currency_col_label].presence || "ARS").to_s,
        name: (row[name_col_label].presence || default_row_name).to_s,
        notes: balance.present? ? "Saldo: #{balance}" : ""
      }
    end

    rows.insert_all!(mapped_rows) if mapped_rows.any?
    update_column(:rows_count, rows.count)
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      rows.each do |row|
        mapped_account = account || mappings.accounts.mappable_for(row.account)
        if mapped_account.nil?
          raise Import::MappingError, "Row #{row.source_row_number}: account is not mapped"
        end

        mapped_account.entries.create!(
          date: row.date_iso,
          amount: row.signed_amount,
          name: row.name,
          currency: row.currency.presence || mapped_account.currency.presence || "ARS",
          notes: row.notes,
          entryable: Transaction.new,
          import: self
        )
      end
    end
  end

  def mapping_steps
    account.nil? ? [ Import::AccountMapping ] : []
  end

  def required_column_keys
    %i[date amount name currency]
  end

  def column_keys
    %i[date amount name currency notes]
  end

  def csv_template
    template = <<~CSV
      Fecha,Descripción,ID de la operación,Valor,Saldo
      15/03/2024,Supermercado,1001,"-1.234,56","10.000,00"
      16/03/2024,Transferencia recibida,1002,"2.500,00","12.500,00"
    CSV

    CSV.parse(template, headers: true)
  end

  private
    def set_mappings
      assign_attributes(self.class.default_column_mappings)
      save!
    end
end
