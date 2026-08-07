require "application_system_test_case"

class PlannedMealIngredientReviewsTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "plans a meal, answers its ingredients, and resumes the review from the week" do
    travel_to WEEK_START do
      sign_in_via_browser users(:one)
      visit_and_wait_for_path meal_week_path(date: WEEK_START)

      set_date_and_wait "Date", "2026-07-31"
      select_and_wait recipes(:porridge).title, from: "Planned recipe"
      select_and_wait "Whole household", from: "Plan for"
      click_button_and_wait_for_text "Add to plan", "#{recipes(:porridge).title} was added to the plan."

      # Planning lands on the ingredient check for the plan it just created.
      plan = PlannedMeal.find_by!(recipe: recipes(:porridge), planned_on: Date.new(2026, 7, 31))
      assert_current_path planned_meal_ingredient_review_path(plan)
      assert_selector "h1", text: recipes(:porridge).title
      assert_selector "[data-readiness-state='needs_ingredient_check']", text: "Needs ingredient check"

      oats = requirement(plan, :rolled_oats)
      berries = requirement(plan, :blueberries)

      within "#requirement-#{oats.id}" do
        assert_selector "[data-requirement-fact='pantry']", text: /Confirmed/
        click_button "On hand"
      end
      assert_selector "#requirement-#{oats.id} [data-decision-label]", text: "On hand"

      within("#requirement-#{berries.id}") { click_button "Add to list" }
      assert_selector "#requirement-#{berries.id} [data-decision-label]", text: "Missing"
      assert_selector "[data-readiness-state='shopping_needed']", text: "Shopping needed"

      within("#requirement-#{berries.id}") { click_link "Substitute" }
      assert_current_path new_planned_meal_ingredient_substitution_path(berries)
      select_and_wait "Carrots", from: "Replacement ingredient"
      set_and_wait find_field("Amount"), "2"
      find_field("Unit").set("")
      assert_field "substitution_unit", with: ""
      click_button_and_wait_for_path "Save substitution", planned_meal_ingredient_review_path(plan)

      assert_selector "#requirement-#{berries.id}", text: /Substituted → Carrots/
      assert_selector "#requirement-#{berries.id} [data-decision-label]", text: "Check ingredient"

      # The replacement is the ingredient allocation now draws on, so its decision
      # is the one still open. Carrots are not tracked at all, so confirming them
      # on hand writes the evidence the decision asserts and the plan is ready.
      within("#requirement-#{berries.id}") { click_button "On hand" }
      assert_selector "#requirement-#{berries.id} [data-decision-label]", text: "On hand"
      assert_selector "[data-readiness-state='ready_to_cook']", text: "Ready to cook"

      click_link_and_wait_for_path "Back to the week", meal_week_path(date: WEEK_START)
      within("li", text: recipes(:porridge).title) { click_link "Review ingredients" }
      assert_current_path planned_meal_ingredient_review_path(plan)
      assert_selector "#requirement-#{oats.id} [data-decision-label]", text: "On hand"
      assert_selector "#requirement-#{berries.id} [data-decision-label]", text: "On hand"
    end
  end

  test "the fast path answers everything undecided and leaves an explicit choice alone" do
    travel_to WEEK_START do
      plan = PlannedMeal.create!(household: households(:home), recipe: recipes(:porridge), planned_on: WEEK_START)
      requirement(plan, :blueberries).decide!(:not_needed)

      sign_in_via_browser users(:one)
      visit_and_wait_for_path planned_meal_ingredient_review_path(plan)

      click_button_and_wait_for_text "Everything is on hand", "Everything still unanswered is now on hand."

      assert_selector "#requirement-#{requirement(plan, :rolled_oats).id} [data-decision-label]", text: "On hand"
      assert_selector "#requirement-#{requirement(plan, :blueberries).id} [data-decision-label]", text: "Not needed"
      assert_no_button "Everything is on hand"
    end
  end

  test "a competing plan explains the deficit on a phone without naming another person's meal" do
    travel_to WEEK_START do
      original_size = page.current_window.size
      page.current_window.resize_to(390, 844)
      sign_in_via_browser users(:one)
      visit_and_wait_for_path planned_meal_ingredient_review_path(planned_meals(:shared_target_week))

      assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")

      requirement = planned_meal_ingredients(:shared_salad_lettuce)
      within "#requirement-#{requirement.id}" do
        click_button "2 contributing meals"
        assert_selector "[data-contribution-anonymous='true']", text: /Another household plan/
        assert_no_selector "[data-contribution-anonymous='true']", text: /#{Regexp.escape(recipes(:salad).title)}/
        assert_selector "[data-contribution-current='true']", text: /#{Regexp.escape(WEEK_START.to_fs(:long))}/
      end

      # Dark mode is expressed in the markup, not applied by JavaScript.
      assert_includes find("#requirement-#{requirement.id} [data-requirement-fact='required']")[:class], "dark:text-gray-300"
    ensure
      page.current_window.resize_to(original_size[0], original_size[1]) if original_size
    end
  end

  private
    def requirement(plan, ingredient)
      plan.planned_meal_ingredients.active.find_by!(ingredient: ingredients(ingredient))
    end
end
