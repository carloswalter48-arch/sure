# frozen_string_literal: true

class Argentina::DollarQuote < ApplicationRecord
  self.table_name = "argentina_dollar_quotes"

  # casas published by dolarapi / argentinadatos. MEP is the "bolsa" quote.
  KINDS = %w[oficial blue bolsa contadoconliqui mayorista cripto tarjeta].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :quoted_on, :buy_rate, :sell_rate, :source, presence: true
  validates :buy_rate, :sell_rate, numericality: { greater_than: 0 }

  scope :for_kind, ->(kind) { where(kind: kind) }

  def self.latest_for(kind)
    for_kind(kind).order(quoted_on: :desc).first
  end

  # Latest quote on or before `date`, else the earliest after it.
  def self.on_or_near(kind, date)
    for_kind(kind).where(quoted_on: ..date).order(quoted_on: :desc).first ||
      for_kind(kind).where("quoted_on > ?", date).order(:quoted_on).first
  end

  def self.upsert_quotes!(rows)
    return 0 if rows.blank?

    now = Time.current
    payload = rows.filter_map do |row|
      next unless KINDS.include?(row[:kind])
      next unless row[:buy_rate].to_d.positive? && row[:sell_rate].to_d.positive?

      {
        kind: row[:kind],
        quoted_on: row[:quoted_on],
        buy_rate: row[:buy_rate],
        sell_rate: row[:sell_rate],
        source: row[:source].presence || "dolarapi",
        created_at: now,
        updated_at: now
      }
    end
    return 0 if payload.empty?

    payload.uniq! { |row| [ row[:kind], row[:quoted_on] ] }
    payload.each_slice(500) do |batch|
      upsert_all(batch, unique_by: %i[kind quoted_on])
    end
    payload.size
  end
end
