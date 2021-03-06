class ChargeInvoicesTask < BaseTask
  def initialize(user, invoices, auto_billing = false)
    @user     = user
    @invoices = invoices
    @auto_billing = auto_billing
  end

  def process
    account = @user.account
    card    = account.primary_billing_card

    invoices_to_card_charge = []
    @invoices.each do |invoice|
      credit_notes = account.credit_notes.with_remaining_cost
      notes_used = CreditNote.charge_account(credit_notes, invoice.remaining_cost)
      account.create_activity :charge_credit_account, owner: @user, params: { notes: notes_used } unless notes_used.empty?
      create_credit_note_charges(account, invoice, notes_used)
      invoices_to_card_charge << invoice if Invoice.milli_to_cents(invoice.remaining_cost) > 0
    end

    if Invoice.milli_to_cents(invoices_to_card_charge.sum(&:remaining_cost)) >= Invoice::MIN_CHARGE_AMOUNT && card.present?
      charge_primary_card_for_invoices(account, invoices_to_card_charge, card)
    end
  end

  private

  def charge_primary_card_for_invoices(account, invoices, card)
    remaining_cost = invoices.sum(&:remaining_cost)

    begin
      charge = Payments.new.auth_charge(account.gateway_id, card.processor_token, Invoice.milli_to_cents(remaining_cost))
      account.create_activity :auth_charge, owner: @user, params: { card: card.id, amount: Invoice.milli_to_cents(remaining_cost) }
      Payments.new.capture_charge(charge[:charge_id], card_description(invoices))
      account.create_activity :capture_charge, owner: @user, params: { card: card.id, charge: charge[:charge_id] }
      create_card_charges_for_invoices(account, invoices, card, charge)
      mark_invoices_as_paid(invoices)
      track_invoice_revenue(remaining_cost)
    rescue Stripe::StripeError => e
      ErrorLogging.new.track_exception(e, extra: { current_user: @user, source: 'AutomatedBillingTask', invoices: invoices, remaining_cost: remaining_cost })
      account.create_activity :auth_charge_failed, owner: @user, params: { card: card.id, amount: Invoice.milli_to_cents(remaining_cost), reason: e.message }
    end
  end

  def create_credit_note_charges(account, invoice, credit_notes)
    credit_notes.each do |k, v|
      source = CreditNote.find(k)
      Charge.create(source: source, invoice: invoice, amount: v)
      account.create_activity :credit_charge, owner: @user, params: { invoice: invoice.id, amount: v, credit_note: k }
    end

    if Invoice.milli_to_cents(invoice.remaining_cost) > 0 && credit_notes.present?
      invoice.update(state: :partially_paid)
    elsif Invoice.milli_to_cents(invoice.remaining_cost) <= 0
      invoice.update(state: :paid)
    end
  end

  def create_card_charges_for_invoices(account, invoices, card, charge)
    invoices.each do |invoice|
      amount = invoice.remaining_cost
      Charge.create(source: card, invoice: invoice, amount: amount, reference: charge[:charge_id])
      account.create_activity :card_charge, owner: @user, params: { invoice: invoice.id, amount: amount, card: card.id }
    end
  end

  def card_description(invoices)
    "Cloud.net Invoice(s) #{invoices.map(&:invoice_number).join(', ')}"
  end

  def mark_invoices_as_paid(invoices)
    invoices.each { |invoice| invoice.update(state: :paid) }
  end

  def track_invoice_revenue(remaining_cost)
    Analytics.track(@user, event: 'Generated revenue', properties: { revenue: Invoice.pretty_total(remaining_cost) })
  end
end
