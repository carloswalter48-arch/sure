# frozen_string_literal: true

require "csv"

# Turns a Mercado Pago Actividad export (CSV or XLSX) into a canonical CSV
# the import pipeline already understands: ISO dates, dot decimals, and a
# signed amount where money in is positive.
class Argentina::MercadoPago::Statement
  Result = Data.define(:rows, :csv)

  CANONICAL_HEADERS = %w[date description amount balance currency].freeze

  DATE_HEADERS = %w[fecha date fecha_de_liberacion release_date transaction_date fecha_de_transaccion].freeze
  DESCRIPTION_HEADERS = %w[descripcion description detalle concepto tipo_de_operacion transaction_type record_type].freeze
  AMOUNT_HEADERS = %w[valor monto importe amount transaction_net_amount net_amount monto_neto].freeze
  BALANCE_HEADERS = %w[saldo balance saldo_parcial partial_balance balance_amount].freeze
  CREDIT_HEADERS = %w[net_credit_amount credito haber].freeze
  DEBIT_HEADERS = %w[net_debit_amount debito debe].freeze
  CURRENCY_HEADERS = %w[moneda currency].freeze
  REFERENCE_HEADERS = %w[id_de_la_operacion referencia reference source_id external_reference].freeze

  DATE_FORMATS = [ "%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d", "%d/%m/%y", "%Y/%m/%d" ].freeze

  def self.parse(raw, filename: nil)
    new(raw, filename: filename).parse
  end

  def initialize(raw, filename: nil)
    @raw = raw
    @filename = filename.to_s
  end

  def parse
    table = xlsx? ? Argentina::Spreadsheet.read(@raw) : parse_delimited(@raw)
    found = detect_columns(table)
    return Result.new(rows: [], csv: "") if found.nil?

    header_index, columns = found

    parsed = table.drop(header_index + 1).filter_map { |row| build_row(row, columns) }
    Result.new(rows: parsed, csv: to_csv(parsed))
  rescue Argentina::Spreadsheet::WorkbookError
    Result.new(rows: [], csv: "")
  end

  # "1.234,56", "1,234.56", "$ 1.234", "(1.234,56)".
  def self.parse_amount(value)
    text = value.to_s.strip
    return nil if text.blank?

    negative = text.start_with?("-") || text.match?(/\A\(/)
    digits = text.gsub(/[^\d,.]/, "")
    return nil if digits.blank?

    normalized = if digits.match?(/\A\d{1,3}(\.\d{3})+(,\d+)?\z/)
      digits.delete(".").tr(",", ".")
    elsif digits.match?(/\A\d{1,3}(,\d{3})+(\.\d+)?\z/)
      digits.delete(",")
    elsif digits.include?(",")
      digits.tr(",", ".")
    elsif digits.match?(/\A\d+\.\d{3}\z/)
      digits.delete(".")
    else
      digits
    end

    number = BigDecimal(normalized)
    negative ? -number : number
  rescue ArgumentError
    nil
  end

  def self.parse_date(value)
    text = value.to_s.strip
    return nil if text.blank?

    if text.match?(/\A\d{5}(\.0+)?\z/)
      return Date.new(1899, 12, 30) + text.to_i
    end

    DATE_FORMATS.each do |format|
      return Date.strptime(text, format)
    rescue Date::Error
      next
    end
    nil
  end

  private
    def xlsx?
      @filename.downcase.end_with?(".xlsx") || @raw.to_s.b.start_with?("PK\x03\x04")
    end

    def parse_delimited(raw)
      text = raw.to_s.dup.force_encoding(Encoding::UTF_8).scrub.delete_prefix("\uFEFF")
      sample = text.lines.lazy.map(&:strip).find(&:present?).to_s
      separator = sample.count(";") > sample.count(",") ? ";" : ","
      CSV.parse(text, col_sep: separator, liberal_parsing: true)
    rescue CSV::MalformedCSVError
      []
    end

    def detect_columns(table)
      table.first(20).each_with_index do |row, index|
        headers = row.map { |cell| normalize_header(cell) }
        date = index_of(headers, DATE_HEADERS)
        amount = index_of(headers, AMOUNT_HEADERS)
        credit = index_of(headers, CREDIT_HEADERS)
        next if date.nil? || (amount.nil? && credit.nil?)

        return [ index, {
          date: date,
          description: index_of(headers, DESCRIPTION_HEADERS),
          amount: amount,
          balance: index_of(headers, BALANCE_HEADERS),
          credit: credit,
          debit: index_of(headers, DEBIT_HEADERS),
          currency: index_of(headers, CURRENCY_HEADERS),
          reference: index_of(headers, REFERENCE_HEADERS)
        } ]
      end
      nil
    end

    def index_of(headers, names)
      headers.index { |header| names.include?(header) }
    end

    def normalize_header(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip.tr(" ", "_")
    end

    def build_row(row, columns)
      date = self.class.parse_date(cell(row, columns[:date]))
      amount = signed_amount(row, columns)
      return nil if date.nil? || amount.nil?

      description = cell(row, columns[:description]).presence || "Mercado Pago"
      reference = cell(row, columns[:reference])
      description = "#{description} (#{reference})" if reference.present? && !description.include?(reference)

      {
        date: date.iso8601,
        description: description.squish.truncate(250),
        amount: format_decimal(amount),
        balance: format_decimal(self.class.parse_amount(cell(row, columns[:balance]))),
        currency: currency_code(cell(row, columns[:currency]))
      }
    end

    # Positive means money in, which is what signage `inflows_positive` expects.
    def signed_amount(row, columns)
      if columns[:amount]
        self.class.parse_amount(cell(row, columns[:amount]))
      else
        credit = self.class.parse_amount(cell(row, columns[:credit])) || 0
        debit = self.class.parse_amount(cell(row, columns[:debit])) || 0
        credit.abs - debit.abs
      end
    end

    def currency_code(value)
      code = value.to_s.strip.upcase
      return "ARS" if code.blank?
      return code if code.match?(/\A[A-Z]{3}\z/)

      "ARS"
    end

    def cell(row, index)
      return "" if index.nil?

      row[index].to_s.strip
    end

    def format_decimal(number)
      return "" if number.nil?

      number.to_s("F")
    end

    def to_csv(rows)
      CSV.generate do |csv|
        csv << CANONICAL_HEADERS
        rows.each do |row|
          csv << CANONICAL_HEADERS.map { |key| row[key.to_sym] }
        end
      end
    end
end
