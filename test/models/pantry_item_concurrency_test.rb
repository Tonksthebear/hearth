require "test_helper"

# Contention on the never-decrease confirmation, run on independent pooled
# connections and inspected after both contenders have committed.
#
# Rails 8.1's SQLite adapter opens transactions with BEGIN IMMEDIATE, so two
# writers serialize at transaction start. That makes with_lock redundant only for
# an invariant resting on a predicate re-read inside the transaction. It is NOT
# redundant here: ensure_at_least! is entered on an instance loaded before the
# race, and with_lock's reload is what refreshes it, so the target is recomputed
# from the winner's committed amount rather than a stale copy. The measured
# ablations agree — replacing with_lock with a plain transaction goes red, as do
# removing the never-decrease rule, hoisting the target computation above the
# reload, and dropping winner re-entry.
class PantryItemConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  COOKED_ON = Date.new(2026, 8, 10)

  setup do
    @household = households(:home)
    @ingredient = Ingredient.resolve!(household: @household, name: "Contended flour")
  end

  # Nothing rolls back here, so this test owns its rows and removes them in
  # reverse dependency order.
  teardown do
    Meal.where(planned_meal_id: @plan&.id).destroy_all if @plan
    PlannedMeal.where(id: @plan&.id).destroy_all if @plan
    Recipe.where(id: @recipe&.id).destroy_all if @recipe
    PantryItem.where(ingredient_id: @ingredient.id).destroy_all
    Ingredient.where(id: @ingredient.id).destroy_all
  end

  test "concurrent first-time confirmations settle on the larger amount" do
    race { |person, quantity| pantry_row.ensure_at_least!(**confirmation(quantity, person)) }

    committed do
      assert_equal 1, PantryItem.where(ingredient_id: @ingredient.id).count
      assert_equal [ "confirmed", Rational(6), "cup" ], pantry
    end
  end

  test "concurrent confirmations of an existing row never lower it" do
    pantry_row.confirm!(quantity: 1, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))

    race { |person, quantity| pantry_row.ensure_at_least!(**confirmation(quantity, person)) }

    committed { assert_equal [ "confirmed", Rational(6), "cup" ], pantry }
  end

  # Cooking draws the same row an "on hand" confirmation may be raising. The
  # fixture is chosen so BOTH serial orders converge on one committed outcome, so
  # the oracle is exact rather than a permissive set of allowed states:
  #
  #   confirm then cook: max(4, 2) = 4, cook draws 2 -> 2 cup
  #   cook then confirm: cook draws 2 -> 2, max(2, 2) = 2 -> 2 cup
  #
  # Each plausible defect lands outside it. Delta arithmetic gives 4; lowering an
  # already-sufficient row gives 0 and state out; a double draw gives out with two
  # ledger rows; a stale clobber gives the wrong quantity.
  test "cooking and confirming the same row converge on one committed state" do
    prepare_plan
    pantry_row.confirm!(quantity: 4, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))

    race(
      ->(person, _) { PlannedMeal.find(@plan.id).convert_for!(person, today: COOKED_ON) },
      ->(person, _) { pantry_row.ensure_at_least!(**confirmation(2, person)) }
    )

    committed do
      assert_equal [ "confirmed", Rational(2), "cup" ], pantry
      assert_equal [ [ Rational(2), "cup" ] ], ledger.map { |row| [ row.quantity, row.unit ] }
      assert_equal [ true ], ledger.map(&:active?)
    end
  end

  # The review answer and the cooking event contend for the same plan, not just
  # the same pantry row. Whichever loses must leave nothing behind: a decision
  # written after the draw would rewrite history, and its evidence would confirm
  # stock this plan has already taken off the shelf.
  # The review answer and the cooking event contend for the same plan, not just
  # the same pantry row. Fixture chosen so both orders converge on ONE committed
  # state — pantry 4 cup, requirement 3 cup:
  #
  #   answer then cook: max(4, 3) = 4, cook draws 3 -> 1 cup
  #   cook then answer: cook draws 3 -> 1 cup, the answer is refused -> 1 cup
  #
  # A late answer that slipped past the guard would top the row back up to
  # max(1, 3) = 3 cup, confirming stock the plan had already taken off the shelf.
  #
  # SCOPE OF THIS ORACLE, measured rather than assumed: instrumenting the race
  # eight times landed the answer first 8/8, so this test exercises the
  # answer-then-cook order and proves the committed state stays coherent under
  # contention — one draw, one ledger row, one meal. It does NOT reach the
  # refusal path and stays green when the lifecycle guard is ablated. The
  # load-bearing oracles for the guard are the deterministic model tests in
  # PlannedMealIngredientOnHandTest ("a requirement cooked between the
  # eligibility check and the write is refused" and "every review command is
  # refused once the plan has been cooked"), both of which go red without it.
  test "answering a requirement races cooking and the committed state stays coherent" do
    prepare_plan(required: "3")
    pantry_row.confirm!(quantity: 4, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))
    requirement = @plan.planned_meal_ingredients.active.sole

    race(
      ->(person, _) { PlannedMeal.find(@plan.id).convert_for!(person, today: COOKED_ON) },
      ->(person, _) do
        PlannedMealIngredient.find(requirement.id).answer!(:on_hand, by: person)
      rescue ActiveRecord::RecordNotFound
        nil # Cooking won, so the answer is refused rather than applied late.
      end
    )

    committed do
      assert_equal [ "confirmed", Rational(1), "cup" ], pantry
      assert_equal [ Rational(3) ], ledger.map(&:quantity)
      assert_equal 1, Meal.where(planned_meal_id: @plan.id).count
      # The decision is on_hand only when the answer actually won; a refused
      # answer leaves the requirement untouched, decided_at included.
      answered = PlannedMealIngredient.find(requirement.id)
      assert_includes %w[ unknown on_hand ], answered.decision
      assert_nil answered.decided_at if answered.unknown?
      assert_not_nil answered.decided_at if answered.on_hand?
    end
  end

  test "confirming before cooking leaves the same committed state as cooking first" do
    prepare_plan
    pantry_row.confirm!(quantity: 4, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))

    pantry_row.ensure_at_least!(**confirmation(2, people(:one)))
    assert_equal [ "confirmed", Rational(4), "cup" ], pantry
    PlannedMeal.find(@plan.id).convert_for!(people(:one), today: COOKED_ON)

    assert_equal [ "confirmed", Rational(2), "cup" ], pantry
    assert_equal [ Rational(2) ], ledger.map(&:quantity)
  end

  test "cooking before confirming leaves the same committed state as confirming first" do
    prepare_plan
    pantry_row.confirm!(quantity: 4, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))

    PlannedMeal.find(@plan.id).convert_for!(people(:one), today: COOKED_ON)
    assert_equal [ "confirmed", Rational(2), "cup" ], pantry
    pantry_row.ensure_at_least!(**confirmation(2, people(:one)))

    assert_equal [ "confirmed", Rational(2), "cup" ], pantry
    assert_equal [ Rational(2) ], ledger.map(&:quantity)
  end

  private
    def prepare_plan(required: "2")
      @recipe = @household.recipes.create!(
        title: "Contended flour plan", source_name: "Concurrency fixture", provenance_status: :observed
      )
      @recipe.recipe_ingredients.create!(display_name: "Contended flour", display_quantity: required, unit: "cup", position: 1)
      @plan = PlannedMeal.create!(household: @household, recipe: @recipe, planned_on: COOKED_ON)
    end

    def pantry_row
      PantryItem.for(household: @household, ingredient: @ingredient)
    end

    def confirmation(quantity, person)
      {
        quantity: quantity,
        unit: "cup",
        source: PantryItem::READINESS_REVIEW_SOURCE,
        confirmed_by: person,
        confirmed_at: Time.current
      }
    end

    # Both contenders enter together on their own connection, so the assertions
    # inspect committed state rather than one lucky thread. The larger amount goes
    # second so an ordering-blind implementation cannot pass by accident.
    def race(*contenders, &block)
      contenders = [ block, block ] if contenders.empty?
      barrier = Concurrent::CyclicBarrier.new(2)
      failures = Queue.new

      [ [ people(:one), 2 ], [ people(:two), 6 ] ].each_with_index.map do |(person, quantity), index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            contenders[index].call(person, quantity)
          end
        rescue StandardError => error
          failures << error
        end
      end.each(&:join)

      assert_empty Array.new(failures.size) { failures.pop }.map { |error| "#{error.class}: #{error.message}" }
    end

    # This connection's query cache is never invalidated by the contenders'
    # commits, which happen on their own connections, so a repeated read would
    # otherwise answer from before the race.
    def committed(&block)
      ActiveRecord::Base.uncached(&block)
    end

    def pantry
      row = PantryItem.find_by!(household_id: @household.id, ingredient_id: @ingredient.id)
      [ row.state, row.quantity, row.unit ]
    end

    def ledger
      PantryConsumption.where(planned_meal_id: @plan.id).order(:id).to_a
    end
end
