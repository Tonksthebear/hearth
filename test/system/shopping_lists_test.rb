require "application_system_test_case"

class ShoppingListsTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "manages the shared checklist with physical mobile controls and preserves completed provenance" do
    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 390,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )

    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      visit_and_wait_for_path shopping_list_path(date: WEEK_START)
      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)

      click_button "Add item"
      fill_in_and_wait_for_value "Name", "Bananas"
      fill_in_and_wait_for_value "Quantity", "6"
      fill_in_and_wait_for_value "Unit", "pieces"
      fill_in_and_wait_for_value "Notes", "Still green"
      click_button_and_wait_for_text "Add to list", "Item was added."
      manual = ShoppingListItem.find_by!(name: "Bananas")

      edit_link = within("#shopping-list-item-#{manual.id}") { find_link("Edit") }
      click_element_and_wait_for_path edit_link, edit_shopping_list_item_path(manual, date: WEEK_START)
      fill_in_and_wait_for_value "Name", "Ripe bananas"
      fill_in_and_wait_for_value "Notes", "Ready tomorrow"
      click_button_and_wait_for_text "Save item", "Item was updated."

      check_button = within("#shopping-list-item-#{manual.id}") { find("button[aria-label='Check Ripe bananas']") }
      check_button.click
      assert_selector "#shopping-list-item-#{manual.id}[data-completed='true']", visible: :all, wait: 5
      click_button "Completed"
      assert_selector "#shopping-list-item-#{manual.id}[data-completed='true']", wait: 5
      uncheck_button = within("#shopping-list-item-#{manual.id}") { find("button[aria-label='Uncheck Ripe bananas']") }
      uncheck_button.click
      assert_selector "#shopping-list-item-#{manual.id}[data-completed='false']", wait: 5
      delete_button = within("#shopping-list-item-#{manual.id}") { find_button("Delete") }
      accept_confirm { delete_button.click }
      assert_no_selector "#shopping-list-item-#{manual.id}", wait: 5

      lettuce = ShoppingListItem.find_by!(shopping_list: shopping_lists(:target_week), name: "Lettuce")
      assert_text "2 head Lettuce"
      within "#shopping-list-item-#{lettuce.id}" do
        click_button "2 contributing meals"
        assert_link recipes(:salad).title, count: 2, visible: :visible, wait: 5
        assert_text "On hand"
        assert_text "From pantry evidence"
        assert_selector "[data-shopping-ownership]", minimum: 1
        assert_selector "[data-ownership-role='short']", minimum: 1
        find("button[aria-label='Check Lettuce']").click
      end
      completed_lettuce = "#shopping-list-item-#{lettuce.id}[data-completed='true']"
      assert_selector completed_lettuce, visible: :all, wait: 5
      completed_button = find_button "Completed"
      completed_button.click if completed_button["aria-expanded"] == "false"
      assert_selector completed_lettuce, wait: 5
      assert_predicate pantry_items(:out_lettuce).reload, :out?
      assert_nil pantry_items(:out_lettuce).quantity

      click_link_and_wait_for_path "Meals", meal_week_path
      accept_confirm do
        within "li", text: recipes(:salad).title, match: :first do
          click_button "Remove"
        end
      end
      assert_text "was removed from the plan", wait: 5
      click_link_and_wait_for_path "Shopping", shopping_list_path

      completed_button = find_button "Completed"
      completed_button.click if completed_button["aria-expanded"] == "false"
      assert_selector completed_lettuce
      assert_equal 1, lettuce.reload.shopping_list_item_sources.count
      assert_equal 1, ShoppingListItem.where(shopping_list: lettuce.shopping_list, generated_key: lettuce.generated_key).count

      sign_in_as_person_via_browser people(:two)
      click_link_and_wait_for_path "Meals", meal_week_path
      click_link_and_wait_for_path "Shopping", shopping_list_path
      completed_button = find_button "Completed"
      completed_button.click if completed_button["aria-expanded"] == "false"
      assert_selector completed_lettuce
      assert_text(/shared household list/i)
      assert_equal 390, page.evaluate_script("window.innerWidth")
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "confirming a purchase is the only step that turns a checked deficit into pantry evidence" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      visit_and_wait_for_path shopping_list_path(date: WEEK_START)
      lettuce = ShoppingListItem.find_by!(shopping_list: shopping_lists(:target_week), name: "Lettuce")

      within "#shopping-list-item-#{lettuce.id}" do
        find("button[aria-label='Check Lettuce']").click
      end
      assert_selector "#shopping-list-item-#{lettuce.id}[data-completed='true']", wait: 5
      assert_predicate pantry_items(:out_lettuce).reload, :out?

      confirm_link = within("#shopping-list-item-#{lettuce.id}") { find_link("Confirm purchase") }
      click_element_and_wait_for_path confirm_link, new_shopping_list_item_pantry_confirmation_path(lettuce)
      assert_text "checking the item off the list never does"
      fill_in_and_wait_for_value "Amount purchased", "2"
      fill_in_and_wait_for_value "Unit", "head"
      click_button_and_wait_for_text "Confirm purchase", "Pantry evidence recorded for Lettuce."

      pantry = pantry_items(:out_lettuce).reload
      assert_predicate pantry, :confirmed?
      assert_equal Rational(2), pantry.quantity
      assert_equal "head", pantry.unit
      assert_equal PantryItem::PURCHASE_SOURCE, pantry.confirmation_source
      assert_equal people(:one), pantry.confirmed_by
      # The deficit is settled, so the checked row stays only as a tombstone with
      # no contributing meals left to attribute it to.
      assert_selector "#shopping-list-item-#{lettuce.id}[data-completed='true']", wait: 5
      assert_empty lettuce.reload.shopping_list_item_sources
      within("#shopping-list-item-#{lettuce.id}") { assert_no_selector "el-disclosure" }
    end
  end

  test "desktop hover stays read only until the explicit Shopping click" do
    travel_to Time.zone.local(2026, 10, 5, 12) do
      sign_in_via_browser users(:one)
      visit_and_wait_for_path recipe_path(recipes(:porridge))
      week_start = Date.new(2026, 10, 5)

      assert_no_changes -> { ShoppingList.where(household: households(:home), week_start:).count } do
        within "nav[aria-label='Meals']" do
          find_link("Shopping").hover
          assert_no_selector "#shopping-list", wait: 1
        end
      end

      click_link_and_wait_for_path "Shopping", shopping_list_path
      assert ShoppingList.exists?(household: households(:home), week_start:)
      assert_selector "h1", text: "Shopping list"
    end
  end
end
