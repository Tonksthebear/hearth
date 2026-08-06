require "test_helper"

# Contention on the real cooking and undo paths, run on independent pooled
# connections and inspected after both contenders have committed. Rails 8.1's
# SQLite adapter opens transactions with BEGIN IMMEDIATE, so writers take the
# write lock at BEGIN and wait on the busy handler rather than deadlocking.
class PlannedMeal::PantryLifecycleConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  COOKED_ON = Date.new(2026, 8, 10)

  setup do
    @household = households(:home)
    @ingredient = Ingredient.resolve!(household: @household, name: "Contended rice")
    @pantry = PantryItem.for(household: @household, ingredient: @ingredient).confirm!(
      quantity: 4, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login)
    )
    @recipe = @household.recipes.create!(
      title: "Contended plan", source_name: "Concurrency fixture", provenance_status: :observed
    )
    @recipe.recipe_ingredients.create!(display_name: "Contended rice", display_quantity: "2", unit: "cup", position: 1)
    @plan = PlannedMeal.create!(household: @household, recipe: @recipe, planned_on: COOKED_ON)
  end

  # Nothing rolls back here, so this test owns its rows and removes them in
  # reverse dependency order. Rails teardown rather than raw deletes, because the
  # consumption ledger restricts its requirement and the plan's declaration order
  # is what makes that teardown legal.
  teardown do
    Meal.where(planned_meal_id: @plan.id).destroy_all
    PlannedMeal.where(id: @plan.id).destroy_all
    Recipe.where(id: @recipe.id).destroy_all
    PantryItem.where(ingredient_id: @ingredient.id).destroy_all
    Ingredient.where(id: @ingredient.id).destroy_all
  end

  test "two people converting the same shared plan draw the stock exactly once" do
    race { |person| PlannedMeal.find(@plan.id).convert_for!(person, today: COOKED_ON) }

    committed do
      assert_equal 2, Meal.where(planned_meal_id: @plan.id).count
      assert_equal [ Rational(2) ], ledger.map(&:quantity)
      assert_equal [ true ], ledger.map(&:active?)
      assert_equal [ "confirmed", Rational(2) ], pantry
    end
  end

  test "deleting both meals of a shared plan credits the stock back exactly once" do
    [ people(:one), people(:two) ].each { |person| PlannedMeal.find(@plan.id).convert_for!(person, today: COOKED_ON) }
    assert_equal [ "confirmed", Rational(2) ], committed { pantry }

    race { |person| Meal.find_by!(planned_meal_id: @plan.id, person_id: person.id).destroy! }

    committed do
      assert_equal 0, Meal.where(planned_meal_id: @plan.id).count
      assert_equal [ "credited" ], ledger.map(&:released_reason)
      assert_empty ledger.select(&:active?)
      assert_equal [ "confirmed", Rational(4) ], pantry
    end
  end

  private
    # Both contenders enter the shared path together on their own connection, so
    # the assertions inspect committed state rather than one lucky thread.
    def race(&contender)
      barrier = Concurrent::CyclicBarrier.new(2)
      failures = Queue.new

      [ people(:one), people(:two) ].map do |person|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            contender.call(person)
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

    def ledger
      PantryConsumption.where(planned_meal_id: @plan.id).order(:id).to_a
    end

    def pantry
      row = PantryItem.find(@pantry.id)
      [ row.state, row.quantity ]
    end
end
