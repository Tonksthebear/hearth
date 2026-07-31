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

  test "classified interval dose counts work and excludes recorded recovery" do
    session = completed_interval_session(rounds: 8, work_seconds: 20, rest_seconds: 20)
    week = TrainingWeek.for(household: households(:home), person: people(:one), date: session.performed_on)
    assert_in_delta 160 / 60.0, week.metrics.index_by(&:key)[:vigorous_minutes].actual

    session.destroy!
    session = completed_interval_session(rounds: 8, work_seconds: 60, rest_seconds: 60)
    week = TrainingWeek.for(household: households(:home), person: people(:one), date: session.performed_on)
    assert_equal 8.0, week.metrics.index_by(&:key)[:vigorous_minutes].actual

    session.destroy!
    session = completed_interval_session(rounds: 4, work_seconds: 240, rest_seconds: 180)
    week = TrainingWeek.for(household: households(:home), person: people(:one), date: session.performed_on)
    assert_equal 16.0, week.metrics.index_by(&:key)[:vigorous_minutes].actual
  end

  test "classified distance and count work retains its duration" do
    distance_session = completed_measured_session(
      performance_kind: :distance,
      dose_class: :zone2,
      duration_seconds: 600,
      target: { snapshot_target_distance_amount: 5, snapshot_target_distance_unit: :km },
      actual: { distance_amount: 5, distance_unit: :km }
    )
    count_session = completed_measured_session(
      performance_kind: :count,
      dose_class: :vigorous,
      duration_seconds: 300,
      target: { snapshot_target_count: 40, snapshot_target_count_unit: :flights },
      actual: { count: 40, count_unit: :flights }
    )

    week = TrainingWeek.for(household: households(:home), person: people(:one), date: distance_session.performed_on)
    metrics = week.metrics.index_by(&:key)

    assert_equal 39.5, metrics[:zone2_minutes].actual
    assert_equal 5.0, metrics[:vigorous_minutes].actual
    assert_equal 600, distance_session.training_session_blocks.first.training_session_exercises.first.training_sets.sole.duration_seconds
    assert_equal 300, count_session.training_session_blocks.first.training_session_exercises.first.training_sets.sole.duration_seconds
  end

  private
    def completed_interval_session(rounds:, work_seconds:, rest_seconds:)
      session = people(:one).training_sessions.create!(
        household: households(:home),
        snapshot_title: "Interval dose proof",
        performed_on: Date.new(2026, 7, 29),
        started_at: Time.zone.local(2026, 7, 29, 8),
        completed_at: Time.zone.local(2026, 7, 29, 9)
      )
      block = session.training_session_blocks.create!(
        position: 1,
        snapshot_title: "Intervals",
        snapshot_block_kind: :hiit_interval,
        snapshot_dose_class: :vigorous,
        actual_duration_seconds: rounds * (work_seconds + rest_seconds)
      )
      exercise = block.training_session_exercises.create!(
        position: 1,
        snapshot_name: "Intervals",
        snapshot_modality: :cardio,
        snapshot_movement_pattern: :locomotion_cardio,
        snapshot_performance_kind: :interval,
        snapshot_dose_class: :vigorous,
        snapshot_sets_count: rounds,
        snapshot_work_seconds: work_seconds,
        snapshot_rest_seconds: rest_seconds
      )
      rounds.times do |index|
        exercise.training_sets.create!(
          position: index + 1,
          dose_class: :vigorous,
          duration_seconds: work_seconds,
          rest_seconds: rest_seconds,
          completed: true
        )
      end
      session
    end

    def completed_measured_session(performance_kind:, dose_class:, duration_seconds:, target:, actual:)
      session = people(:one).training_sessions.create!(
        household: households(:home),
        snapshot_title: "Measured dose proof",
        performed_on: Date.new(2026, 7, 29),
        started_at: Time.zone.local(2026, 7, 29, 8),
        completed_at: Time.zone.local(2026, 7, 29, 9)
      )
      block = session.training_session_blocks.create!(
        position: 1,
        snapshot_title: "Measured work",
        snapshot_block_kind: :zone2,
        snapshot_dose_class: dose_class,
        actual_duration_seconds: duration_seconds
      )
      exercise = block.training_session_exercises.create!({
        position: 1,
        snapshot_name: "Measured work",
        snapshot_modality: :cardio,
        snapshot_movement_pattern: :locomotion_cardio,
        snapshot_performance_kind: performance_kind,
        snapshot_dose_class: dose_class,
        snapshot_sets_count: 1,
        snapshot_work_seconds: duration_seconds
      }.merge(target))
      exercise.training_sets.create!({
        position: 1,
        dose_class: dose_class,
        duration_seconds: duration_seconds,
        completed: true
      }.merge(actual))
      session
    end
end
