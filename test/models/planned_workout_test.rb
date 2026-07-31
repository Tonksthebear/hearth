require "test_helper"

class PlannedWorkoutTest < ActiveSupport::TestCase
  test "derives lifecycle status without a stored status column" do
    assert_equal :planned, planned_workouts(:planned_balanced).status
    assert_equal :in_progress, planned_workouts(:linked_in_progress).status
    assert_equal :skipped, planned_workouts(:skipped_balanced).status

    training_sessions(:in_progress).update!(completed_at: Time.current)
    assert_equal :completed, planned_workouts(:linked_in_progress).reload.status
  end

  test "starts one immutable session snapshot and links it atomically" do
    travel_to Time.zone.local(2026, 7, 30, 10) do
      plan = planned_workouts(:planned_balanced)

      assert_difference "TrainingSession.count", 1 do
        session = plan.start!
        assert_equal Date.new(2026, 7, 30), session.performed_on
        assert_equal workout_templates(:balanced), session.workout_template
      end

      assert_equal :in_progress, plan.reload.status
      assert_raises(ActiveRecord::RecordInvalid) { plan.start! }
    end
  end

  test "skip is a retained due outcome and restore returns it to planned" do
    travel_to Time.zone.local(2026, 7, 30, 10) do
      plan = planned_workouts(:planned_balanced)
      plan.skip!(reason: "Travel")

      assert_equal :skipped, plan.status
      assert_equal "Travel", plan.skip_reason
      assert_not plan.destroy
      assert PlannedWorkout.exists?(plan.id)

      plan.restore!
      assert_equal :planned, plan.status
      assert_nil plan.skip_reason
    end
  end

  test "future plan cannot be skipped but can be removed as planning correction" do
    travel_to Time.zone.local(2026, 7, 30, 10) do
      plan = planned_workouts(:future_balanced)

      assert_raises(ActiveRecord::RecordInvalid) { plan.skip! }
      assert_difference "PlannedWorkout.count", -1 do
        plan.destroy!
      end
    end
  end

  test "linked and skipped plans cannot be rescheduled or removed" do
    assert_raises(ActiveRecord::RecordInvalid) do
      planned_workouts(:linked_in_progress).reschedule!(scheduled_on: Date.new(2026, 8, 1))
    end
    assert_not planned_workouts(:linked_in_progress).destroy
    assert_not planned_workouts(:skipped_balanced).destroy
  end

  test "deleting an incomplete session returns its plan to planned" do
    session = training_sessions(:in_progress)
    plan = planned_workouts(:linked_in_progress)

    session.destroy!

    assert_nil plan.reload.training_session
    assert_equal :planned, plan.status
  end

  test "rejects cross-person and cross-household graph assignments" do
    plan = PlannedWorkout.new(
      household: households(:home),
      person: people(:two),
      workout_template: workout_templates(:balanced),
      training_session: training_sessions(:in_progress),
      scheduled_on: Date.current
    )

    assert_not plan.valid?
    assert_includes plan.errors[:training_session], "must belong to this person"
  end
end
