require "test_helper"

class ActivityHistoryTest < ActiveSupport::TestCase
  test "lists only selected-person outcomes in reverse chronology" do
    travel_to Time.zone.local(2026, 8, 3, 12) do
      history = ActivityHistory.new(household: households(:home), person: people(:one))

      assert_includes history.items.map(&:record), training_sessions(:completed_sunday)
      assert_includes history.items.map(&:record), planned_workouts(:skipped_balanced)
      refute_includes history.items.map(&:record), training_sessions(:other_person)
      refute_includes history.items.map(&:record), planned_workouts(:sam_balanced)
      assert_equal history.items.map(&:occurred_on).sort.reverse, history.items.map(&:occurred_on)
    end
  end

  test "bounds each outcome source to the recent history window" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      old_date = Date.current - ActivityHistory::WINDOW_DAYS.days
      session = training_sessions(:following_monday)
      check_in = habit_check_ins(:alex_lights_out_yesterday)
      plan = planned_workouts(:skipped_balanced)
      session.update!(performed_on: old_date, completed_at: old_date.noon)
      check_in.update!(checked_on: old_date)
      plan.update!(scheduled_on: old_date)

      records = ActivityHistory.new(household: households(:home), person: people(:one)).items.map(&:record)

      refute_includes records, session
      refute_includes records, check_in
      refute_includes records, plan
    end
  end

  test "navigates bounded history windows and falls back from malformed dates" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      older = ActivityHistory.new(
        household: households(:home),
        person: people(:one),
        before: "2026-04-30"
      )
      malformed = ActivityHistory.new(
        household: households(:home),
        person: people(:one),
        before: "not-a-date"
      )

      assert_equal Date.new(2026, 4, 30), older.end_date
      assert_equal older.start_date - 1.day, older.previous_end_date
      refute_predicate older, :recent?
      assert_equal Date.current, malformed.end_date
      assert_predicate malformed, :recent?
    end
  end
end
