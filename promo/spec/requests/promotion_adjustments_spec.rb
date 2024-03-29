require 'spec_helper'

describe "Promotion Adjustments" do
  stub_authorization!

  context "coupon promotions", :js => true do
    let!(:zone) { create(:zone) }
    let!(:shipping_method) do
      sm = create(:shipping_method, :zone => zone)
      sm.calculator.set_preference(:amount, 10)
      sm
    end
    let!(:country) do
      country = create(:country)
      shipping_method.zone.zone_members.create!(:zoneable => country)
      country
    end
    let!(:state) { create(:state, :country => country) }
    let!(:address) { create(:address, :state => state, :country => country) }

    before(:each) do
      # creates a default shipping method which is required for checkout
      create(:bogus_payment_method, :environment => 'test')
      # creates a check payment method so we don't need to worry about cc details
      create(:payment_method)


      user = create(:admin_user)
      create(:product, :name => "RoR Mug", :price => "40")
      create(:product, :name => "RoR Bag", :price => "20")

      visit spree.admin_path
      click_link "Promotions"
      click_link "New Promotion"
    end

    it "should properly populate Spree::Product#possible_promotions" do
      promotion = create_per_product_promotion 'RoR Mug', 5.0
      promotion.update_column :advertise, true

      mug = Spree::Product.find_by_name 'RoR Mug'
      bag = Spree::Product.find_by_name 'RoR Bag'

      mug.possible_promotions.size.should == 1
      bag.possible_promotions.size.should == 0

      # expire the promotion
      promotion.expires_at = Date.today.beginning_of_week
      promotion.starts_at = Date.today.beginning_of_week.advance(:day => 3)
      promotion.save!

      mug.possible_promotions.size.should == 0
    end

    it "should allow an admin to create a flat rate discount coupon promo" do
      create_per_order_coupon_promotion 30, 5, "ORDER_38"

      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      click_button "Checkout"

      fill_in "Customer E-Mail", :with => "spree@example.com"
      str_addr = "bill_address"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"

      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"

      fill_in "order_coupon_code", :with => "ORDER_38"
      click_button "Save and Continue"

      Spree::Order.last.adjustments.promotion.pluck(:amount).sum.should == -5.0
    end

    it "should allow an admin to create a single user coupon promo with flat rate discount" do
      fill_in "Name", :with => "Order's total > $30"
      fill_in "Usage Limit", :with => "1"
      select2 "Coupon code added", :from => "Event Name"
      fill_in "Code", :with => "SINGLE_USE"
      click_button "Create"
      page.should have_content("Editing Promotion")

      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Flat Rate (per order)", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('#action_fields') { fill_in "Amount", :with => "5" }
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      click_button "Checkout"

      fill_in "Customer E-Mail", :with => "spree@example.com"
      str_addr = "bill_address"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"
      fill_in "order_coupon_code", :with => "SINGLE_USE"

      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"
      click_button "Save and Continue"

      Spree::Order.first.total.to_f.should == 45.00

      click_button "Place Order"
      # Really make sure that the order has been processed
      # Rather than blindly clicking on "Place Order" and hoping for the best
      page.should have_content("Your order has been processed successfully")

      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      click_button "Checkout"

      fill_in "Customer E-Mail", :with => "spree@example.com"
      str_addr = "bill_address"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"

      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"
      fill_in "order_coupon_code", :with => "SINGLE_USE"
      click_button "Save and Continue"

      Spree::Order.last.total.to_f.should == 50.00
    end

    it "should allow an admin to create an automatic promo with flat percent discount" do
      fill_in "Name", :with => "Order's total > $30"
      select2 "Order contents changed", :from => "Event Name"
      click_button "Create"
      page.should have_content("Editing Promotion")

      select2 "Item total", :from => "Add rule of type"
      within('#rule_fields') { click_button "Add" }

      eventually_fill_in "promotion_promotion_rules_attributes_1_preferred_amount", :with => 30
      within('#rule_fields') { click_button "Update" }

      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Flat Percent", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('.calculator-fields') { fill_in "Flat Percent", :with => "10" }
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      Spree::Order.last.total.to_f.should == 36.00
      visit spree.root_path
      click_link "RoR Bag"
      click_button "Add To Cart"
      Spree::Order.last.total.to_f.should == 54.00
    end

    it "should allow an admin to create an automatic promotion with free shipping (no code)" do
      fill_in "Name", :with => "Free Shipping"
      click_button "Create"
      page.should have_content("Editing Promotion")

      select2 "Item total", :from => "Add rule of type"
      within('#rule_fields') { click_button "Add" }
      eventually_fill_in "promotion_promotion_rules_attributes_1_preferred_amount", :with => "30"
      within('#rule_fields') { click_button "Update" }

      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Free Shipping", :from => "Calculator"
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Bag"
      click_button "Add To Cart"
      click_button "Checkout"

      fill_in "Customer E-Mail", :with => "spree@example.com"
      str_addr = "bill_address"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"

      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"
      click_button "Save and Continue"
      Spree::Order.last.total.to_f.should == 30.00 # bag(20) + shipping(10)
      page.should_not have_content("Free Shipping")

      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      click_button "Checkout"

      str_addr = "bill_address"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"
      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"

      click_button "Save and Continue"
      Spree::Order.last.total.to_f.should == 60.00 # bag(20) + mug(40) + free shipping(0)
      page.should have_content("Free Shipping")
    end

    it "should allow an admin to create an automatic promo requiring a landing page to be visited" do
      fill_in "Name", :with => "Deal"
      select2 "Visit static content page", :from => "Event Name"
      fill_in "Path", :with => "content/cvv"
      click_button "Create"
      page.should have_content("Editing Promotion")

      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Flat Rate (per order)", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('.calculator-fields') { fill_in "Amount", :with => "4" }
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      Spree::Order.last.total.to_f.should == 40.00

      visit "/content/cvv"
      visit spree.root_path
      click_link "RoR Mug"
      click_button "Add To Cart"
      Spree::Order.last.total.to_f.should == 76.00
    end

    # Regression test for #1416
    it "should allow an admin to create an automatic promo requiring a specific product to be bought" do
      create_per_product_promotion("RoR Mug", 5.0)
      create_per_product_promotion("RoR Bag", 10.0)

      add_to_cart "RoR Mug"
      add_to_cart "RoR Bag"

      # first promotion should be effective on current order
      first_promotion = Spree::Promotion.first
      first_promotion.actions.first.calculator.compute(Spree::Order.last).should == 5.0

      # second promotion should be effective on current order
      second_promotion = Spree::Promotion.last
      second_promotion.actions.first.calculator.compute(Spree::Order.last).should == 10.0

      do_checkout

      # Mug discount ($5) is not taken into account due to #1526
      # Only "best" discount is taken into account
      Spree::Order.last.total.to_f.should == 60.0 # mug(40) + bag(20) - bag_discount(10) + shipping(10)
    end

    it "should allow an admin to create a promotion that adds a 'free' item to the cart" do
      fill_in "Name", :with => "Bundle"
      select2 "Coupon code added", :from => "Event Name"
      fill_in "Code", :with => "5ZHED2DH"
      click_button "Create"
      page.should have_content("Editing Promotion")

      select2 "Create line items", :from => "Add action of type"

      within('#action_fields') { click_button "Add" }
      # Forced narcolepsy, thanks to JavaScript
      sleep(1)
      page.execute_script "$('.create_line_items .select2-choice').mousedown();"
      sleep(1)
      page.execute_script "$('.select2-input:visible').val('RoR Mug').trigger('keyup-change');"
      sleep(1)
      page.execute_script "$('.select2-highlighted').mouseup();"

      within('#actions_container') { click_button "Update" }

      select2 "Create adjustment", :from => "Add action of type"
      within('#new_promotion_action_form') { click_button "Add" }
      select2 "Flat Rate (per order)", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('.calculator-fields') { fill_in "Amount", :with => "40.00" }
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Bag"
      click_button "Add To Cart"
      click_button "Checkout"

      str_addr = "bill_address"
      fill_in "order_email", :with => "buyer@spreecommerce.com"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"

      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"

      fill_in "order_coupon_code", :with => "5ZHED2DH"
      click_button "Save and Continue"

      last_order = Spree::Order.last
      last_order.line_items.count.should == 2
      last_order.line_items.pluck(:price).should =~ [20.00, 40.00]
      last_order.item_total.to_f.should == 60.00
      last_order.adjustments.promotion.pluck(:amount).sum.to_f.should == -40.00
      last_order.total.to_f.should == 30.00
    end

    it "ceasing to be eligible for a promotion with item total rule then becoming eligible again" do
      fill_in "Name", :with => "Spend over $50 and save $5"
      select2 "Order contents changed", :from => "Event Name"
      click_button "Create"
      page.should have_content("Editing Promotion")

      select2 "Item total", :from => "Add rule of type"
      within('#rule_fields') { click_button "Add" }
      eventually_fill_in "promotion_promotion_rules_attributes_1_preferred_amount", :with => "50"
      within('#rule_fields') { click_button "Update" }

      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Flat Rate (per order)", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('.calculator-fields') { fill_in "Amount", :with => "5" }
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Bag"
      click_button "Add To Cart"
      Spree::Order.last.total.to_f.should == 20.00

      fill_in "order[line_items_attributes][0][quantity]", :with => "2"
      click_button "Update"
      Spree::Order.last.total.to_f.should == 40.00
      Spree::Order.last.adjustments.eligible.promotion.count.should == 0

      fill_in "order[line_items_attributes][0][quantity]", :with => "3"
      click_button "Update"
      Spree::Order.last.total.to_f.should == 55.00
      Spree::Order.last.adjustments.eligible.promotion.count.should == 1

      fill_in "order[line_items_attributes][0][quantity]", :with => "2"
      click_button "Update"
      Spree::Order.last.total.to_f.should == 40.00
      Spree::Order.last.adjustments.eligible.promotion.count.should == 0

      fill_in "order[line_items_attributes][0][quantity]", :with => "3"
      click_button "Update"
      Spree::Order.last.total.to_f.should == 55.00
    end

    it "only counting the most valuable promotion adjustment in an order" do
      fill_in "Name", :with => "$5 off"
      select2 "Order contents changed", :from => "Event Name"
      click_button "Create"
      page.should have_content("Editing Promotion")
      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Flat Rate (per order)", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('.calculator-fields') { fill_in "Amount", :with => "5" }
      within('#actions_container') { click_button "Update" }

      visit spree.admin_promotions_path
      click_link "New Promotion"
      fill_in "Name", :with => "10% off"
      select2 "Order contents changed", :from => "Event Name"
      click_button "Create"
      page.should have_content("Editing Promotion")
      select2 "Create adjustment", :from => "Add action of type"
      within('#action_fields') { click_button "Add" }
      select2 "Flat Percent", :from => "Calculator"
      within('#actions_container') { click_button "Update" }
      within('.calculator-fields') { fill_in "Flat Percent", :with => "10" }
      within('#actions_container') { click_button "Update" }

      visit spree.root_path
      click_link "RoR Bag"
      click_button "Add To Cart"
      Spree::Order.last.total.to_f.should == 15.00

      fill_in "order[line_items_attributes][0][quantity]", :with => "2"
      click_button "Update"
      Spree::Order.last.total.to_f.should == 35.00

      fill_in "order[line_items_attributes][0][quantity]", :with => "3"
      click_button "Update"
      Spree::Order.last.total.to_f.should == 54.00
    end

    def add_to_cart product_name
      visit spree.root_path
      click_link product_name
      click_button "Add To Cart"
    end

    def do_checkout
      click_button "Checkout"
      str_addr = "bill_address"
      fill_in "order_email", :with => "buyer@spreecommerce.com"
      select "United States", :from => "order_#{str_addr}_attributes_country_id"
      ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
        fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
      end
      select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
      check "order_use_billing"
      click_button "Save and Continue"
      click_button "Save and Continue"
      choose('Credit Card')
      fill_in "card_number", :with => "4111111111111111"
      fill_in "card_code", :with => "123"
      click_button "Save and Continue"
    end
  end
end
