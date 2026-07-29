require "test_helper"

class PersonHabitTest < ActiveSupport::TestCase
  test "defaults to all days, assigns append position, and matches targets to definitions" do
    configuration = people(:one).person_habits.build(habit: habits(:movement))
    configuration.ensure_target_rows

    assert PersonHabit::WEEKDAYS.all? { |weekday| configuration.public_send(weekday) }
    assert configuration.scheduled_on?(Date.current)
    assert configuration.valid?
    assert_equal 4, configuration.position

    configuration.person_habit_metrics.first.habit_metric = habit_metrics(:sauna_duration)
    assert_not configuration.valid?
    assert_includes configuration.person_habit_metrics.first.errors[:habit_metric], "must belong to the configured habit"
  end

  test "requires one configuration per person and the same household" do
    duplicate = people(:one).person_habits.build(habit: habits(:sauna))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:habit_id], "has already been taken"
  end

  test "typed targets must use the definition value column" do
    target = person_habit_metrics(:alex_sauna_duration_target)
    target.number_value = 20
    target.duration_value = nil

    assert_not target.valid?
    assert_includes target.errors[:base], "Duration must use its duration value."
  end
end
