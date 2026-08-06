require "test_helper"

class PlannedMeal::IngredientReviewsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the review renders every required fact and offers all four row actions" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)

    get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))

    assert_response :success
    assert_select "h1", text: recipes(:salad).title
    # Out is definitive evidence, so the requirement resolves to a full deficit
    # even though the household has not made a decision about it yet.
    assert_select "[data-readiness-state='shopping_needed']", text: /Shopping needed/
    assert_select "#requirement-#{requirement.id}" do
      assert_select "[data-requirement-fact='required']", text: /1 head/
      assert_select "[data-requirement-fact='pantry']", text: /Out/
      assert_select "[data-requirement-fact='queued-demand']", text: /2 head/
      assert_select "[data-requirement-fact='reserved']", text: /0 head/
      assert_select "[data-requirement-fact='deficit']", text: /1 head/
      assert_select "[data-decision-label]", text: "Check ingredient"
    end
    assert_select "form[action=?]", planned_meal_ingredient_decision_path(requirement), count: 3
    assert_select "a[href=?]", new_planned_meal_ingredient_substitution_path(requirement)
    assert_select "a[href=?]", meal_week_path(date: MealWeek.for(household: households(:home), person: people(:one), date: "2026-07-27"))
  end

  test "a household-shared plan is visible while another person's plan is not" do
    get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))
    assert_response :success

    get planned_meal_ingredient_review_path(planned_meals(:sam_target_week))
    assert_response :not_found
  end

  test "a cooked plan renders a terminal state with no actions" do
    plan = planned_meals(:shared_target_week)
    plan.convert_for!(people(:one), today: plan.planned_on)

    get planned_meal_ingredient_review_path(plan)

    assert_response :success
    assert_select "p", text: /This plan has been cooked/
    assert_select "form[action=?]", planned_meal_ingredient_decision_path(planned_meal_ingredients(:shared_salad_lettuce)), count: 0
    assert_select "form[action=?]", planned_meal_on_hand_confirmation_path(plan), count: 0
  end

  test "the fast path is offered only while something is still unanswered" do
    get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))
    assert_select "form[action=?]", planned_meal_on_hand_confirmation_path(planned_meals(:shared_target_week))

    planned_meal_ingredients(:shared_salad_lettuce).decide!(:not_needed)

    get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))
    assert_select "form[action=?]", planned_meal_on_hand_confirmation_path(planned_meals(:shared_target_week)), count: 0
  end

  test "another person's contributing plan keeps its date and amount but never its identity" do
    planned_meal_ingredients(:shared_salad_lettuce).decide!(:missing)

    get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))

    assert_response :success
    assert_select "[data-contribution-anonymous='true']", text: /Another household plan/
    assert_select "[data-contribution-anonymous='true']", text: /#{Regexp.escape(recipes(:salad).title)}/, count: 0
    assert_select "[data-contribution-current='true']", text: /#{Regexp.escape(planned_meals(:shared_target_week).planned_on.to_fs(:long))}/
  end

  test "the review renders the Meals area as the active navigation" do
    get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))

    assert_select "a[aria-current='page']", text: "Week"
  end

  test "query work stays constant as the household queues more competing demand" do
    queries_for_review
    baseline = queries_for_review
    assert_equal baseline, queries_for_review, "the measurement itself must be stable before it can prove anything"

    4.times do |index|
      recipe = households(:home).recipes.create!(
        title: "Competing salad #{index}", source_name: "Bounded fixture", provenance_status: :observed
      )
      recipe.recipe_ingredients.create!(display_name: "Lettuce", display_quantity: "1", unit: "head", position: 1)
      PlannedMeal.create!(household: households(:home), recipe: recipe, planned_on: "2026-07-30")
    end

    assert_equal baseline, queries_for_review
    assert_select "#ingredient-requirements > li", count: 1
  end

  private
    # Every statement the render issues, cached or not. Repeat requests inside one
    # integration test are served from the query cache, so counting only uncached
    # statements would report zero for the second measurement and prove nothing.
    def queries_for_review
      statements = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        statements += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end
      get planned_meal_ingredient_review_path(planned_meals(:shared_target_week))
      assert_response :success
      statements
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
end
