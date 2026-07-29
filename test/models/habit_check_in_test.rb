require "test_helper"

class HabitCheckInTest < ActiveSupport::TestCase
  test "completion-only check-in needs no measurements" do
    check_in = person_habits(:alex_water).habit_check_ins.build(checked_on: Date.current + 1.day)
    assert check_in.valid?
  end

  test "requires the complete matching typed measurement set" do
    check_in = person_habits(:alex_sauna).habit_check_ins.build(checked_on: Date.current + 1.day)
    check_in.habit_check_in_measurements.build(
      habit_metric: habit_metrics(:sauna_duration),
      number_value: 10
    )

    assert_not check_in.valid?
    assert_includes check_in.errors[:habit_check_in_measurements], "must include each configured habit metric exactly once"
    assert_includes check_in.habit_check_in_measurements.first.errors[:base], "Duration must use its duration value."
  end

  test "rejects duplicate dates per person habit" do
    duplicate = person_habits(:alex_sauna).habit_check_ins.build(checked_on: Date.current)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:checked_on], "has already been taken"
  end
end
