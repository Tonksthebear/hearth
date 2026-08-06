require "test_helper"

class PantryConsumptionTest < ActiveSupport::TestCase
  COOKED_ON = Date.new(2026, 8, 10)

  # Consumption

  test "the first conversion draws each reservation and records what it took" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))

    dinner.convert_for!(people(:one), today: COOKED_ON)

    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Rice")
    consumption = dinner.pantry_consumptions.sole
    assert_equal [ Rational(2), "cup", ingredient("Rice") ], [ consumption.quantity, consumption.unit, consumption.ingredient ]
    assert_equal requirement(dinner, "Rice"), consumption.planned_meal_ingredient
    assert_predicate consumption, :active?
  end

  test "a second person converting a shared plan draws nothing further" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    dinner.convert_for!(people(:one), today: COOKED_ON)

    dinner.convert_for!(people(:two), today: COOKED_ON)

    assert_equal 2, dinner.meals.count
    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Rice")
    assert_equal 1, dinner.pantry_consumptions.active.count
  end

  test "the draw takes the queue share rather than the whole requirement" do
    confirm("Rice", 3, "cup")
    monday = plan(line("Rice", "2", "cup"), planned_on: COOKED_ON)
    friday = plan(line("Rice", "2", "cup"), planned_on: COOKED_ON + 4)

    friday.convert_for!(people(:one), today: COOKED_ON + 4)

    assert_equal Rational(1), friday.pantry_consumptions.sole.quantity
    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Rice")
    assert_equal Rational(2), Household::PantryAllocation.new(households(:home)).reservations_for(monday).sole.reserved_quantity
  end

  test "an exactly emptied row becomes out and still records the draw" do
    confirm("Rice", 2, "cup")
    dinner = plan(line("Rice", "2", "cup"))

    dinner.convert_for!(people(:one), today: COOKED_ON)

    assert_equal [ :out, nil, nil ], pantry_state("Rice")
    assert_equal Rational(2), dinner.pantry_consumptions.sole.quantity
  end

  test "a compatible unit is converted into the pantry row's own unit" do
    confirm("Milk", 1, "L")
    dinner = plan(line("Milk", "250", "ml"))

    dinner.convert_for!(people(:one), today: COOKED_ON)

    consumption = dinner.pantry_consumptions.sole
    assert_equal [ Rational(1, 4), "L" ], [ consumption.quantity, consumption.unit ]
    assert_equal [ :confirmed, Rational(3, 4), "L" ], pantry_state("Milk")
  end

  test "a substituted requirement consumes the replacement and never the original" do
    confirm("Carrots", 4, "cup")
    confirm("Parsnips", 4, "cup")
    dinner = plan(line("Carrots", "2", "cup"))
    requirement(dinner, "Carrots").substitute!(ingredient: ingredient("Parsnips"), display_quantity: "2", unit: "cup")

    dinner.convert_for!(people(:one), today: COOKED_ON)

    assert_equal [ :confirmed, Rational(4), "cup" ], pantry_state("Carrots")
    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Parsnips")
    assert_equal ingredient("Parsnips"), dinner.pantry_consumptions.sole.ingredient
  end

  test "requirements with nothing to draw are a no-op rather than an error" do
    confirm("Rice", 4, "cup")
    confirm("Salt", 1, "package")
    dinner = plan(
      line("Rice", "2", "cup"), line("Salt", "to taste", nil), line("Kale", "1", "head"), line("Broth", "1", "cup")
    )
    confirm("Kale", 1, "head").mark_low!(source: "pantry_check", confirmed_by: people(:without_login))
    requirement(dinner, "Salt").decide!(:not_needed)

    dinner.convert_for!(people(:one), today: COOKED_ON)

    assert_equal [ ingredient("Rice") ], dinner.pantry_consumptions.map(&:ingredient)
    assert_equal [ :confirmed, Rational(1), "package" ], pantry_state("Salt")
    assert_equal :low, pantry_state("Kale").first
  end

  test "logging stays available in every readiness state" do
    confirm("Rice", 1, "cup")
    unresolved = plan(line("Broth", "1", "cup"))
    deficit = plan(line("Rice", "4", "cup"))
    ready = plan(line("Beans", "1", "can"))
    confirm("Beans", 1, "can")
    requirement(deficit, "Rice").decide!(:missing)
    states = [ unresolved, deficit, ready ].map { |queued| Household::PantryAllocation.new(households(:home)).readiness_for(queued).state }

    meals = [ unresolved, deficit, ready ].map { |queued| queued.convert_for!(people(:one), today: COOKED_ON) }

    assert_equal %i[ needs_ingredient_check shopping_needed ready_to_cook ], states
    assert_equal 3, meals.compact.count(&:persisted?)
    assert_equal [ :out, :out ], [ pantry_state("Rice").first, pantry_state("Beans").first ]
  end

  test "a reservation larger than the row draws only what is there and still logs the meal" do
    confirm("Rice", 1, "cup")
    dinner = plan(line("Rice", "1", "cup"))

    with_inflated_reservations { dinner.convert_for!(people(:one), today: COOKED_ON) }

    assert_equal [ :out, nil, nil ], pantry_state("Rice")
    assert_equal Rational(1), dinner.pantry_consumptions.sole.quantity
    assert_predicate dinner.meals.sole, :persisted?
  end

  test "a rejected adjustment is retried once and abandoned on a second rejection" do
    confirm("Rice", 4, "cup")
    confirm("Beans", 2, "can")
    retried = plan(line("Rice", "2", "cup"))
    abandoned = plan(line("Rice", "1", "cup"), line("Beans", "1", "can"))

    with_failing_adjustments(1) { retried.convert_for!(people(:one), today: COOKED_ON) }
    with_failing_adjustments(2) { abandoned.convert_for!(people(:one), today: COOKED_ON) }

    assert_equal Rational(2), retried.pantry_consumptions.sole.quantity
    assert_equal [ :confirmed, Rational(1), "can" ], pantry_state("Beans")
    assert_equal [ ingredient("Beans") ], abandoned.pantry_consumptions.map(&:ingredient)
    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Rice")
    assert_predicate abandoned.meals.sole, :persisted?
  end

  test "consumption leaves meal nutrition and requirement history untouched" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    requirement(dinner, "Rice").decide!(:on_hand)
    before = requirement_snapshot

    meal = dinner.convert_for!(people(:one), today: COOKED_ON)

    assert_equal before, requirement_snapshot
    assert_equal [ dinner.recipe.title ], meal.meal_items.map(&:snapshot_label)
  end

  # Release

  test "deleting the last meal credits the recorded amount back exactly" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    meal = dinner.convert_for!(people(:one), today: COOKED_ON)

    meal.destroy!

    assert_equal [ :confirmed, Rational(4), "cup" ], pantry_state("Rice")
    consumption = dinner.pantry_consumptions.sole
    assert_equal "credited", consumption.released_reason
    assert_not_nil consumption.released_at
    assert_empty dinner.pantry_consumptions.active
  end

  test "deleting one meal of a shared plan credits nothing while another remains" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    first = dinner.convert_for!(people(:one), today: COOKED_ON)
    dinner.convert_for!(people(:two), today: COOKED_ON)

    first.destroy!

    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Rice")
    assert_equal 1, dinner.pantry_consumptions.active.count
  end

  test "a released ledger credits nothing further on replay" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    dinner.convert_for!(people(:one), today: COOKED_ON).destroy!

    dinner.release_pantry_consumptions!(person: people(:one))
    dinner.release_pantry_consumptions!(person: people(:one))

    assert_equal [ :confirmed, Rational(4), "cup" ], pantry_state("Rice")
    assert_equal 1, dinner.pantry_consumptions.count
  end

  test "a newer pantry assertion is preserved and the forfeited credit keeps its reason" do
    forfeits = {
      "evidence_weakened" => ->(item) { item.mark_low!(**observation) },
      "evidence_depleted" => ->(item) { item.mark_out!(**observation) },
      "evidence_cleared" => ->(item) { item.clear!(**observation) },
      "evidence_absent" => ->(item) { item.destroy! },
      "unit_incompatible" => ->(item) { item.confirm!(quantity: 3, unit: "can", **observation) }
    }

    reasons = forfeits.map do |reason, assertion|
      name = "Rice #{reason}"
      confirm(name, 4, "cup")
      dinner = plan(line(name, "2", "cup"))
      meal = dinner.convert_for!(people(:one), today: COOKED_ON)
      assertion.call(pantry_item(name))
      state = pantry_state(name)

      meal.destroy!

      assert_equal state, pantry_state(name), "#{reason} overwrote a newer pantry assertion"
      dinner.pantry_consumptions.sole.released_reason
    end

    assert_equal forfeits.keys, reasons
  end

  test "a compatible re-confirmation in another unit still credits exactly" do
    confirm("Milk", 1, "L")
    dinner = plan(line("Milk", "250", "ml"))
    meal = dinner.convert_for!(people(:one), today: COOKED_ON)
    pantry_item("Milk").confirm!(quantity: 500, unit: "ml", **observation)

    meal.destroy!

    assert_equal [ :confirmed, Rational(750), "mL" ], pantry_state("Milk")
    assert_equal "credited", dinner.pantry_consumptions.sole.released_reason
  end

  test "cooking again after an undo records a fresh draw behind released history" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    dinner.convert_for!(people(:one), today: COOKED_ON).destroy!

    dinner.convert_for!(people(:one), today: COOKED_ON)

    assert_equal [ :confirmed, Rational(2), "cup" ], pantry_state("Rice")
    assert_equal 2, dinner.pantry_consumptions.count
    assert_equal [ "credited" ], dinner.pantry_consumptions.released.map(&:released_reason)
    assert_equal Rational(2), dinner.pantry_consumptions.active.sole.quantity
  end

  test "deleting an unconverted plan releases its reservation without any ledger" do
    confirm("Rice", 4, "cup")
    monday = plan(line("Rice", "4", "cup"), planned_on: COOKED_ON)
    friday = plan(line("Rice", "4", "cup"), planned_on: COOKED_ON + 4)
    assert_equal Rational(0), reserved_for(friday)

    monday.destroy!

    assert_equal Rational(4), reserved_for(friday)
    assert_equal [ :confirmed, Rational(4), "cup" ], pantry_state("Rice")
    assert_empty PantryConsumption.all
  end

  test "rescheduling reorders the queue without any ledger" do
    confirm("Rice", 4, "cup")
    monday = plan(line("Rice", "4", "cup"), planned_on: COOKED_ON)
    friday = plan(line("Rice", "4", "cup"), planned_on: COOKED_ON + 4)

    monday.update!(planned_on: COOKED_ON + 8)

    assert_equal Rational(4), reserved_for(friday)
    assert_equal Rational(0), reserved_for(monday)
    assert_empty PantryConsumption.all
  end

  test "a requirement that drew stock is superseded rather than destroyed" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    dinner.convert_for!(people(:one), today: COOKED_ON)
    drawn = requirement(dinner, "Rice")

    dinner.recipe.recipe_ingredients.sole.update!(display_quantity: "3", quantity_numerator: 3)
    dinner.reconcile_ingredient_snapshots!

    assert_predicate drawn.reload, :persisted?
    assert_equal "requirement_changed", drawn.superseded_reason
    assert_equal drawn, dinner.pantry_consumptions.sole.planned_meal_ingredient
  end

  test "deleting the plan destroys its consumption history ahead of its requirements" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    meal = dinner.convert_for!(people(:one), today: COOKED_ON)
    meal.destroy!

    dinner.destroy!

    assert_empty PantryConsumption.all
    assert_empty PlannedMealIngredient.where(planned_meal_id: dinner.id)
  end

  # Ledger invariants

  test "a requirement from another plan is rejected even when assigned by id" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    other = plan(line("Rice", "2", "cup"), planned_on: COOKED_ON + 1)
    consumption = build_consumption(dinner)

    consumption.planned_meal_ingredient_id = requirement(other, "Rice").id

    assert_predicate consumption, :invalid?
    assert_equal [ "must belong to this planned meal" ], consumption.errors[:planned_meal_ingredient]
  end

  test "a fixture requirement from another plan is rejected even when assigned by id" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    consumption = build_consumption(dinner)

    consumption.planned_meal_ingredient_id = planned_meal_ingredients(:shared_salad_lettuce).id

    assert_predicate consumption, :invalid?
    assert_equal [ "must belong to this planned meal" ], consumption.errors[:planned_meal_ingredient]
  end

  test "an ingredient from another household is rejected" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    consumption = build_consumption(dinner)

    consumption.ingredient = Household.new(name: "Other home").ingredients.build(name: "Outside", normalized_name: "outside")

    assert_predicate consumption, :invalid?
    assert_equal [ "must belong to this household" ], consumption.errors[:ingredient]
  end

  test "the same plan and requirement stay valid" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))

    assert_predicate build_consumption(dinner), :valid?
  end

  test "a release timestamp and a bounded reason travel together" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))

    assert_predicate build_consumption(dinner, released_at: Time.current), :invalid?
    assert_predicate build_consumption(dinner, released_reason: "credited"), :invalid?
    assert_predicate build_consumption(dinner, released_at: Time.current, released_reason: "vanished"), :invalid?
    assert_predicate build_consumption(dinner, released_at: Time.current, released_reason: "credited"), :valid?
  end

  test "the database rejects an unbounded release reason" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    consumption = build_consumption(dinner)
    consumption.save!

    assert_raises ActiveRecord::StatementInvalid do
      consumption.update_columns(released_at: Time.current, released_reason: "vanished")
    end
  end

  test "a released row is immutable" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    consumption = build_consumption(dinner)
    consumption.save!
    consumption.release!(person: people(:one))

    consumption.quantity_numerator = 9

    assert_predicate consumption, :invalid?
    assert_equal [ "A released pantry consumption cannot be changed" ], consumption.errors[:base]
  end

  test "one requirement holds at most one active draw" do
    confirm("Rice", 4, "cup")
    dinner = plan(line("Rice", "2", "cup"))
    build_consumption(dinner).save!

    assert_raises ActiveRecord::RecordNotUnique do
      build_consumption(dinner).save!(validate: false)
    end
  end

  private
    def observation
      { source: "pantry_check", confirmed_by: people(:without_login) }
    end

    def line(display_name, display_quantity, unit)
      { display_name: display_name, display_quantity: display_quantity, unit: unit }
    end

    def plan(*lines, planned_on: COOKED_ON, recipe_scale: 1)
      recipe = households(:home).recipes.create!(
        title: "Lifecycle #{planned_on} #{lines.map { |attributes| attributes.fetch(:display_name) }.join(" ")}",
        source_name: "Lifecycle fixture",
        provenance_status: :observed
      )
      lines.each_with_index { |attributes, index| recipe.recipe_ingredients.create!(**attributes, position: index + 1) }

      PlannedMeal.create!(household: households(:home), recipe: recipe, planned_on: planned_on, recipe_scale: recipe_scale)
    end

    def ingredient(name)
      Ingredient.resolve!(household: households(:home), name: name)
    end

    def pantry_item(name)
      PantryItem.for(household: households(:home), ingredient: ingredient(name))
    end

    def confirm(name, quantity, unit = nil)
      pantry_item(name).confirm!(quantity: quantity, unit: unit, **observation)
    end

    def pantry_state(name)
      item = households(:home).pantry_items.find_by(ingredient: ingredient(name))
      return [ nil, nil, nil ] unless item

      [ item.state.to_sym, item.quantity, item.unit ]
    end

    def requirement(plan, name)
      plan.planned_meal_ingredients.active.find_by!(ingredient: ingredient(name))
    end

    def reserved_for(plan)
      Household::PantryAllocation.new(households(:home)).reservations_for(plan).sole.reserved_quantity
    end

    def requirement_snapshot
      PlannedMealIngredient.order(:id).pluck(:id, :decision, :decided_at, :superseded_at, :updated_at)
    end

    def build_consumption(plan, **attributes)
      plan.pantry_consumptions.build(
        planned_meal_ingredient: plan.planned_meal_ingredients.active.first,
        ingredient: plan.planned_meal_ingredients.active.first.ingredient,
        quantity_numerator: 1,
        quantity_denominator: 1,
        unit: "cup",
        **attributes
      )
    end

    # Violates the draw's own precondition — the projection claiming more than the
    # row holds — because that is the only way to reach the clamp deliberately.
    def with_inflated_reservations
      original = Household::PantryAllocation.instance_method(:reservations_for)
      Household::PantryAllocation.define_method(:reservations_for) do |planned_meal|
        original.bind(self).call(planned_meal).map do |reservation|
          reservation.with(reserved_quantity: reservation.reserved_quantity * 10)
        end
      end
      yield
    ensure
      Household::PantryAllocation.define_method(:reservations_for, original)
    end

    def with_failing_adjustments(failures)
      remaining = failures
      original = PantryItem.instance_method(:adjust!)
      PantryItem.define_method(:adjust!) do |**keywords|
        next original.bind(self).call(**keywords) unless remaining.positive?

        remaining -= 1
        errors.add(:base, "Simulated contention on the pantry row.")
        raise ActiveRecord::RecordInvalid, self
      end
      yield
    ensure
      PantryItem.define_method(:adjust!, original)
    end
end
