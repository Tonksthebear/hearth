require "test_helper"

class MealWeekTest < ActiveSupport::TestCase
  test "uses Monday boundaries and falls back to the current week for invalid dates" do
    travel_to Date.new(2026, 7, 27) do
      current = MealWeek.for(household: households(:home), person: people(:one), date: nil)
      malformed = MealWeek.for(household: households(:home), person: people(:one), date: "not-a-date")
      invalid_calendar = MealWeek.for(household: households(:home), person: people(:one), date: "2026-02-31")

      assert_equal Date.new(2026, 7, 27), current.start_date
      assert_equal Date.new(2026, 8, 2), current.end_date
      assert_equal current.start_date, malformed.start_date
      assert_equal current.start_date, invalid_calendar.start_date
    end
  end

  test "prepares both form models for a complete week render" do
    week = MealWeek.for(
      household: households(:home),
      person: people(:one),
      date: "2026-07-27"
    )

    assert_equal Date.new(2026, 7, 27), week.planned_meal.planned_on
    assert_equal Date.new(2026, 7, 27), week.meal_log.eaten_on
    assert_equal households(:home).recipes.order(:title).to_a, week.recipes.to_a
    assert_equal households(:home).people.order(:name).to_a, week.people.to_a
  end
end
