require "test_helper"

class WeeklyDoseTargetsControllerTest < ActionDispatch::IntegrationTest
  test "updates exactly Current person's nullable targets" do
    sign_in_as users(:one)

    patch weekly_dose_target_path, params: {
      date: "2026-07-29",
      person: {
        weekly_structured_minutes_target: "180",
        weekly_strength_sessions_target: "3",
        weekly_zone2_minutes_target: "",
        weekly_vigorous_minutes_target: "20"
      }
    }

    assert_redirected_to training_week_path(date: "2026-07-29")
    assert_equal 180, people(:one).reload.weekly_structured_minutes_target
    assert_equal 3, people(:one).weekly_strength_sessions_target
    assert_nil people(:one).weekly_zone2_minutes_target
    assert_equal 20, people(:one).weekly_vigorous_minutes_target
    assert_nil people(:two).weekly_structured_minutes_target
  end

  test "invalid targets rerender the week with errors" do
    sign_in_as users(:one)

    patch weekly_dose_target_path, params: {
      date: "2026-07-29",
      person: { weekly_structured_minutes_target: "0" }
    }

    assert_response :unprocessable_entity
    assert_select "h1", text: "Training"
    assert_select "section[aria-labelledby='targets-heading']", text: /must be greater than 0/
  end
end
