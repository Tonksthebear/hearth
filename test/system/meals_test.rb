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

  test "logs free text in two activations from the week" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      recipe_count = Recipe.count

      click_link_and_wait_for_path "Log meal", new_meal_path(date: WEEK_START)
      assert_field "Food or meal", focused: true
      fill_in_and_wait_for_value "Food or meal", "Late snack after a movie"

      click_button_and_wait_for_text "Log meal", "Late snack after a movie was logged for #{people(:one).name}."
      assert_selector "h1", text: "Late snack after a movie"
      assert_equal recipe_count, Recipe.count
    end
  end

  test "creates edits and shows recipe ingredient and free text items after Turbo replacements" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      click_link_and_wait_for_path "Log meal", new_meal_path(date: WEEK_START)
      fill_in_and_wait_for_value "Food or meal", "Side salad"

      click_button_and_wait_for_count "Add recipe", "li[data-meal-item-kind]", 2
      recipe_control_id = within("li[data-meal-item-kind='recipe']") { find("label", text: "Recipe", match: :prefer_exact)[:for] }
      select_and_wait recipes(:porridge).title, from: recipe_control_id
      within "li[data-meal-item-kind='recipe']" do
        find("input[aria-label='Portion amount']").set("1.5")
        find("input[aria-label='Portion unit']").set("servings")
        fill_in "Substitutions", with: "Use oat milk"
      end

      click_button_and_wait_for_count "Add ingredient", "li[data-meal-item-kind]", 3
      ingredient_control_id = within("li[data-meal-item-kind='ingredient']") { find("label", text: "Ingredient", match: :prefer_exact)[:for] }
      select_and_wait ingredients(:blueberries).name, from: ingredient_control_id
      within "li[data-meal-item-kind='ingredient']" do
        fill_in "Item notes", with: "A handful"
      end
      within "li[data-meal-item-kind='recipe']" do
        fill_in "Recipe feedback (optional)", with: "Good base for breakfast."
      end

      click_button "Log meal"
      assert_text "Side salad, #{recipes(:porridge).title}, and #{ingredients(:blueberries).name} was logged", wait: 5
      assert_link recipes(:porridge).title
      assert_text "1.5 servings"
      assert_text "Use oat milk"
      assert_text "Good base for breakfast."

      meal = Meal.joins(:meal_items).find_by!(meal_items: { snapshot_label: "Side salad" })
      surviving_item = meals(:alex_recipe_target_week).meal_items.create!(
        source_kind: :recipe, recipe: recipes(:porridge), position: 2
      )
      surviving_item.create_recipe_feedback!(body: "Feedback from another meal remains.")
      click_link_and_wait_for_path "Edit meal", edit_meal_path(meal)
      within "li[data-meal-item-kind='recipe']" do
        fill_in "Recipe feedback (optional)", with: "Excellent with less sweetener."
      end
      within "li[data-meal-item-kind='free_text']" do
        click_button "Remove"
      end
      assert_selector "li[data-meal-item-kind]", count: 2, wait: 5

      click_button "Save meal"
      assert_text "was updated", wait: 5
      assert_no_text "Side salad"
      assert_text "Excellent with less sweetener."

      click_link_and_wait_for_path recipes(:porridge).title, recipe_path(recipes(:porridge))
      assert_text "Excellent with less sweetener."
      assert_text "Feedback from another meal remains."
      assert_text people(:one).name

      visit_and_wait_for_path edit_meal_path(meal)
      within "li[data-meal-item-kind='recipe']" do
        click_button "Remove"
      end
      assert_selector "li[data-meal-item-kind]", count: 1, wait: 5
      click_button "Save meal"
      assert_text "was updated", wait: 5

      visit_and_wait_for_path recipe_path(recipes(:porridge))
      assert_no_text "Excellent with less sweetener."
      assert_text "Feedback from another meal remains."
    end
  end

  test "converts a shared plan once per person on the planned day" do
    travel_to Time.zone.local(2026, 7, 31, 12) do
      sign_in_and_open_meals users(:one)
      plan = planned_meals(:shared_target_week)

      within "li", text: plan.recipe.title, match: :first do
        click_button "Log as eaten"
      end
      assert_text "was logged for #{people(:one).name}", wait: 5
      alex_meal = plan.meals.find_by!(person: people(:one))
      assert_current_path meal_path(alex_meal), wait: 5
      assert_equal plan.planned_on, alex_meal.eaten_on

      assert_link "Back to meals", href: meal_week_path(date: plan.planned_on)
      visit_and_wait_for_path meal_week_path(date: plan.planned_on)
      within "li", text: plan.recipe.title, match: :first do
        assert_link "View logged meal"
        assert_no_button "Log as eaten"
      end

      sign_in_as_person_via_browser people(:two)
      visit_and_wait_for_path meal_week_path(date: plan.planned_on)
      within "li", text: plan.recipe.title, match: :first do
        click_button "Log as eaten"
      end
      assert_text "was logged for #{people(:two).name}", wait: 5
      sam_meal = plan.meals.find_by!(person: people(:two))
      assert_current_path meal_path(sam_meal), wait: 5
      refute_equal alex_meal.id, sam_meal.id
    end
  end

  test "future plan has no conversion action" do
    travel_to Time.zone.local(2026, 7, 31, 12) do
      sign_in_and_open_meals users(:one)
      visit_and_wait_for_path meal_week_path(date: "2026-08-03")

      within "li", text: planned_meals(:adjacent_week).recipe.title, match: :first do
        assert_no_button "Log as eaten"
      end
    end
  end

  test "switches person context and hides the prior person's private week rows" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      assert_text "Dinner with friends"
      assert_selector "li", text: recipes(:alex_only).title

      sign_in_as_person_via_browser people(:two)
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

  test "logs a visible recipe serving and renders its historical nutrition snapshot" do
    travel_to WEEK_START do
      sign_in_and_open_meals users(:one)
      click_link_and_wait_for_path "Log meal", new_meal_path(date: WEEK_START)
      fill_in_and_wait_for_value "Food or meal", "Side"
      click_button_and_wait_for_count "Add recipe", "li[data-meal-item-kind]", 2

      recipe_control_id = within "li[data-meal-item-kind='recipe']" do
        assert_selector "input[aria-label='Portion amount'][value='1']"
        assert_selector "input[aria-label='Portion unit'][value='servings']"
        find("label", text: "Recipe", match: :prefer_exact)[:for]
      end
      select_and_wait recipes(:salad).title, from: recipe_control_id

      click_button "Log meal"
      assert_text "was logged", wait: 5
      assert_selector "#meal-nutrition-heading", text: "Nutrition snapshot"
      assert_text "6.18 g"
      assert_text(/estimated/i)
    end
  end

  private
    def sign_in_and_open_meals(user)
      sign_in_via_browser user
      within "nav[aria-label='Primary']" do
        click_link_and_wait_for_path "Meals", meal_week_path
      end
      assert_selector "h1", text: "Meals"
      assert_text WEEK_START.to_fs(:long)
      assert_selector "h3", text: /Planned/i
      assert_selector "h3", text: /Eaten/i
    end
end
