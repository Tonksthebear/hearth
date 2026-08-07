require "test_helper"

class PlannedMealIngredient::DecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @requirement = planned_meal_ingredients(:shared_salad_lettuce)
    @planned_meal = planned_meals(:shared_target_week)
  end

  test "on hand records the decision and the pantry evidence the rendered control offers" do
    action, params = rendered_control("on_hand")
    pantry_items(:out_lettuce).destroy!

    patch action, params: params

    assert_redirected_to planned_meal_ingredient_review_path(@planned_meal)
    assert_response :see_other
    assert_predicate @requirement.reload, :on_hand?
    pantry = PantryItem.find_by!(household: households(:home), ingredient: ingredients(:lettuce))
    assert_equal [ "confirmed", Rational(1), "head" ], [ pantry.state, pantry.quantity, pantry.unit ]
    assert_equal [ PantryItem::READINESS_REVIEW_SOURCE, people(:one) ], [ pantry.confirmation_source, pantry.confirmed_by ]

    follow_redirect!
    assert_select "#requirement-#{@requirement.id} [data-decision-label]", text: "On hand"
  end

  test "add to list records the decision without touching pantry evidence" do
    action, params = rendered_control("missing")

    assert_no_changes -> { pantry_items(:out_lettuce).reload.updated_at } do
      patch action, params: params
    end

    assert_predicate @requirement.reload, :missing?
    assert_not_nil @requirement.decided_at
  end

  test "not needed resolves the requirement with no shopping work" do
    action, params = rendered_control("not_needed")

    patch action, params: params

    assert_predicate @requirement.reload, :not_needed?
  end

  # The generated row materialises on the next explicit Shopping visit, because
  # writing a child requirement never fires the plan's reconciliation callback.
  test "add to list reaches the shopping list through the household's next Shopping visit" do
    action, params = rendered_control("missing")

    patch action, params: params
    assert_empty shopping_rows_for_lettuce

    get shopping_list_path(date: "2026-07-27")
    assert_response :success
    assert_equal [ "Lettuce" ], shopping_rows_for_lettuce.map(&:name)
  end

  test "marking the requirement on hand withdraws it from the generated shopping row on the next Shopping visit" do
    action, params = rendered_control("missing")
    patch action, params: params
    get shopping_list_path(date: "2026-07-27")
    assert_includes shopping_sources_for_lettuce, @requirement.id

    pantry_items(:out_lettuce).destroy!
    action, params = rendered_control("on_hand")
    patch action, params: params

    get shopping_list_path(date: "2026-07-27")
    assert_response :success
    assert_not_includes shopping_sources_for_lettuce, @requirement.id
    # The one head this plan just confirmed is allocated to it as the earlier
    # meal, so Sam's later plan inherits the shortfall and the row survives with a
    # different contributor. The deficit moved rather than disappearing.
    assert_equal [ planned_meal_ingredients(:sam_salad_lettuce).id ], shopping_sources_for_lettuce
  end

  test "an unrecognised decision is not found and writes nothing" do
    assert_no_changes -> { @requirement.reload.decision } do
      patch planned_meal_ingredient_decision_path(@requirement), params: { decision: "substituted" }
    end

    assert_response :not_found
  end

  test "another person's requirement is not reachable" do
    patch planned_meal_ingredient_decision_path(planned_meal_ingredients(:sam_salad_lettuce)), params: { decision: "missing" }

    assert_response :not_found
  end

  test "a superseded requirement is not reachable" do
    patch planned_meal_ingredient_decision_path(planned_meal_ingredients(:adjacent_free_text_history)), params: { decision: "missing" }

    assert_response :not_found
  end

  test "a cooked plan's requirement can no longer be decided" do
    @planned_meal.convert_for!(people(:one), today: @planned_meal.planned_on)

    assert_no_changes -> { @requirement.reload.decision } do
      patch planned_meal_ingredient_decision_path(@requirement), params: { decision: "missing" }
    end

    assert_response :not_found
  end

  # Proves there is no clear-the-decision endpoint hiding behind the resource
  # rather than merely that no control links to one.
  test "the decision resource offers update only" do
    path = planned_meal_ingredient_decision_path(@requirement)

    assert_equal "planned_meal_ingredient/decisions#update", recognized(path, :patch)
    assert_raises(ActionController::RoutingError) { recognized(path, :delete) }
    assert_raises(ActionController::RoutingError) { recognized(path, :post) }
  end

  private
    # Enters through the page the household actually sees and reuses the control it
    # rendered, so a missing affordance or a mislabelled parameter fails here.
    def rendered_control(decision)
      get planned_meal_ingredient_review_path(@planned_meal)
      assert_response :success
      action = planned_meal_ingredient_decision_path(@requirement)
      # One form per offered decision, each submitting the same action as a PATCH.
      assert_select "form[action=?][method='post']", action, count: 3
      assert_select "form[action=?] input[name='_method'][value='patch']", action, count: 3
      assert_select "form[action=?] input[name='decision'][value=?]", action, decision, count: 1
      [ action, { decision: decision } ]
    end

    def recognized(path, method)
      route = Rails.application.routes.recognize_path(path, method: method)
      "#{route[:controller]}##{route[:action]}"
    end

    def shopping_rows_for_lettuce
      ShoppingListItem.where(ingredient: ingredients(:lettuce)).where.not(generated_key: nil).to_a
    end

    def shopping_sources_for_lettuce
      ShoppingListItemSource.where(shopping_list_item: shopping_rows_for_lettuce).pluck(:planned_meal_ingredient_id)
    end
end
