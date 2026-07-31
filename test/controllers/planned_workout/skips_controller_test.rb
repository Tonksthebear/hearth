require "test_helper"

class PlannedWorkout::SkipsControllerTest < ActionDispatch::IntegrationTest
  test "skips and restores a due plan with a reason" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)
      plan = planned_workouts(:planned_balanced)

      post planned_workout_skip_path(plan), params: { planned_workout: { skip_reason: "Sore" } }
      assert_redirected_to activity_week_path(date: plan.scheduled_on)
      assert_equal "Sore", plan.reload.skip_reason

      delete planned_workout_skip_path(plan)
      assert_redirected_to activity_week_path(date: plan.scheduled_on)
      assert_equal :planned, plan.reload.status
    end
  end

  test "skip and restore return to canonical Today when requested" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)
      plan = planned_workouts(:planned_balanced)

      post planned_workout_skip_path(plan), params: { return_to: "today" }
      assert_redirected_to root_path

      delete planned_workout_skip_path(plan), params: { return_to: "today" }
      assert_redirected_to root_path
    end
  end

  test "another person's plan is not mutable" do
    sign_in_as users(:one)

    post planned_workout_skip_path(planned_workouts(:sam_balanced))

    assert_response :not_found
  end
end
