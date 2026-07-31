require "test_helper"

class ActivityDayTest < ActiveSupport::TestCase
  test "composes planned, in-progress, completed, skipped, and habit items once" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.delete_all
      day = ActivityDay.new(
        household: households(:home),
        person: people(:one),
        date: Date.new(2026, 7, 30)
      )

      assert_includes day.up_next.map(&:record), planned_workouts(:planned_balanced)
      assert_includes day.up_next.map(&:record), person_habits(:alex_water)
      assert_includes day.in_progress.map(&:record), planned_workouts(:linked_in_progress)
      assert_equal 1, day.in_progress.count { |item| item.title == training_sessions(:in_progress).snapshot_title }
      refute_includes day.up_next.map(&:record), planned_workouts(:sam_balanced)
      assert_predicate day.sections, :frozen?
      assert day.sections.all? { |section| section.items.frozen? }
    end
  end

  test "checked habits move from up next to done" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.delete_all
      check_in = person_habits(:alex_water).habit_check_ins.create!(checked_on: Date.current)
      day = ActivityDay.new(household: households(:home), person: people(:one), date: Date.current)

      refute_includes day.up_next.map(&:title), "Water"
      assert_includes day.done.map(&:record), check_in
    end
  end

  test "linked plan renders on performed date rather than intended date" do
    plan = planned_workouts(:linked_in_progress)

    intended = ActivityDay.new(household: households(:home), person: people(:one), date: plan.scheduled_on)
    performed = ActivityDay.new(household: households(:home), person: people(:one), date: plan.training_session.performed_on)

    refute_includes intended.in_progress.map(&:record), plan
    assert_includes performed.in_progress.map(&:record), plan
  end
end
