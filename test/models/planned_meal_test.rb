require "test_helper"

class PlannedMealTest < ActiveSupport::TestCase
  test "scopes plans by week and selected-person visibility" do
    week = MealWeek.for(
      household: households(:home),
      person: people(:one),
      date: "2026-07-27"
    )

    assert_includes week.planned_meals, planned_meals(:shared_target_week)
    assert_includes week.planned_meals, planned_meals(:alex_target_week)
    refute_includes week.planned_meals, planned_meals(:sam_target_week)
    refute_includes week.planned_meals, planned_meals(:adjacent_week)
  end

  test "requires person and recipe associations to match the household" do
    other_household = Household.new(name: "Other")
    other_person = other_household.people.build(name: "Other person")
    other_recipe = other_household.recipes.build(
      title: "Other recipe",
      source_name: "Test",
      provenance_status: :observed
    )

    planned_meal = PlannedMeal.new(
      household: households(:home),
      person: other_person,
      recipe: other_recipe,
      planned_on: Date.new(2026, 7, 27)
    )

    assert_not planned_meal.valid?
    assert_includes planned_meal.errors[:person], "must belong to this household"
    assert_includes planned_meal.errors[:recipe], "must belong to this household"
  end

  test "destroys assigned plans with a person but preserves shared plans" do
    person = people(:one)
    assigned_id = planned_meals(:alex_target_week).id
    shared_id = planned_meals(:shared_target_week).id

    person.destroy!

    assert_not PlannedMeal.exists?(assigned_id)
    assert PlannedMeal.exists?(shared_id)
  end


  test "shared plan converts independently once per person on the planned date" do
    plan = planned_meals(:shared_target_week)

    alex_meal = plan.convert_for!(people(:one), today: Date.new(2026, 7, 31))
    sam_meal = plan.convert_for!(people(:two), today: Date.new(2026, 7, 31))

    assert_equal plan.planned_on, alex_meal.eaten_on
    assert_equal plan.planned_on, sam_meal.eaten_on
    assert_equal [ people(:one).id, people(:two).id ].sort, plan.meals.reload.map(&:person_id).sort
    assert_equal alex_meal.id, plan.convert_for!(people(:one), today: Date.new(2026, 7, 31)).id

    alex_meal.update!(notes: "Alex changed this meal")
    assert_nil sam_meal.reload.notes
    alex_meal.destroy!
    assert Meal.exists?(sam_meal.id)
  end

  test "future and invisible plans cannot convert" do
    assert_raises(ActiveRecord::RecordInvalid) do
      planned_meals(:adjacent_week).convert_for!(people(:one), today: Date.new(2026, 7, 31))
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      planned_meals(:sam_target_week).convert_for!(people(:one), today: Date.new(2026, 7, 31))
    end
  end

  test "referenced plan cannot be destroyed" do
    plan = planned_meals(:shared_target_week)
    plan.convert_for!(people(:one), today: Date.new(2026, 7, 31))

    assert_raises(ActiveRecord::DeleteRestrictionError) { plan.destroy! }
  end
end
