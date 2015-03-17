class PaygInvoicePdf < BillingPdf
  include ActionView::Helpers::TextHelper

  def initialize(invoice, view)
    super
    @invoice = invoice
    @account = invoice.account
    @view = view

    font_size 9
    header('PAYG INVOICE')
    addresses_and_invoice_details
    invoice_table
    invoice_summary
    invoice_payment
  end

  def addresses_and_invoice_details
    billing_address = @invoice.billing_address

    float do
      span((bounds.width / 2) - 20, position: :left) do
        text 'Billable to', style: :bold
        move_down 10
        text @invoice.account.user.full_name
        text @invoice.account.user.email
        move_down 5

        if billing_address.present?
          text billing_address[:address1]
          text billing_address[:address2] if billing_address[:address2].present?
          text "#{billing_address[:city]}, #{billing_address[:region]}"
          text billing_address[:postal]
          text IsoCountryCodes.find(billing_address[:country]).name
        end
      end
    end

    float do
      span((bounds.width / 2) - 20, position: :right) do
        items = [
          ['Invoice Number',      @invoice.invoice_number],
          ['Invoice Date',        @invoice.created_at.strftime('%d/%m/%Y')],
          ['Invoice Due Date',    @invoice.created_at.strftime('%d/%m/%Y')],
          ['Invoice Currency',    'USD'],
          ['Customer VAT Number', @invoice.vat_number]
        ]

        table items, width: bounds.width, cell_style: { border_widths: [1] * 4, border_colors: ['999999'] * 4 } do
          style(column(0), align: :right, background_color: 'e9e9e9', font_style: :bold, width: 130, inline_format: true)
        end
      end
    end

    move_down 130
  end

  def invoice_table
    items = [['Product Name/Description', 'Tax Value', 'Net Value']]
    @invoice.invoice_items.each { |item| items << invoice_item(item) }

    if @invoice.coupon.present?
      items << coupon_discount
    end

    table items, width: bounds.width, cell_style: { border_widths: [1] * 4, border_colors: ['999999'] * 4 } do
      style(column(1..2), width: 100, align: :center, valign: :center)
      style(column(0), padding: [8] * 4)
      style(row(0), align: :center, background_color: 'e9e9e9', font_style: :bold, padding: [5] * 4)
    end

    move_down 10
  end

  def coupon_discount
    desc_items = [[formatted_cell("<b>Coupon: #{truncate(@invoice.coupon.description, length: 60)}</b>")]]
    [
      Prawn::Table.new(desc_items - [nil], self, cell_style: { border_widths: [0] * 4, padding: [1, 5, 1, 5] }),
      Invoice.pretty_total(@invoice.tax_cost - @invoice.pre_coupon_tax_cost),
      Invoice.pretty_total(@invoice.net_cost - @invoice.pre_coupon_net_cost)
    ]
  end

  def invoice_summary
    page_width = bounds.width

    float do
      span(300, position: :left) do
        net_cost_gbp = Invoice.pretty_total(Invoice.in_gbp(@invoice.net_cost), '£')
        tax_cost_gbp = Invoice.pretty_total(Invoice.in_gbp(@invoice.tax_cost), '£')

        items = [
          [{ content: 'Tax Summary (in GBP)', colspan: 4 }],
          ['Tax Code', 'Tax Rate', 'Net Value', 'Tax Value'],
          [@invoice.tax_code, "#{(@invoice.tax_rate * 100)}%", net_cost_gbp, tax_cost_gbp]
        ]

        table items, width: page_width - 220, cell_style: { border_widths: [1] * 4, border_colors: ['999999'] * 4 } do
          style(row(0..1), background_color: 'e9e9e9', font_style: :bold, padding: [5] * 4)
          style(row(0..2), align: :center)
        end
      end
    end

    float do
      span(200, position: :right) do
        items = [
          ['Net Total',     Invoice.pretty_total(@invoice.net_cost)],
          ['Tax Total',     Invoice.pretty_total(@invoice.tax_cost)],
          ['Invoice Total', Invoice.pretty_total(@invoice.total_cost)]
        ]

        table items, width: 200, cell_style: { border_widths: [1] * 4, border_colors: ['999999'] * 4 } do
          style(column(0), align: :right, background_color: 'e9e9e9', font_style: :bold, inline_format: true)
          style(column(0..1), width: 100)
          style(column(1), align: :center)
        end
      end
    end

    move_down 90
  end

  def invoice_payment
    items = [
      ['Invoice Payment'],
      ['Payment for your PAYG invoice will be processed against your Payment Balance']
    ]

    table items, width: bounds.width, cell_style: { border_widths: [1] * 4, border_colors: ['999999'] * 4 } do
      style(row(0), background_color: 'e9e9e9', font_style: :bold, padding: [5] * 4)
    end
  end

  private

  def formatted_cell(text)
    Prawn::Table::Cell::Text.new(self, [0, 0], content: text, inline_format: true)
  end

  def invoice_item(item)
    desc_items = [[formatted_cell("<b>#{truncate(item.description, length: 60)}</b>")]]

    if item.billable_transactions.present?
      categories = Payg.categorize_transactions(item.billable_transactions)
      categories.each { |_key, content| desc_items << category_content(content) }
    end

    [
      Prawn::Table.new(desc_items - [nil], self, cell_style: { border_widths: [0] * 4, padding: [1, 5, 1, 5] }),
      Invoice.pretty_total(item.tax_cost),
      Invoice.pretty_total(item.net_cost)
    ]
  end

  def category_content(category)
    return unless category.present?

    cost = Invoice.pretty_total(category[:cost], '$', 8)

    content = "<font size='8'>"
    content += "#{category[:hours]} hour(s) at #{cost} per hour. "
    content += " (#{category[:coupon].percentage}% off via coupon #{category[:coupon].coupon_code})" if category[:coupon].present?
    content += '</font>'
    [formatted_cell(content)]
  end
end