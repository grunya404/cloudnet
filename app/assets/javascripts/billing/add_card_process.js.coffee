$ ->
  card_form     = "#jg-card-form"
  card_button   = "#cc_card_submit"
  card_alert    = "#cc_card_alert"

  cc_month      = '#cc_month'
  cc_year       = '#cc_year'
  cc_cvc        = '#cc_cvc'
  cc_card       = '#cc_number'

  cc_addr1      = '#cc_address1'
  cc_addr2      = '#cc_address2'
  cc_country    = '#cc_country'
  cc_city       = '#cc_city'
  cc_region     = '#cc_region'
  cc_postal     = '#cc_postal_code'
  cc_cardholder = '#cc_holder_name'

  addCard = (card) ->
    account_cards.push card

  disableAddCardButton = ->
    $(card_button).text("Please wait, verifying card...")
    $(card_button).attr('disabled', 'disabled')

  enableAddCardButton = ->
    $(card_button).removeAttr('disabled')
    $(card_button).text("Add Card")

  showMessages = (messages, type) ->
    alert_box = $("#jg-add-card").find('#cc_card_alert')
    alert_box.html "<div class='alert alert-#{type}'>#{messages}</div>"
    $('html, body').scrollTop($('#cc_card_alert').offset().top - 100)

  hideMessages = ->
    alert_box = $("#jg-add-card").find('#cc_card_alert').first()
    alert_box.html ""

  showErrorMessages = (errors) ->
    showMessages errors.join(', '), "danger"

  showWarningMessages = (warnings) ->
    showMessages warnings.join(', '), "warning"

  showSuccessMessage = (success) ->
    showMessages success, "success"
  
  resetCardFields = ->
    $(cc_month).val("")
    $(cc_year).val("")
    $(cc_cvc).val("")
    $(cc_card).val("")
    # $(cc_country).val("") // This conflicts with Select2!
    $(cc_addr1).val("")
    $(cc_addr2).val("")
    $(cc_city).val("")
    $(cc_region).val("")
    $(cc_postal).val("")
    $(cc_cardholder).val("")

  validateCardFields = ->
    errors = []
    errors.push "Card number is not valid" if !$.payment.validateCardNumber($(cc_card).val())
    errors.push "Card expiry month/year is not valid" if !$.payment.validateCardExpiry($(cc_month).val(), $(cc_year).val())
    errors.push "Card CVC number is not valid (the CVC is usually the last 3 digits on the back of your card or the 4 digits on the top if you have an AMEX card)" if !$.payment.validateCardCVC($(cc_cvc).val(), $.payment.cardType($(cc_card).val()))
    errors.push "Address Line 1 is not valid" if $(cc_addr1).val().length <= 1
    errors.push "Country selected is not valid" if $(cc_country).val().length <= 1
    errors.push "City entered is not valid" if $(cc_city).val().length < 2
    errors.push "Region entered is not valid" if $(cc_region).val().length < 2
    errors.push "Postal Code entered is not valid" if $(cc_postal).val().length < 1
    errors.push "Card Holder Name entered is not valid" if $(cc_cardholder).val().length < 1
    return errors

  validateCard = ->
    card_number = $(cc_card).val()
    cvc         = $(cc_cvc).val()

    data = 
      card:
        address1:     $(cc_addr1).val()
        address2:     $(cc_addr2).val()
        last4:        card_number.substr(card_number.length - 4);
        bin:          card_number.slice(0, 6)
        city:         $(cc_city).val()
        country:      $(cc_country).val()
        region:       $(cc_region).val()
        postal:       $(cc_postal).val()
        expiry_month: $(cc_month).val()
        expiry_year:  $(cc_year).val()
        cardholder:   $(cc_cardholder).val()

    $.ajax 
      type: "POST",
      data: data,
      url: '/billing/validate_card',
      dataType: "JSON",
      success: (response) ->
        if response.assessment == "safe"
          sendCardToPaymentProcessor(response.card_id, data, card_number, cvc)
        else if response.assessment == "validate"
          sendCardToPaymentProcessor(response.card_id, data, card_number, cvc)
        else if response.assessment == "rejected"
          showErrorMessages ["Your card could not be validated and has been rejected. Please try a different card"]
          enableAddCardButton()
        else
          showErrorMessages ["We are currently experiencing some issues validating your card. Please try again later"]
          enableAddCardButton()
      error: (xhr, status, error) ->
        showErrorMessages ["We are currently experiencing some issues validating your card. Please try again later"]
        enableAddCardButton()

  sendCardToPaymentProcessor = (card_id, data, number, cvc) ->
    Stripe.card.createToken
      number:           number,
      cvc:              cvc,
      exp_month:        data.card.expiry_month,
      exp_year:         data.card.expiry_year,
      address_zip:      data.card.postal,
      address_country:  data.card.country,
      address_state:    data.card.region,
      name:             data.card.cardholder
    , (status, response) ->
      if response.error
        showErrorMessages [response.error.message]
        enableAddCardButton()
      else
        token = response['id'];
        saveCardToken(card_id, token)

  saveCardToken = (card_id, token) ->
    $.ajax 
      type: "POST",
      data: { card_id: card_id, token: token },
      url: '/billing/add_card_token',
      dataType: "JSON",
      success: (response) ->
        if response.requires_validation == 1
          showSuccessMessage("Card has been added successfully but any servers created using this card will be placed in a validation queue for approval")
        else
          showSuccessMessage("Card has been added successfully")
        addCard(response)
        resetCardFields()
        enableAddCardButton()
        $(card_form).trigger($.Event("add_card", {}))
      error: (xhr, status, error) ->
        showErrorMessages ["We are currently experiencing some issues validating your card. Please try again later"]
        enableAddCardButton()

  bindAddCardEvents = ->
    $("#cc_card_submit").on 'click', (e) ->
      e.preventDefault()
      disableAddCardButton()
      hideMessages()
  
      validation_errors = validateCardFields()  
      if validation_errors.length > 0
        showErrorMessages(validation_errors)
        enableAddCardButton()
        return
    
      validateCard()

  bindAddCardEvents()