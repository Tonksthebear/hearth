require "application_system_test_case"

class MealsTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "plans a household meal for the frozen current week" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      select_and_wait recipes(:porridge).title, from: "Planned recipe"
      select_and_wait "Whole household", from: "Plan for"

      click_button_and_wait_for_text "Add to plan", "#{recipes(:porridge).title} was added to the plan."

      assert_selector "li", text: /#{Regexp.escape(recipes(:porridge).title)}\s+Whole household/
    end
  end

  test "plans a meal for the selected person" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      select_and_wait recipes(:porridge).title, from: "Planned recipe"
      select_and_wait people(:one).name, from: "Plan for"

      click_button_and_wait_for_text "Add to plan", "#{recipes(:porridge).title} was added to the plan."

      assert_selector "li", text: /#{Regexp.escape(recipes(:porridge).title)}\s+#{Regexp.escape(people(:one).name)}/
    end
  end

  test "logs a catalog meal for the selected person" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      select_and_wait recipes(:porridge).title, from: "Recipe eaten"

      click_button_and_wait_for_text "Log meal", "#{recipes(:porridge).title} was logged for #{people(:one).name}."

      assert_selector "li", text: /#{Regexp.escape(recipes(:porridge).title)}\s+Catalog recipe/
    end
  end

  test "logs an ad hoc meal without changing the catalog" do
    travel_to WEEK_START do
      recipe_count = Recipe.count
      sign_in_and_open_meals users(:one)
      select_and_wait "No catalog recipe", from: "Recipe eaten"
      fill_in_and_wait_for_value "Ad hoc meal", "Late snack after a movie"

      click_button_and_wait_for_text "Log meal", "Late snack after a movie was logged for #{people(:one).name}."

      assert_selector "li", text: /Late snack after a movie\s+Ad hoc meal/
      assert_equal recipe_count, Recipe.count
    end
  end

  test "switches person context and hides the prior person's private week rows" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      assert_text "Dinner with friends"
      assert_selector "li", text: recipes(:alex_only).title

      switch_person_via_browser people(:two)
      visit_and_wait_for_path meal_week_path

      assert_no_text "Dinner with friends"
      assert_no_selector "li", text: recipes(:alex_only).title
      assert_selector "section[aria-labelledby='day-2026-07-27'] > div > div:first-child li",
        text: recipes(:salad).title
    end
  end

  test "opens household shopping from meals and excludes eaten-only text" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      click_link_and_wait_for_path "Shopping", shopping_list_path
      click_link_and_wait_for_path "Meals", meal_week_path
      click_link_and_wait_for_path "Shopping list", shopping_list_path(date: "2026-07-27")

      assert_text "Carrots"
      assert_text "Lettuce"
      assert_no_text "Dinner with friends"
    end
  end

  private
    def sign_in_and_open_meals(user)
      sign_in_via_browser user
      within "nav[aria-label='Household and person context']" do
        click_link_and_wait_for_path "Meals", meal_week_path
      end
      assert_selector "h1", text: "Meals"
      assert_text WEEK_START.to_fs(:long)
      assert_selector "h3", text: /Planned/i
      assert_selector "h3", text: /Eaten/i
    end
end
