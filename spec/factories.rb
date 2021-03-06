FactoryGirl.define do
  factory :user do
    email { Faker::Internet.email }
    password 'sekret123'
    full_name { Faker::Name.name }
    association :account, factory: :account

    factory :active_user do
      status :active
    end

    factory :admin do
      admin true
    end

    factory :user_onapp do
      status :active
      onapp_user 'user_onapp_test'
      onapp_password 'abcdef123456'
    end

    # The presence of user.account.gateway_id prevents the callback that makes a Stripe account for
    # the user
    factory :user_without_stripe do
      account nil
    end
  end

  factory :account do
    gateway_id 'cn_abc123456'
  end

  # This isn't a real location. But hv_group_id is very likely to be, if Onapp is properly set up
  factory :location do
    latitude '-51.43423423'
    longitude '60.323233423'
    provider 'Dediserve'
    country 'GB'
    city 'London'
    hv_group_id '30'
    hidden false
    photo_ids '123456,789012'
    price_cpu 50
    price_disk 60
    price_bw 100
    price_memory 100
    after(:build) do |location|
      3.times {|i| create("pack#{i}".to_sym, location: location) }
    end
  end
  
  factory :package do
    memory 512
    cpus 1
    disk_size 10
    ip_addresses 1
    location 
    
    factory :pack0
    factory :pack1 do
      memory 1024
      cpus 2
    end
    factory :pack2 do
      disk_size 50
      cpus 3
    end
  end

  factory :template do
    identifier 5
    os_type 'linux'
    os_distro 'ubuntu'
    onapp_os_distro 'ubuntu'
    name 'Ubuntu 12.04 x64'
    association :location, factory: :location
    hidden false
  end

  factory :server do
    identifier 'w909klk7ft4kp3'
    name 'My Server'
    hostname 'server.com'
    state :building
    association :user, factory: :user_onapp
    association :template, factory: :template

    after(:build) { |s| s.update location: s.template.location }
  end

  factory :server_wizard do
    name 'My Server'
    hostname 'server.com'
    memory 1024
    cpus 2
    disk_size 10
    association :user, factory: :user_onapp
    association :location, factory: :location

    after(:build) do |s|
      s.template = FactoryGirl.create(:template, location: s.location)
    end

    factory :server_wizard_with_billing_card do
      after(:build) do |s|
        s.card_id  = FactoryGirl.create(:billing_card, account: s.user.account).id
      end
    end
  end

  factory :server_usage do
    usage_type :cpu
    usages '[{"cpu_time":1,"created_at":"2014-05-05T12:01:08Z"},{"cpu_time":0,"created_at":"2014-05-05T13:01:16Z"},{"cpu_time":0,"created_at":"2014-05-05T14:01:03Z"}]'
    association :server, factory: :server
  end

  factory :server_event do
    action 'create_virtual_server'
    status 'completed'
    association :server, factory: :server
  end

  factory :server_backup do
    backup_id 1
    built true
    identifier 'abc123'
    backup_created Date.today
    association :server, factory: :server
  end

  factory :ticket do
    subject 'My fantastic ticket'
    body 'I would like to add some more resources to my cloud'
    association :user, factory: :user
    association :server, factory: :server
  end

  factory :ticket_reply do |_n|
    body 'Some comment about the ticket by someone'
    sender 'John Smith'
    association :ticket, factory: :ticket
  end

  factory :dns_zone do
    domain 'testererw.com'
    association :user, factory: :user_onapp
    autopopulate true
    domain_id 64
  end

  factory :invoice do
    association :account, factory: :account
  end

  factory :invoice_item do
    association :invoice, factory: :invoice
  end

  factory :credit_note do
    association :account, factory: :account
  end

  factory :credit_note_item do
    association :credit_note, factory: :credit_note
  end

  factory :billing_card do
    bin '424242'
    ip_address '192.168.1.1'
    user_agent 'Mozilla/6.0'
    address1 '91 Brick Lane'
    city 'London'
    country 'GB'
    region 'Essex'
    postal 'E1 6QL'
    expiry_month '06'
    expiry_year '15'
    last4 '1234'
    cardholder 'Mr John Smith'
    association :account, factory: :account
    processor_token 'abcd-1234567'
  end

  factory :coupon do
    coupon_code 'ABC123'
    duration_months 6
    percentage 20
    active true
  end

  factory :charge do
    amount 10_000
    association :invoice, factory: :invoice
    source_type 'Tester'
    source_id 100
  end
end
