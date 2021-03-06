class PaygTopupCardTask < BaseTask
  def initialize(account, usd_amount)
    @usd_amount = usd_amount
    @amount     = usd_amount * Payg::CENTS_IN_DOLLAR

    @account = account
    @user    = account.user
  end

  def process
    card = @account.primary_billing_card

    if !Payg::VALID_TOP_UP_AMOUNTS.include?(@usd_amount)
      errors << 'Amount submitted is invalid. Please try again'
      return false
    elsif !card.present?
      errors << 'You do not have a billing card associated with your account.'
      return false
    end

    begin
      charge = Payments.new.auth_charge(@account.gateway_id, card.processor_token, @amount)
      @account.create_activity :auth_charge, owner: @user, params: { card: card.id, amount: @amount }
      Payments.new.capture_charge(charge[:charge_id], 'Cloud.net Top Up')
      @account.create_activity :capture_charge, owner: @user, params: { card: card.id, charge: charge[:charge_id] }
      create_payment_receipt(charge[:charge_id])
      return true
    rescue Stripe::StripeError => e
      ErrorLogging.new.track_exception(e, extra: { current_user: @user, source: 'PaygTopupCard', amount: @amount })
      @account.create_activity :auth_charge_failed, owner: @user, params: { card: card.id, amount: @amount, reason: e.message }
      errors << "Card Failure: #{e.message}"
      return false
    end
  end

  attr_reader :payment_receipt

  private

  def create_payment_receipt(charge_id)
    value = @usd_amount * Invoice::MILLICENTS_IN_DOLLAR
    @payment_receipt = PaymentReceipt.create_receipt(@account, value, :billing_card)
    @payment_receipt.reference = charge_id
    @payment_receipt.save
  end
end
