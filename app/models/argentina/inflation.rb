# frozen_string_literal: true

# Scales an ARS amount from the month it happened into the latest published
# INDEC CPI (IPC), so a 2023 peso is shown in today's pesos.
class Argentina::Inflation
  def self.for_today
    new(Argentina::PriceIndex.order(:period_on).pluck(:period_on, :index_value))
  end

  def initialize(rows)
    @rows = rows.sort_by(&:first)
  end

  def available?
    @rows.any?
  end

  def latest_period
    @rows.last&.first
  end

  # Index of the month containing `date`, or the latest index published
  # before that month when the month itself is not out yet.
  def factor(on:, as_of: Date.current)
    from_index = index_on(on)
    to_index = index_on(as_of)
    return nil if from_index.nil? || to_index.nil? || from_index.to_d.zero?

    to_index.to_d / from_index.to_d
  end

  def adjust(amount, on:, as_of: Date.current)
    ratio = factor(on: on, as_of: as_of)
    return amount if ratio.nil?

    if amount.is_a?(Money)
      return amount unless amount.currency.iso_code == "ARS"

      Money.new(amount.amount * ratio, "ARS")
    else
      amount.to_d * ratio
    end
  end

  private
    def index_on(date)
      month = date.to_date.beginning_of_month
      match = @rows.reverse_each.find { |period, _value| period <= month }
      match&.last
    end
end
