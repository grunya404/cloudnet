class PaygTopupPaypalResponseTask < BaseTask
  def initialize(account, token, payer_id)
    Paypal.sandbox! unless Rails.env.production?

    @account  = account
    @user     = account.user
    @token    = token
    @payer_id = payer_id
  end

  def process
    request = Paypal::Express::Request.new(
      username: PAYMENTS[:paypal][:api_user],
      password: PAYMENTS[:paypal][:api_pass],
      signature: PAYMENTS[:paypal][:api_signature]
    )

    details = request.details(@token) # GetExpressCheckoutDetails
    payment = Paypal::Payment::Request.new(amount: details.amount, description: 'Cloud.net PAYG')

    response = request.checkout!(@token, @payer_id, payment)  # DoExpressCheckoutPayment
    create_payment_receipt(details.amount, response.token, response_to_hash(response))
  end

  attr_reader :payment_receipt

  private

  def response_to_hash(response)
    response.instance_variables.each_with_object({}) { |var, hash| hash[var.to_s.delete('@')] = response.instance_variable_get(var) }
  end

  def create_payment_receipt(amount, token_id, metadata)
    existing_receipt = PaymentReceipt.find_by(reference: token_id)

    if existing_receipt.present?
      @payment_receipt = existing_receipt
    else
      value = amount.total.to_f * Invoice::MILLICENTS_IN_DOLLAR
      @payment_receipt = PaymentReceipt.create_receipt(@account, value, :paypal)
      @payment_receipt.reference = token_id
      @payment_receipt.metadata = metadata
      @payment_receipt.save
    end
  end
end
