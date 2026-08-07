require "test_helper"

class Household::PantryAllocationTest < ActiveSupport::TestCase
  MONDAY = Date.new(2026, 8, 10)
  TUESDAY = Date.new(2026, 8, 11)
  THURSDAY = Date.new(2026, 8, 13)
  FRIDAY = Date.new(2026, 8, 14)

  test "limited stock fills the earlier meal first and leaves the later one short" do
    confirm("Beans", 3, "can")
    monday = plan(MONDAY, line("Beans", "2", "can"))
    friday = plan(FRIDAY, line("Beans", "2", "can"))
    requirement(monday, "Beans").decide!(:on_hand)
    requirement(friday, "Beans").decide!(:missing)

    allocated = allocation

    assert_predicate allocated.readiness_for(monday), :ready_to_cook?
    assert_equal Rational(2), reserved(allocated, monday)
    assert_predicate allocated.readiness_for(friday), :shopping_needed?
    assert_equal [ Rational(1), Rational(1) ], [ reserved(allocated, friday), deficit(allocated, friday) ]
    assert_equal Rational(3), allocated.reserved_for(ingredient("Beans"))
    assert_equal Rational(0), allocated.remaining_for(ingredient("Beans"))
  end

  test "known stock resolves undecided requirements and is never reserved twice" do
    confirm("Rice", 4, "cup")
    monday = plan(MONDAY, line("Rice", "2", "cup"))
    thursday = plan(THURSDAY, line("Rice", "2", "cup"))

    allocated = allocation

    assert_predicate allocated.readiness_for(monday), :ready_to_cook?
    assert_predicate allocated.readiness_for(thursday), :ready_to_cook?
    assert_equal [ Rational(2), Rational(2) ], [ reserved(allocated, monday), reserved(allocated, thursday) ]
    assert_equal Rational(4), allocated.reserved_for(ingredient("Rice"))
    assert_equal Rational(0), allocated.remaining_for(ingredient("Rice"))
    assert_predicate requirement(monday, "Rice"), :unknown?
  end

  test "an explicit priority moves stock to a later meal without moving any date" do
    confirm("Chicken", 1, "package")
    salad = plan(MONDAY, line("Chicken", "1", "package"))
    roast = plan(FRIDAY, line("Chicken", "1", "package"))
    requirement(salad, "Chicken").decide!(:missing)
    requirement(roast, "Chicken").decide!(:on_hand)

    roast.prioritize_before!(salad)
    allocated = allocation

    assert_predicate allocated.readiness_for(roast), :ready_to_cook?
    assert_equal Rational(1), reserved(allocated, roast)
    assert_predicate allocated.readiness_for(salad), :shopping_needed?
    assert_equal [ Rational(0), Rational(1) ], [ reserved(allocated, salad), deficit(allocated, salad) ]
    assert_equal Rational(1), allocated.reserved_for(ingredient("Chicken"))
    assert_equal [ MONDAY, FRIDAY ], [ salad.reload.planned_on, roast.reload.planned_on ]
  end

  test "rescheduling hands the reservation to the next meal exactly once" do
    confirm("Tofu", 1, "block")
    stir_fry = plan(TUESDAY, line("Tofu", "1", "block"))
    curry = plan(THURSDAY, line("Tofu", "1", "block"))
    requirement(stir_fry, "Tofu").decide!(:on_hand)
    requirement(curry, "Tofu").decide!(:missing)
    assert_equal Rational(1), reserved(allocation, stir_fry)
    pantry = pantry_snapshot

    stir_fry.update!(planned_on: Date.new(2026, 8, 15))
    allocated = allocation

    assert_predicate allocated.readiness_for(curry), :ready_to_cook?
    assert_equal Rational(1), reserved(allocated, curry)
    assert_equal [ Rational(0), Rational(1) ], [ reserved(allocated, stir_fry), deficit(allocated, stir_fry) ]
    assert_equal Rational(1), allocated.reserved_for(ingredient("Tofu"))
    assert_equal pantry, pantry_snapshot
  end

  test "an ingredient with no pantry evidence stays unresolved without a deficit" do
    soup = plan(MONDAY, line("Broth", "1", "cup"))

    allocated = allocation
    reservation = allocated.reservations_for(soup).sole

    assert_predicate allocated.readiness_for(soup), :needs_ingredient_check?
    assert_not reservation.resolved_for_readiness?
    assert_not reservation.deficit?
    assert_nil reservation.deficit_quantity
    assert_equal Rational(0), reservation.reserved_quantity
    assert_nil allocated.available_for(ingredient("Broth"))
  end

  test "out supplies zero and resolves while low leaves the requirement open" do
    empty = plan(MONDAY, line("Molasses", "1", "cup"))
    short = plan(MONDAY, line("Vinegar", "1", "cup"))
    pantry_item("Molasses").mark_out!(source: "pantry_check", confirmed_by: people(:without_login))
    pantry_item("Vinegar").mark_low!(source: "pantry_check", confirmed_by: people(:without_login))

    allocated = allocation

    assert_predicate allocated.readiness_for(empty), :shopping_needed?
    assert_equal Rational(1), deficit(allocated, empty)
    assert_equal Rational(0), allocated.available_for(ingredient("Molasses"))
    assert_predicate allocated.readiness_for(short), :needs_ingredient_check?
    assert_nil deficit(allocated, short)
    assert_nil allocated.available_for(ingredient("Vinegar"))
  end

  test "confirmed evidence in an incompatible family neither resolves nor allocates" do
    confirm("Honey", 2, "cup")
    drizzle = plan(MONDAY, line("Honey", "200", "g"))

    allocated = allocation
    reservation = allocated.reservations_for(drizzle).sole

    assert_predicate allocated.readiness_for(drizzle), :needs_ingredient_check?
    assert_not reservation.resolved_for_readiness?
    assert_equal Rational(0), reservation.reserved_quantity
    assert_equal Rational(2), allocated.remaining_for(ingredient("Honey"))
  end

  test "an unresolved requirement outranks a confirmed deficit beside it" do
    bowl = plan(MONDAY, line("Quinoa", "1", "cup"), line("Dressing", "2", "tbsp"))
    requirement(bowl, "Quinoa").decide!(:missing)

    allocated = allocation

    assert_predicate allocated.readiness_for(bowl), :needs_ingredient_check?
    assert_equal Rational(1), reservation(allocated, bowl, "Quinoa").deficit_quantity
    assert_predicate reservation(allocated, bowl, "Quinoa"), :deficit?
    assert_not reservation(allocated, bowl, "Dressing").resolved_for_readiness?
  end

  test "a substitution draws against the replacement and leaves the recipe line untouched" do
    pasta = plan(MONDAY, line("Parmesan", "1", "cup"))
    requirement(pasta, "Parmesan").substitute!(
      ingredient: ingredient("Nutritional yeast"),
      display_quantity: "1",
      unit: "cup"
    )

    unresolved = allocation.reservations_for(pasta).sole
    assert_predicate allocation.readiness_for(pasta), :needs_ingredient_check?
    assert_not unresolved.resolved_for_readiness?
    assert_equal ingredient("Nutritional yeast"), unresolved.ingredient

    confirm("Nutritional yeast", 1, "cup")
    allocated = allocation

    assert_predicate allocated.readiness_for(pasta), :ready_to_cook?
    assert_equal Rational(1), reserved(allocated, pasta)
    assert_equal Rational(0), allocated.remaining_for(ingredient("Nutritional yeast"))
    assert_nil allocated.available_for(ingredient("Parmesan"))
    assert_equal [ "Parmesan", "cup", Rational(1) ], pasta.recipe.recipe_ingredients.sole
      .then { |line| [ line.display_name, line.unit, line.quantity ] }
  end

  test "a numeric unitless requirement allocates against a compatible count" do
    confirm("Avocado", 2)
    toast = plan(MONDAY, line("Avocado", "2", nil))
    requirement(toast, "Avocado").decide!(:on_hand)

    allocated = allocation
    reservation = allocated.reservations_for(toast).sole

    assert_predicate allocated.readiness_for(toast), :ready_to_cook?
    assert_equal Rational(2), reservation.reserved_quantity
    assert_equal "count", reservation.unit
    assert_equal Rational(0), allocated.remaining_for(ingredient("Avocado"))
  end

  test "a plan scale multiplies demand without rewriting the authored amount" do
    confirm("Chickpeas", 2, "can")
    double_batch = plan(MONDAY, line("Chickpeas", "1", "can"), recipe_scale: 2)
    requirement(double_batch, "Chickpeas").decide!(:on_hand)

    allocated = allocation
    reservation = allocated.reservations_for(double_batch).sole

    assert_predicate allocated.readiness_for(double_batch), :ready_to_cook?
    assert_equal [ Rational(2), Rational(2), "1" ],
      [ reservation.required_quantity, reservation.reserved_quantity, reservation.display_quantity ]
    assert_equal Rational(1), double_batch.recipe.recipe_ingredients.sole.quantity
  end

  test "an unparseable amount is never allocated and stays faithful" do
    soup = plan(MONDAY, line("Salt", "to taste", nil))

    unresolved = allocation.reservations_for(soup).sole
    assert_predicate allocation.readiness_for(soup), :needs_ingredient_check?
    assert_not unresolved.measurable?
    assert_nil unresolved.reserved_quantity
    assert_not unresolved.deficit?

    requirement(soup, "Salt").decide!(:missing)
    allocated = allocation
    reservation = allocated.reservations_for(soup).sole

    assert_predicate allocated.readiness_for(soup), :shopping_needed?
    assert_predicate reservation, :deficit?
    assert_nil reservation.deficit_quantity
    assert_equal "to taste", reservation.display_quantity
  end

  test "superseded requirements leave readiness and stop drawing stock" do
    confirm("Parsnips", 4, "cup")
    soup = plan(MONDAY, line("Parsnips", "2", "cup"))
    requirement(soup, "Parsnips").decide!(:on_hand)

    soup.recipe.recipe_ingredients.sole.update!(display_quantity: "4")

    allocated = allocation
    reservation = allocated.reservations_for(soup).sole

    assert_equal 1, soup.planned_meal_ingredients.superseded.count
    assert_equal [ Rational(4), Rational(4) ], [ reservation.required_quantity, reservation.reserved_quantity ]
    assert_equal Rational(4), allocated.reserved_for(ingredient("Parsnips"))
    assert_predicate allocated.readiness_for(soup), :ready_to_cook?
  end

  test "a plan assigned to another person still competes for household stock" do
    confirm("Lentils", 1, "cup")
    sam_dinner = plan(MONDAY, line("Lentils", "1", "cup"), person: people(:two))
    alex_lunch = plan(FRIDAY, line("Lentils", "1", "cup"), person: people(:one))

    allocated = allocation

    assert_equal Rational(1), reserved(allocated, sam_dinner)
    assert_equal Rational(0), reserved(allocated, alex_lunch)
    assert_not_includes MealWeek.for(household: households(:home), person: people(:one), date: MONDAY).planned_meals,
      sam_dinner
  end

  test "cooking a shared plan consumes its reservation exactly once however many people log it" do
    confirm("Barley", 1, "cup")
    shared = plan(MONDAY, line("Barley", "1", "cup"))
    later = plan(FRIDAY, line("Barley", "1", "cup"))
    assert_equal Rational(1), reserved(allocation, shared)

    shared.convert_for!(people(:one), today: MONDAY)
    after_first = allocation

    # The plan leaves the queue and takes its stock with it: cooking is the
    # household action that turns a reservation into consumption.
    assert_nil after_first.readiness_for(shared)
    assert_predicate pantry_item("Barley"), :out?
    assert_equal [ Rational(0), Rational(1) ], [ reserved(after_first, later), deficit(after_first, later) ]

    shared.convert_for!(people(:two), today: MONDAY)
    after_second = allocation

    assert_nil after_second.readiness_for(shared)
    assert_equal [ Rational(0), Rational(1) ], [ reserved(after_second, later), deficit(after_second, later) ]
    assert_equal [ Rational(1) ], shared.pantry_consumptions.active.map(&:quantity)
  end

  test "cooking a person's own plan consumes its reservation" do
    confirm("Millet", 1, "cup")
    alex_plan = plan(MONDAY, line("Millet", "1", "cup"), person: people(:one))
    later = plan(FRIDAY, line("Millet", "1", "cup"))

    alex_plan.convert_for!(people(:one), today: MONDAY)
    allocated = allocation

    assert_nil allocated.readiness_for(alex_plan)
    assert_predicate pantry_item("Millet"), :out?
    assert_equal [ Rational(0), Rational(1) ], [ reserved(allocated, later), deficit(allocated, later) ]
  end

  test "a past plan that was never cooked keeps its place ahead of later meals" do
    confirm("Bulgur", 1, "cup")
    stale = plan(Date.new(2026, 1, 5), line("Bulgur", "1", "cup"))
    upcoming = plan(FRIDAY, line("Bulgur", "1", "cup"))

    allocated = allocation

    assert_equal Rational(1), reserved(allocated, stale)
    assert_equal Rational(0), reserved(allocated, upcoming)
  end

  test "a not-needed requirement resolves without drawing stock or reporting a shortfall" do
    confirm("Sesame", 1, "cup")
    garnish = plan(MONDAY, line("Sesame", "1", "cup"))
    requirement(garnish, "Sesame").decide!(:not_needed)

    allocated = allocation
    reservation = allocated.reservations_for(garnish).sole

    assert_predicate allocated.readiness_for(garnish), :ready_to_cook?
    assert_equal Rational(0), reservation.reserved_quantity
    assert_not reservation.deficit?
    assert_equal Rational(1), allocated.remaining_for(ingredient("Sesame"))
  end

  test "a requirement decided on hand still reports the shortfall allocation could not cover" do
    braise = plan(MONDAY, line("Saffron", "1", "g"))
    requirement(braise, "Saffron").decide!(:on_hand)

    allocated = allocation

    assert_predicate allocated.readiness_for(braise), :shopping_needed?
    assert_equal [ Rational(0), Rational(1) ], [ reserved(allocated, braise), deficit(allocated, braise) ]
  end

  test "a plan with no active requirements is ready to cook" do
    empty = PlannedMeal.create!(household: households(:home), recipe: recipes(:alex_only), planned_on: MONDAY)

    allocated = allocation

    assert_predicate allocated.readiness_for(empty), :ready_to_cook?
    assert_empty allocated.reservations_for(empty)
  end

  test "cross-unit reservations stay exact rationals" do
    confirm("Olive oil", 1, "cup")
    monday = plan(MONDAY, line("Olive oil", "10", "tbsp"))
    friday = plan(FRIDAY, line("Olive oil", "10", "tbsp"))
    requirement(monday, "Olive oil").decide!(:on_hand)
    requirement(friday, "Olive oil").decide!(:on_hand)

    allocated = allocation

    assert_equal Rational(10), reserved(allocated, monday)
    assert_instance_of Rational, reserved(allocated, monday)
    assert_equal [ Rational(6), Rational(4) ], [ reserved(allocated, friday), deficit(allocated, friday) ]
    assert_equal Rational(1), allocated.reserved_for(ingredient("Olive oil"))
    assert_equal Rational(0), allocated.remaining_for(ingredient("Olive oil"))
  end

  test "a fresh engine reflects pantry, priority, and decision changes with no invalidation step" do
    confirm("Farro", 1, "cup")
    first = plan(MONDAY, line("Farro", "1", "cup"))
    second = plan(FRIDAY, line("Farro", "1", "cup"))

    assert_equal [ Rational(1), Rational(0) ], farro_reservations(first, second)
    assert_equal farro_reservations(first, second), farro_reservations(first, second)

    second.prioritize_before!(first)
    assert_equal [ Rational(0), Rational(1) ], farro_reservations(first, second)

    confirm("Farro", 2, "cup")
    assert_equal [ Rational(1), Rational(1) ], farro_reservations(first, second)

    requirement(first, "Farro").decide!(:not_needed)
    assert_equal [ Rational(0), Rational(1) ], farro_reservations(first, second)
  end

  test "computing readiness changes no ingredient decision and no pantry row" do
    confirm("Beans", 3, "can")
    monday = plan(MONDAY, line("Beans", "2", "can"))
    plan(FRIDAY, line("Beans", "2", "can"), line("Salt", "to taste", nil))
    requirement(monday, "Beans").substitute!(ingredient: ingredient("Rice"), display_quantity: "1", unit: "cup")
    before = [ requirement_snapshot, pantry_snapshot ]

    3.times { allocation }

    assert_equal before, [ requirement_snapshot, pantry_snapshot ]
  end

  test "contributions record every competing plan in the order stock was handed out" do
    confirm("Beans", 3, "can")
    monday = plan(MONDAY, line("Beans", "2", "can"))
    friday = plan(FRIDAY, line("Beans", "2", "can"))

    allocated = allocation
    contributions = allocated.contributions_for(ingredient("Beans"))

    assert_equal [ monday, friday ], contributions.map(&:planned_meal)
    assert_equal [ Rational(2), Rational(1) ], contributions.map { |contribution| contribution.reservation.reserved_quantity }
  end

  test "a not needed or unmeasurable requirement is never recorded as a contribution" do
    confirm("Beans", 3, "can")
    monday = plan(MONDAY, line("Beans", "2", "can"))
    skipped = plan(FRIDAY, line("Beans", "1", "can"))
    requirement(skipped, "Beans").decide!(:not_needed)
    plan(THURSDAY, line("Beans", "a handful", nil))

    assert_equal [ monday ], allocation.contributions_for(ingredient("Beans")).map(&:planned_meal)
  end

  test "the pantry row for an ingredient is answered without a further query" do
    confirm("Beans", 3, "can")
    plan(MONDAY, line("Beans", "2", "can"))
    beans = ingredient("Beans")
    untracked = ingredient("Untracked spice")
    allocated = allocation

    # A review renders one row per requirement, so a per-row pantry lookup would
    # grow the page's query count with the recipe.
    assert_no_queries do
      assert_equal Rational(3), allocated.pantry_item_for(beans).quantity
      assert_nil allocated.pantry_item_for(untracked)
    end
  end

  private
    def allocation
      Household::PantryAllocation.new(households(:home))
    end

    def line(display_name, display_quantity, unit)
      { display_name: display_name, display_quantity: display_quantity, unit: unit }
    end

    def plan(planned_on, *lines, person: nil, recipe_scale: 1)
      recipe = households(:home).recipes.create!(
        title: "Allocation plan #{planned_on} #{lines.first.fetch(:display_name)}",
        source_name: "Allocation fixture",
        provenance_status: :observed
      )
      lines.each_with_index { |attributes, index| recipe.recipe_ingredients.create!(**attributes, position: index + 1) }

      PlannedMeal.create!(
        household: households(:home),
        recipe: recipe,
        planned_on: planned_on,
        person: person,
        recipe_scale: recipe_scale
      )
    end

    def ingredient(name)
      Ingredient.resolve!(household: households(:home), name: name)
    end

    def pantry_item(name)
      PantryItem.for(household: households(:home), ingredient: ingredient(name))
    end

    def confirm(name, quantity, unit = nil)
      pantry_item(name).confirm!(
        quantity: quantity,
        unit: unit,
        source: "pantry_check",
        confirmed_by: people(:without_login)
      )
    end

    def requirement(plan, name)
      plan.planned_meal_ingredients.active.find_by!(ingredient: ingredient(name))
    end

    def reservation(allocation, plan, name)
      allocation.reservations_for(plan).find { |reservation| reservation.ingredient == ingredient(name) }
    end

    def reserved(allocation, plan)
      allocation.reservations_for(plan).sole.reserved_quantity
    end

    def deficit(allocation, plan)
      allocation.reservations_for(plan).sole.deficit_quantity
    end

    def farro_reservations(*plans)
      allocated = allocation
      plans.map { |plan| reserved(allocated, plan) }
    end

    def requirement_snapshot
      PlannedMealIngredient.order(:id).pluck(
        :id, :decision, :decided_at, :replacement_ingredient_id, :replacement_decision, :updated_at
      )
    end

    def pantry_snapshot
      PantryItem.order(:id).pluck(
        :id, :state, :quantity_numerator, :quantity_denominator, :unit, :confirmed_at, :updated_at
      )
    end
end
