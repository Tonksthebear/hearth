require "test_helper"

class HabitCheckInsControllerTest < ActionDispatch::IntegrationTest
  test "creates today's check-in for Current person while ignoring a forged date" do
    sign_in_as users(:one)
    habit = households(:home).habits.create!(name: "Stretch")
    metric = habit.habit_metrics.create!(key: "duration", label: "Duration", value_type: "duration", unit: "minutes", position: 1)
    configuration = people(:one).person_habits.create!(habit: habit)

    assert_difference("HabitCheckIn.count", 1) do
      post habit_check_ins_path, params: {
        habit_check_in: {
          person_habit_id: configuration.id,
          checked_on: Date.current - 1.day,
          habit_check_in_measurements_attributes: {
            "0" => { habit_metric_id: metric.id, duration_value: "12" }
          }
        }
      }
    end

    assert_equal Date.current, configuration.habit_check_ins.last.checked_on
    assert_redirected_to recovery_day_path
  end

  test "corrects only Current person's current-date check-in" do
    sign_in_as users(:one)
    check_in = habit_check_ins(:alex_sauna_today)

    patch habit_check_in_path(check_in), params: {
      habit_check_in: {
        notes: "Corrected",
        person_habit_id: person_habits(:sam_sauna).id,
        habit_check_in_measurements_attributes: {
          "0" => {
            id: habit_check_in_measurements(:alex_sauna_duration_today).id,
            habit_metric_id: habit_metrics(:sauna_duration).id,
            duration_value: "22"
          },
          "1" => {
            id: habit_check_in_measurements(:alex_sauna_temperature_today).id,
            habit_metric_id: habit_metrics(:sauna_temperature).id,
            number_value: "172"
          }
        }
      }
    }

    assert_redirected_to recovery_day_path
    assert_equal "Corrected", check_in.reload.notes
    assert_equal 22, habit_check_in_measurements(:alex_sauna_duration_today).reload.duration_value
    assert_equal 12, habit_check_in_measurements(:sam_sauna_duration_today).reload.duration_value
  end

  test "invalid typed measurement rerenders the complete recovery page without a partial write" do
    sign_in_as users(:one)
    check_in = habit_check_ins(:alex_sauna_today)

    patch habit_check_in_path(check_in), params: {
      habit_check_in: {
        notes: "Should roll back",
        habit_check_in_measurements_attributes: {
          "0" => {
            id: habit_check_in_measurements(:alex_sauna_duration_today).id,
            habit_metric_id: habit_metrics(:sauna_duration).id,
            number_value: "22",
            duration_value: ""
          },
          "1" => {
            id: habit_check_in_measurements(:alex_sauna_temperature_today).id,
            habit_metric_id: habit_metrics(:sauna_temperature).id,
            number_value: "172"
          }
        }
      }
    }

    assert_response :unprocessable_entity
    assert_select "h1", text: "Recovery"
    assert_select "#check-in-errors", text: /must use its duration value/
    assert_equal "Felt comfortable", check_in.reload.notes
    assert_equal 18, habit_check_in_measurements(:alex_sauna_duration_today).reload.duration_value
  end

  test "cannot update or destroy another person's or an old-date check-in" do
    sign_in_as users(:one)

    patch habit_check_in_path(habit_check_ins(:sam_sauna_today)), params: { habit_check_in: { notes: "Forged" } }
    assert_response :not_found

    delete habit_check_in_path(habit_check_ins(:alex_sauna_outside_window))
    assert_response :not_found

    assert_not_equal "Forged", habit_check_ins(:sam_sauna_today).reload.notes
    assert HabitCheckIn.exists?(habit_check_ins(:alex_sauna_outside_window).id)
  end

  test "clears today's completion-only check-in" do
    sign_in_as users(:one)

    assert_difference("HabitCheckIn.count", -1) do
      delete habit_check_in_path(habit_check_ins(:alex_water_today))
    end

    assert_redirected_to recovery_day_path
  end
end
