# frozen_string_literal: true

class AddArgentinaFxAndInflation < ActiveRecord::Migration[8.1]
  def change
    change_table :families, bulk: true do |t|
      t.string :argentina_fx_kind, null: false, default: "oficial"
      t.boolean :argentina_fx_enabled, null: false, default: false
      t.boolean :inflation_adjustment_enabled, null: false, default: false
    end

    add_check_constraint :families,
      "argentina_fx_kind IN ('oficial', 'blue', 'mep')",
      name: "chk_families_argentina_fx_kind"

    create_table :argentina_dollar_quotes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.date :quoted_on, null: false
      t.string :kind, null: false
      t.decimal :buy_rate, null: false
      t.decimal :sell_rate, null: false
      t.string :source, null: false, default: "dolarapi"
      t.timestamps
    end

    add_index :argentina_dollar_quotes, [ :kind, :quoted_on ], unique: true
    add_check_constraint :argentina_dollar_quotes,
      "buy_rate > 0 AND sell_rate > 0",
      name: "chk_argentina_dollar_quotes_rates_positive"

    create_table :argentina_price_indices, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.date :period_on, null: false
      t.decimal :index_value, null: false
      t.string :source, null: false, default: "indec"
      t.timestamps
    end

    add_index :argentina_price_indices, :period_on, unique: true
    add_check_constraint :argentina_price_indices,
      "index_value > 0",
      name: "chk_argentina_price_indices_positive"
  end
end
