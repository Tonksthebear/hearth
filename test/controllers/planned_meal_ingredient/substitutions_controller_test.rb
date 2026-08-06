require "test_helper"

class PlannedMealIngredient::SubstitutionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @requirement = planned_meal_ingredients(:shared_salad_lettuce)
    @planned_meal = planned_meals(:shared_target_week)
  end

  test "the form is reached from the review and prefills the requirement's own amount" do
    get planned_meal_ingredient_review_path(@planned_meal)
    assert_select "a[href=?]", new_planned_meal_ingredient_substitution_path(@requirement)

    get new_planned_meal_ingredient_substitution_path(@requirement)

    assert_response :success
    assert_select "form[action=?]", planned_meal_ingredient_substitution_path(@requirement)
    assert_select "input[name=?][value=?]", "substitution[quantity]", "1"
    assert_select "input[name=?][value=?]", "substitution[unit]", "head"
    assert_select "select[name=?] option", "substitution[name]"
  end

  test "substituting a new ingredient creates it and redirects to the review" do
    assert_difference "Ingredient.count", 1 do
      post planned_meal_ingredient_substitution_path(@requirement),
        params: { substitution: { name: "Little gem", quantity: "2", unit: "head" } }
    end

    assert_redirected_to planned_meal_ingredient_review_path(@planned_meal)
    assert_response :see_other
    @requirement.reload
    assert_predicate @requirement, :substituted?
    assert_equal "Little gem", @requirement.replacement_display_name
    assert_equal Rational(2), @requirement.replacement_quantity
    assert_equal "unknown", @requirement.replacement_decision

    follow_redirect!
    assert_select "#requirement-#{@requirement.id}", text: /Substituted → Little gem/
    assert_select "form[action=?]", planned_meal_ingredient_replacement_decision_path(@requirement)
  end

  test "an existing household ingredient is reused rather than duplicated" do
    assert_no_difference "Ingredient.count" do
      post planned_meal_ingredient_substitution_path(@requirement),
        params: { substitution: { name: "blueberries", quantity: "1", unit: "cup" } }
    end

    assert_equal ingredients(:blueberries), @requirement.reload.replacement_ingredient
  end

  test "a blank name re-renders the form and substitutes nothing" do
    assert_no_difference "Ingredient.count" do
      post planned_meal_ingredient_substitution_path(@requirement),
        params: { substitution: { name: "  ", quantity: "1", unit: "head" } }
    end

    assert_response :unprocessable_entity
    assert_select "#substitution-errors", text: /must describe the replacement/
    assert_predicate @requirement.reload, :unknown?
  end

  test "another person's requirement cannot be substituted" do
    get new_planned_meal_ingredient_substitution_path(planned_meal_ingredients(:sam_salad_lettuce))
    assert_response :not_found

    post planned_meal_ingredient_substitution_path(planned_meal_ingredients(:sam_salad_lettuce)),
      params: { substitution: { name: "Little gem", quantity: "1", unit: "head" } }
    assert_response :not_found
  end

  test "a cooked plan's requirement cannot be substituted" do
    @planned_meal.convert_for!(people(:one), today: @planned_meal.planned_on)

    get new_planned_meal_ingredient_substitution_path(@requirement)

    assert_response :not_found
  end
end
