require "test_helper"

class RecoveryDayTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "bounds seven dates and excludes other-person and older records" do
    day = RecoveryDay.current(household: households(:home), person: people(:one))

    assert_equal 7, day.dates.size
    assert_equal Date.current, day.dates.first
    assert_equal Date.current - 6.days, day.dates.last
    assert day.entries.none? { |entry| entry.person_habit.person_id == people(:two).id }
    sauna = day.entries.find { |entry| entry.person_habit == person_habits(:alex_sauna) }
    assert_nil sauna.check_in_on(Date.current - 7.days)
  end

  test "classifies active recorded scheduled and unscheduled states" do
    travel_to Time.zone.local(2026, 7, 29, 12) do
      habit = households(:home).habits.create!(name: "Pinned recovery")
      configuration = people(:one).person_habits.create!(
        habit: habit,
        saturday: false,
        sunday: false
      )
      configuration.habit_check_ins.create!(checked_on: Date.current)
      day = RecoveryDay.current(household: households(:home), person: people(:one))
      entry = day.entries.find { |candidate| candidate.person_habit == configuration }

      assert_equal :checked, entry.status_on(Date.current)
      assert_equal :not_scheduled, entry.status_on(Date.new(2026, 7, 25))
      assert_equal :not_checked, entry.status_on(Date.new(2026, 7, 28))
    end
  end

  test "schedule edits relabel only unrecorded dates" do
    configuration = person_habits(:alex_sauna)
    day = RecoveryDay.current(household: households(:home), person: people(:one))
    date = day.dates.find { |candidate| candidate != Date.current }
    configuration.update!(PersonHabit::WEEKDAYS.fetch(date.wday) => false)
    entry = RecoveryDay.current(household: households(:home), person: people(:one)).entries
      .find { |candidate| candidate.person_habit == configuration }

    assert_equal :not_scheduled, entry.status_on(date)
    configuration.update!(PersonHabit::WEEKDAYS.fetch(Date.current.wday) => false)
    entry = RecoveryDay.current(household: households(:home), person: people(:one)).entries
      .find { |candidate| candidate.person_habit == configuration }
    assert_equal :checked, entry.status_on(Date.current)
  end

  test "inactive recent history is checked or neutral and never actionable" do
    day = RecoveryDay.current(household: households(:home), person: people(:one))
    lights_out = day.entries.find { |entry| entry.person_habit == person_habits(:alex_lights_out) }

    assert_predicate lights_out, :history_only?
    assert_equal :checked, lights_out.status_on(Date.current - 1.day)
    assert_equal :no_record, lights_out.status_on(Date.current)
    assert_not_includes day.actionable_entries, lights_out
  end

  test "requires the person to belong to the supplied household scope" do
    assert_raises ActiveRecord::RecordNotFound do
      RecoveryDay.current(household: Household.new, person: people(:one))
    end
  end
end
