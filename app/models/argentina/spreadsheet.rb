# frozen_string_literal: true

require "csv"
require "zip"

# Reads the first worksheet of an .xlsx file into rows of strings, using
# rubyzip and Nokogiri (already in the app). Enough for a Mercado Pago
# statement, which is a single sheet of text and numbers.
class Argentina::Spreadsheet
  WorkbookError = Class.new(StandardError)

  def self.read(binary)
    new(binary).rows
  end

  def initialize(binary)
    @binary = binary.to_s.b
  end

  def rows
    parsed = nil
    # open_buffer returns the buffer, not the block result, so keep the rows.
    Zip::File.open_buffer(@binary) do |zip|
      shared = shared_strings(zip)
      sheet = zip.find_entry("xl/worksheets/sheet1.xml")
      raise WorkbookError, "The workbook has no sheet" unless sheet

      parsed = parse_sheet(sheet.get_input_stream.read, shared)
    end
    parsed
  rescue Zip::Error => e
    raise WorkbookError, e.message
  end

  private
    def shared_strings(zip)
      entry = zip.find_entry("xl/sharedStrings.xml")
      return [] unless entry

      document = Nokogiri::XML(entry.get_input_stream.read)
      document.xpath("//*[local-name()='si']").map do |item|
        item.xpath(".//*[local-name()='t']").map(&:text).join
      end
    end

    def parse_sheet(xml, shared)
      document = Nokogiri::XML(xml)
      document.xpath("//*[local-name()='sheetData']/*[local-name()='row']").map do |row|
        values = []
        row.xpath("*[local-name()='c']").each do |cell|
          index = column_index(cell["r"].to_s)
          values[index] = cell_value(cell, shared)
        end
        values.map { |value| value.to_s }
      end
    end

    def cell_value(cell, shared)
      node = cell.at_xpath("*[local-name()='v']")
      case cell["t"]
      when "s"
        shared[node&.text.to_i].to_s
      when "inlineStr"
        cell.xpath(".//*[local-name()='t']").map(&:text).join
      when "b"
        node&.text == "1" ? "true" : "false"
      else
        node&.text.to_s
      end
    end

    def column_index(ref)
      letters = ref[/[A-Z]+/].to_s
      letters.chars.reduce(0) { |sum, char| (sum * 26) + (char.ord - 64) } - 1
    end
end
