class BillingController < ApplicationController
  before_action :set_invoice, only: [:invoice_pdf]
  before_action :set_credit_note, only: [:credit_note_pdf]
  before_action :set_payment_receipt, only: [:payment_receipt_pdf]

  def index
    @account = current_user.account
    @billing = Kaminari.paginate_array(invoice_credits_receipts).page(params[:page]).per(10)
    @cards   = @account.billing_cards.processable
    @payg    = payg_details

    respond_to do |format|
      format.html
    end
  end

  def payg
    render partial: 'payg_details', locals: { payg: payg_details }
  end

  def invoice_pdf
    respond_to do |format|
      format.any do
        pdf = InvoicePdf.create_invoice(@invoice, view_context)
        filename = "CloudDotNet Invoice #{@invoice.invoice_number}.pdf"
        send_data pdf.render, filename: filename, type: 'application/pdf', disposition: 'inline'
      end
    end
  end

  def credit_note_pdf
    respond_to do |format|
      format.any do
        pdf = CreditNotePdf.new(@credit_note, view_context)
        filename = "CloudDotNet Credit Note #{@credit_note.credit_number}.pdf"
        send_data pdf.render, filename: filename, type: 'application/pdf', disposition: 'inline'
      end
    end
  end

  def payment_receipt_pdf
    respond_to do |format|
      format.any do
        pdf = PaymentReceiptPdf.new(@receipt, view_context)
        filename = "CloudDotNet Receipt #{@receipt.receipt_number}.pdf"
        send_data pdf.render, filename: filename, type: 'application/pdf', disposition: 'inline'
      end
    end
  end

  def validate_card
    @account = current_user.account
    @card = BillingCard.new(card_params)
    @card.account    = current_user.account
    @card.ip_address = request.remote_ip
    @card.user_agent = request.user_agent

    fraud_check = lambda { |user, card| MaxmindFraudCheck.new(user, card).process }

    respond_to do |format|
      if @card.valid? && fraud_check.call(current_user, @card) && @card.save
        assessment = @card.fraud_assessment
        @card.account.calculate_risky_card(assessment[:assessment])
        format.json { render json: assessment.merge(card_id: @card.id) }
      else
        format.json { render json: @card.errors, status: :unprocessable_entity }
      end
    end
  end

  def add_card_token
    account = current_user.account
    @card = BillingCard.find(params[:card_id])
    associate_card = lambda { |card, token| AssociateCard.new(card, token).process }

    respond_to do |format|
      if associate_card.call(@card, params[:token]) && @card.errors.empty?
        Analytics.track(current_user, event: 'Added a billing card')
        format.json { render partial: 'card.json', locals: { card: @card, primary_card: account.primary_billing_card } }
      else
        format.json { render json: @card.errors, status: :unprocessable_entity }
      end
    end
  end

  def update_billing
    @account = current_user.account
    @account.update(account_params)

    if @account.save
      redirect_to billing_index_path, notice: 'Billing Account updated successfully'
    else
      redirect_to billing_index_path, alert: 'Billing Account could not be updated. Please check the VAT number is valid and try again'
    end

    Analytics.track(current_user, event: 'Added a VAT Number')
  end

  def make_primary
    card = current_user.account.billing_cards.find(params[:card_id])
    card.update(primary: true)
    Analytics.track(current_user, event: 'Changed primary billing card')
    redirect_to billing_index_path, notice: 'Primary Card preference has been saved successfully'
  end

  def set_coupon_code
    coupon_code = params[:coupon_code]
    task = SetCouponCodeTask.new(current_user, coupon_code)

    if task.process
      Analytics.track(current_user, event: 'Set coupon code', properties: { coupon: coupon_code })
    else
      @message = task.errors.join(', ')
    end

    render partial: 'billing/coupon_code/coupon_code_form'
  end

  private

  def invoice_credits_receipts
    maximum = [
      (@account.invoices.maximum(:updated_at).try(:to_i) || 0),
      (@account.credit_notes.maximum(:updated_at).try(:to_i) || 0),
      (@account.payment_receipts.maximum(:updated_at).try(:to_i) || 0)
    ].max

    Rails.cache.fetch([@account, maximum, :invoice_credits_receipts]) do
      invoices          = @account.invoices.order(created_at: :desc).to_a
      credit_notes      = @account.credit_notes.order(created_at: :desc).to_a
      payment_receipts  = @account.payment_receipts.order(created_at: :desc).to_a

      all = invoices.concat(credit_notes).concat(payment_receipts)
      all.sort { |a, b| b.created_at <=> a.created_at }
    end
  end

  def set_invoice
    @invoice = current_user.account.invoices.find_by!(sequential_id: params[:invoice_id])
  end

  def set_credit_note
    @credit_note = current_user.account.credit_notes.find_by!(sequential_id: params[:credit_note_id])
  end

  def set_payment_receipt
    @receipt = current_user.account.payment_receipts.find_by!(sequential_id: params[:payment_receipt_id])
  end

  def payg_details
    a = current_user.account
    { balance: a.payg_balance, available: a.available_payg_balance, used: a.used_payg_balance }
  end

  def card_params
    params.require(:card).permit(:bin, :city, :country, :region, :postal, :expiry_month, :expiry_year, :cardholder, :last4, :address1, :address2)
  end

  def account_params
    # Need to override the country_select gem's form name limitation
    params[:country] = params[:account][:country]
    # Normal strict params
    params.permit(
      :vat_number,
      :company_name,
      :address1,
      :address2,
      :address3,
      :address4,
      :city,
      :country,
      :postal
    )
  end
end
