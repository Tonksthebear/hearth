require "test_helper"

class Person::OverviewTest < ActiveSupport::TestCase
  test "prepares meal activity and recovery summaries for one household person" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      overview = Person::Overview.current(household: households(:home), person: people(:one))

      assert_equal people(:one), overview.person
      assert overview.meal_week.planned_meals.loaded?
      assert overview.meal_week.meal_logs.loaded?
      assert overview.training_week.in_progress_sessions.loaded?
      assert overview.training_week.completed_sessions.loaded?
      refute_includes overview.training_week.completed_sessions, training_sessions(:other_person)
    end
  end

  test "rejects a person from another household" do
    outsider = Person.new(id: 0, household: Household.new(id: 0), name: "Outsider")

    assert_raises ActiveRecord::RecordNotFound do
      Person::Overview.current(household: households(:home), person: outsider)
    end
  end
end
