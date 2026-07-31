require "test_helper"

class TrainingWeekTest < ActiveSupport::TestCase
  test "uses inclusive Monday through Sunday boundaries and excludes other people" do
    week = TrainingWeek.for(
      household: households(:home),
      person: people(:one),
      date: "2026-07-29"
    )

    assert_equal Date.new(2026, 7, 27), week.start_date
    assert_equal Date.new(2026, 8, 2), week.end_date
    assert_includes week.completed_sessions, training_sessions(:completed_sunday)
    refute_includes week.completed_sessions, training_sessions(:following_monday)
    refute_includes week.completed_sessions, training_sessions(:other_person)
    assert_includes week.in_progress_sessions, training_sessions(:in_progress)
  end

  test "derives all four metrics from completed structured rows" do
    person = people(:one)
    person.update!(
      weekly_structured_minutes_target: 45,
      weekly_strength_sessions_target: 1,
      weekly_zone2_minutes_target: 30,
      weekly_vigorous_minutes_target: 10
    )
    metrics = TrainingWeek.for(
      household: households(:home),
      person: person,
      date: "2026-07-29"
    ).metrics.index_by(&:key)

    assert_equal 50.0, metrics[:structured_minutes].actual
    assert_equal 1, metrics[:strength_sessions].actual
    assert_equal 29.5, metrics[:zone2_minutes].actual
    assert_equal 0.0, metrics[:vigorous_minutes].actual
    assert_predicate metrics[:structured_minutes], :reached?
    assert_equal 0, metrics[:structured_minutes].remaining
    assert_equal 0.5, metrics[:zone2_minutes].remaining
    assert_equal 111, metrics[:structured_minutes].percent
  end

  test "leaves progress semantics unset when targets are nil" do
    metric = TrainingWeek.for(
      household: households(:home),
      person: people(:one),
      date: "2026-07-29"
    ).metrics.first

    refute_predicate metric, :configured?
    assert_nil metric.remaining
    assert_nil metric.percent
    refute_predicate metric, :reached?
  end
end
