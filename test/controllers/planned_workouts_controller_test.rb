require "test_helper"

class PlannedWorkoutsControllerTest < ActionDispatch::IntegrationTest
  test "creates reschedules and removes a current person plan" do
    sign_in_as users(:one)

    assert_difference "PlannedWorkout.count", 1 do
      post planned_workouts_path, params: {
        planned_workout: {
          workout_template_id: workout_templates(:balanced).id,
          scheduled_on: "2026-08-01"
        }
      }
    end
    plan = people(:one).planned_workouts.order(:created_at).last
    assert_redirected_to activity_week_path(date: plan.scheduled_on)

    patch planned_workout_path(plan), params: { planned_workout: { scheduled_on: "2026-08-02" } }
    assert_redirected_to activity_week_path(date: "2026-08-02")
    assert_equal Date.new(2026, 8, 2), plan.reload.scheduled_on

    assert_difference "PlannedWorkout.count", -1 do
      delete planned_workout_path(plan)
    end
    assert_redirected_to activity_week_path(date: "2026-08-02")
  end

  test "rejected reschedule redirects with an alert and preserves the schedule create form" do
    sign_in_as users(:one)
    plan = planned_workouts(:linked_in_progress)

    patch planned_workout_path(plan), params: { planned_workout: { scheduled_on: "2026-08-02" } }

    assert_redirected_to activity_week_path(date: plan.scheduled_on)
    assert_equal "Only an unstarted planned workout can be rescheduled.", flash[:alert]

    follow_redirect!
    assert_select "section[aria-labelledby='schedule-workout-heading'] form[action=?][method='post']", planned_workouts_path
  end

  test "reschedule and remove return to canonical Today when requested" do
    sign_in_as users(:one)
    plan = planned_workouts(:planned_balanced)

    patch planned_workout_path(plan),
      params: { planned_workout: { scheduled_on: plan.scheduled_on }, return_to: "today" }
    assert_redirected_to root_path

    delete planned_workout_path(plan), params: { return_to: "today" }
    assert_redirected_to root_path
  end

  test "invalid create renders the real week page" do
    sign_in_as users(:one)

    assert_no_difference "PlannedWorkout.count" do
      post planned_workouts_path, params: {
        planned_workout: { workout_template_id: "", scheduled_on: "2026-07-30" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Week agenda"
  end

  test "another person's plan is not mutable" do
    sign_in_as users(:one)

    patch planned_workout_path(planned_workouts(:sam_balanced)),
      params: { planned_workout: { scheduled_on: "2026-08-01" } }

    assert_response :not_found
  end
end
