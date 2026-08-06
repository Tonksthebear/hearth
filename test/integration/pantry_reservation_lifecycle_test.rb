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

  # The interaction that existed in neither branch alone: cooking both draws
  # pantry stock and removes the plan from PlannedMeal.allocatable, which is the
  # queue the generated shopping rows are projected from. Entered through the
  # rendered controls on both surfaces.
  test "cooking a plan retires its open deficit rows and undoing regenerates them" do
    travel_to TODAY do
      sign_in_as users(:one)
      plan = deficit_plan
      manual = shopping_list.items.create!(name: "Party napkins", user_managed_at: Time.current)

      get shopping_list_path(date: WEEK_START)

      assert_response :success
      assert_equal({ "Lifecycle beans" => "2", "Lifecycle kale" => "3", "Lifecycle oats" => "3" }, generated_amounts)
      assert_nil generated_row("Lifecycle rice"), "covered requirements generate no shopping work"
      generated_row("Lifecycle kale").complete!
      generated_row("Lifecycle oats").apply_user_attributes(name: "Lifecycle oats (steel cut)")

      get meal_week_path(date: plan.planned_on)
      post submitted_action(planned_meal_meal_path(plan), "post")
      follow_redirect!
      get shopping_list_path(date: WEEK_START)

      assert_response :success
      # Drawn exactly once, clamped to what each row actually held.
      assert_equal [ "confirmed", Rational(2) ], pantry_state("Lifecycle rice")
      assert_equal [ "out", nil ], pantry_state("Lifecycle beans")
      assert_equal({ "Lifecycle rice" => Rational(2), "Lifecycle beans" => Rational(1) }, drawn_amounts(plan))
      # The open generated row goes with the plan that left the queue; the
      # completed tombstone and the user-edited row survive without provenance,
      # and the manual row is never touched.
      assert_nil generated_row("Lifecycle beans")
      assert_predicate generated_row("Lifecycle kale"), :completed?
      assert_equal "Lifecycle oats (steel cut)", generated_row("Lifecycle oats (steel cut)").name
      assert_empty generated_row("Lifecycle kale").shopping_list_item_sources
      assert_empty generated_row("Lifecycle oats (steel cut)").shopping_list_item_sources
      assert_equal [ "Party napkins", nil ], [ manual.reload.name, manual.generated_key ]

      meal = plan.meals.sole
      get meal_path(meal)
      delete submitted_action(meal_path(meal), "delete")
      follow_redirect!
      get shopping_list_path(date: WEEK_START)

      assert_response :success
      # Credit where the evidence still admits it, forfeit where a later
      # assertion — here Hearth's own draw to zero — replaced it.
      assert_equal({ "Lifecycle rice" => "credited", "Lifecycle beans" => "evidence_depleted" }, released_reasons(plan))
      assert_equal [ "confirmed", Rational(4) ], pantry_state("Lifecycle rice")
      assert_equal [ "out", nil ], pantry_state("Lifecycle beans")
      # The plan is allocatable again, so its deficits regenerate. Beans now asks
      # for the whole requirement because the forfeited credit left the row out.
      assert_equal "3", generated_row("Lifecycle beans").quantity
      assert_nil generated_row("Lifecycle rice"), "the credited row covers its requirement again"
      assert_equal 1, generated_row("Lifecycle kale").shopping_list_item_sources.count
      assert_equal 1, generated_row("Lifecycle oats (steel cut)").shopping_list_item_sources.count
    end
  end

  private
    WEEK_START = Date.new(2026, 7, 27)

    # One plan carrying every branch at once: a fully covered requirement that
    # credits back, a partially covered one that draws to zero and forfeits, and
    # two uncovered ones whose rows are completed and user-edited.
    def deficit_plan
      confirm("Lifecycle rice", 4, "cup")
      confirm("Lifecycle beans", 1, "can")
      recipe = households(:home).recipes.create!(
        title: "Lifecycle stew", source_name: "Lifecycle fixture", provenance_status: :observed
      )
      [ [ "Lifecycle rice", "2", "cup" ], [ "Lifecycle beans", "3", "can" ],
        [ "Lifecycle kale", "3", "cup" ], [ "Lifecycle oats", "3", "cup" ] ].each_with_index do |(name, amount, unit), index|
        recipe.recipe_ingredients.create!(display_name: name, display_quantity: amount, unit: unit, position: index + 1)
      end

      PlannedMeal.create!(household: households(:home), recipe: recipe, planned_on: WEEK_START).tap do |plan|
        %w[ Lifecycle\ kale Lifecycle\ oats ].each do |name|
          plan.planned_meal_ingredients.active.find_by!(ingredient: ingredient(name)).decide!(:missing)
        end
      end
    end

    def ingredient(name)
      Ingredient.resolve!(household: households(:home), name: name)
    end

    def confirm(name, quantity, unit)
      PantryItem.for(household: households(:home), ingredient: ingredient(name)).confirm!(
        quantity: quantity, unit: unit, source: "pantry_check", confirmed_by: people(:without_login)
      )
    end

    def pantry_state(name)
      row = households(:home).pantry_items.find_by(ingredient: ingredient(name))
      [ row&.state, row&.quantity ]
    end

    def shopping_list
      ShoppingList.for(household: households(:home), date: WEEK_START)
    end

    def generated_row(name)
      shopping_list.items.reload.find { |item| item.name == name && item.generated_key.present? }
    end

    def generated_amounts
      shopping_list.items.reload.select { |item| item.name.start_with?("Lifecycle") }.to_h { |item| [ item.name, item.quantity ] }
    end

    def drawn_amounts(plan)
      plan.pantry_consumptions.active.to_h { |consumption| [ consumption.ingredient.name, consumption.quantity ] }
    end

    def released_reasons(plan)
      plan.pantry_consumptions.reload.to_h { |consumption| [ consumption.ingredient.name, consumption.released_reason ] }
    end

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
