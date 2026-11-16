# frozen_string_literal: true

module ArgentinaHelper
  def argentina_counterpart_money(money)
    return nil unless money.is_a?(Money)
    return nil unless Current.family&.argentina_fx_enabled?

    other = case money.currency.iso_code
    when "ARS" then "USD"
    when "USD" then "ARS"
    end
    return nil unless other

    rate = Argentina::Fx.multiplier(from: money.currency.iso_code, to: other, kind: Current.family.argentina_fx_kind)
    return nil unless rate

    Money.new(money.amount * rate, other)
  end

  def argentina_counterpart_text(money)
    other = argentina_counterpart_money(money)
    return nil unless other

    t("argentina.counterpart", amount: other.format, kind: t("argentina.fx_kinds.#{Current.family.argentina_fx_kind}"))
  end

  # Signed the same way the transaction row prints the original amount
  # (inflows positive on screen). Nil when the figure is already in the
  # latest published month.
  def real_terms_amount(entry)
    return nil unless Current.family&.inflation_adjustment_enabled?
    return nil unless entry.currency == "ARS"

    ratio = inflation_adjuster.factor(on: entry.date)
    return nil if ratio.nil? || (ratio - 1).abs < 0.000_1

    Money.new(-(entry.amount_money.amount * ratio), "ARS")
  end

  def inflation_adjuster
    @inflation_adjuster ||= Argentina::Inflation.for_today
  end
end
