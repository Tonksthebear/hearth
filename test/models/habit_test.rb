require "test_helper"

class HabitTest < ActiveSupport::TestCase
  test "mutates ordered metric rows with safe coordinates and one-based positions" do
    habit = households(:home).habits.build(name: "Composer")
    habit.add_metric
    habit.add_metric
    habit.move_metric("1:up")
    habit.remove_metric(1)

    assert_equal [ 1 ], habit.habit_metrics.map(&:position)
    assert_raises(ArgumentError) { habit.move_metric("0:up") }
    assert_raises(ArgumentError) { habit.remove_metric(9) }
  end

  test "persists metric reorder and middle removal through the unique position index" do
    habit = households(:home).habits.create!(name: "Cold plunge")
    first = habit.habit_metrics.create!(key: "temperature", label: "Temperature", value_type: "number", unit: "°F", position: 1)
    second = habit.habit_metrics.create!(key: "duration", label: "Duration", value_type: "duration", unit: "minutes", position: 2)
    third = habit.habit_metrics.create!(key: "rounds", label: "Rounds", value_type: "number", unit: "rounds", position: 3)

    habit.move_metric("1:up")
    assert habit.save
    assert_equal [ second.id, first.id, third.id ], habit.reload.habit_metrics.pluck(:id)

    habit.remove_metric(1)
    assert habit.save
    assert_equal [ second.id, third.id ], habit.reload.habit_metrics.pluck(:id)
    assert_equal [ 1, 2 ], habit.habit_metrics.pluck(:position)
  end

  test "validates typed metric unit rules and immutable history schema" do
    habit = habits(:sauna)
    number = habit.habit_metrics.build(key: "effort", label: "Effort", value_type: "number", position: 3)
    assert_not number.valid?
    assert_includes number.errors[:unit], "can't be blank"

    clock = habits(:lights_out).habit_metrics.first
    clock.unit = "hours"
    assert_not clock.valid?
    assert_includes clock.errors[:unit], "must be blank"

    metric = habit_metrics(:sauna_duration)
    metric.key = "minutes"
    assert_not metric.valid?
    assert_includes metric.errors[:key], "cannot change after measurements have been recorded"
  end

  test "does not remove a metric that has measurement history" do
    habit = habits(:sauna)
    habit.remove_metric(0)

    assert_not habit.save
    assert_includes habit.errors[:habit_metrics], "Duration cannot be removed after measurements have been recorded"
    assert HabitMetric.exists?(habit_metrics(:sauna_duration).id)
  end
end
