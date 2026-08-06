require "test_helper"

# The cook-and-undo workflow entered the way a household enters it: render the
# meal week, submit the control that page actually offers, follow the result, and
# only then inspect the pantry and its consumption ledger. A direct POST or
# DELETE with a synthetic params hash would still pass if the control were
# missing, mis-targeted, or the result page raised.
class PantryReservationLifecycleTest < ActionDispatch::IntegrationTest
  TODAY = Time.zone.local(2026, 7, 31, 12)

  test "cooking a planned meal from the meal week draws its stock and undoing credits it back" do
    travel_to TODAY do
      sign_in_as users(:one)
      plan = planned_meals(:shared_target_week)
      stock = confirm_lettuce(2)

      get meal_week_path(date: plan.planned_on)

      assert_response :success
      assert_select "form[action=?][method=?]", planned_meal_meal_path(plan), "post"

      post submitted_action(planned_meal_meal_path(plan), "post")
      follow_redirect!

      meal = plan.meals.sole
      assert_response :success
      assert_select "h1", text: meal.description
      assert_select "p", text: /#{meal.description} was logged for #{people(:one).name}/
      assert_equal [ "confirmed", Rational(1) ], [ stock.reload.state, stock.quantity ]
      consumption = plan.pantry_consumptions.sole
      assert_equal [ Rational(1), "head", true ], [ consumption.quantity, consumption.unit, consumption.active? ]

      get meal_path(meal)

      assert_response :success
      assert_select "form[action=?]", meal_path(meal)

      delete submitted_action(meal_path(meal), "delete")
      follow_redirect!

      assert_response :success
      assert_select "p", text: /#{meal.description} was removed from #{people(:one).name}'s meals/
      assert_empty plan.meals.reload
      assert_equal [ "confirmed", Rational(2) ], [ stock.reload.state, stock.quantity ]
      assert_equal "credited", consumption.reload.released_reason
      assert_empty plan.pantry_consumptions.active
    end
  end

  test "logging is offered and consumes nothing when the household has no confirmed stock" do
    travel_to TODAY do
      sign_in_as users(:one)
      plan = planned_meals(:shared_target_week)

      get meal_week_path(date: plan.planned_on)

      assert_response :success
      assert_select "form[action=?][method=?]", planned_meal_meal_path(plan), "post"

      post submitted_action(planned_meal_meal_path(plan), "post")
      follow_redirect!

      assert_response :success
      assert_equal 1, plan.meals.count
      assert_equal "out", pantry_items(:out_lettuce).reload.state
      assert_empty plan.pantry_consumptions
    end
  end

  private
    def confirm_lettuce(quantity)
      pantry_items(:out_lettuce).tap do |item|
        item.confirm!(quantity: quantity, unit: "head", source: "pantry_check", confirmed_by: people(:without_login))
      end
    end

    # The path the rendered control actually submits to, so a view that stops
    # offering the action or retargets it fails here instead of being bypassed.
    def submitted_action(expected, method)
      form = css_select("form[action='#{expected}']").first
      assert form, "The rendered page offers no #{method} control for #{expected}"
      assert_equal method, form_method(form)
      form["action"]
    end

    def form_method(form)
      override = form.css("input[name='_method']").first
      override ? override["value"] : form["method"]
    end
end
