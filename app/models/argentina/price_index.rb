# frozen_string_literal: true

class Argentina::PriceIndex < ApplicationRecord
  self.table_name = "argentina_price_indices"

  validates :period_on, :index_value, :source, presence: true
  validates :index_value, numericality: { greater_than: 0 }

  def self.latest
    order(period_on: :desc).first
  end

  def self.upsert_indexes!(rows)
    return 0 if rows.blank?

    now = Time.current
    payload = rows.filter_map do |row|
      value = row[:index_value].to_d
      next unless value.positive? && row[:period_on].present?

      {
        period_on: row[:period_on].to_date.beginning_of_month,
        index_value: value,
        source: row[:source].presence || "indec",
        created_at: now,
        updated_at: now
      }
    end
    return 0 if payload.empty?

    payload.uniq! { |row| row[:period_on] }
    upsert_all(payload, unique_by: :period_on)
    payload.size
  end
end
