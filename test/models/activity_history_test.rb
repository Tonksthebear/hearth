require "test_helper"

class ActivityHistoryTest < ActiveSupport::TestCase
  test "lists only selected-person outcomes in reverse chronology" do
    history = ActivityHistory.new(household: households(:home), person: people(:one))

    assert_includes history.items.map(&:record), training_sessions(:completed_sunday)
    assert_includes history.items.map(&:record), planned_workouts(:skipped_balanced)
    refute_includes history.items.map(&:record), training_sessions(:other_person)
    refute_includes history.items.map(&:record), planned_workouts(:sam_balanced)
    assert_equal history.items.map(&:occurred_on).sort.reverse, history.items.map(&:occurred_on)
  end
end
