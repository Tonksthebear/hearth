require "test_helper"

class HabitsControllerTest < ActionDispatch::IntegrationTest
  test "creates a normalized ordered metric graph" do
    sign_in_as users(:one)

    assert_difference({ "Habit.count" => 1, "HabitMetric.count" => 2 }) do
      post habits_path, params: {
        habit: {
          name: "Breathing",
          description: "A calm breathing session.",
          habit_metrics_attributes: {
            "0" => { key: "minutes", label: "Minutes", value_type: "duration", unit: "minutes" },
            "1" => { key: "rounds", label: "Rounds", value_type: "number", unit: "rounds" }
          }
        }
      }
    end

    habit = households(:home).habits.find_by!(name: "Breathing")
    assert_redirected_to habits_path
    assert_equal [ 1, 2 ], habit.habit_metrics.pluck(:position)
  end

  test "Turbo structural actions preserve values without persistence" do
    sign_in_as users(:one)

    assert_no_difference [ "Habit.count", "HabitMetric.count" ] do
      post habits_path,
        params: {
          habit: {
            name: "Breathing",
            habit_metrics_attributes: {
              "0" => { key: "minutes", label: "Minutes", value_type: "duration", unit: "minutes" }
            }
          },
          add_metric: "1"
        },
        headers: turbo_stream_headers
    end

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='habit_form']"
    assert_select "input[value='Breathing']"
    assert_select "input[name$='[key]']", count: 2
  end

  test "invalid structural coordinates render the complete form safely" do
    sign_in_as users(:one)

    post habits_path,
      params: { habit: { name: "Breathing" }, move_metric: "0:up" },
      headers: turbo_stream_headers

    assert_response :unprocessable_entity
    assert_select "#habit-errors", text: /Invalid habit metric row/
    assert_select "turbo-stream[action='replace'][target='habit_form']"
  end

  test "persisted metric moves save normalized positions" do
    sign_in_as users(:one)
    habit = habits(:sauna)

    patch habit_path(habit), params: {
      habit: {
        name: habit.name,
        description: habit.description,
        habit_metrics_attributes: habit.habit_metrics.each_with_index.to_h do |metric, index|
          [ index.to_s, {
            id: metric.id,
            key: metric.key,
            label: metric.label,
            value_type: metric.value_type,
            unit: metric.unit
          } ]
        end
      },
      move_metric: "1:up"
    }, headers: turbo_stream_headers

    assert_response :success

    patch habit_path(habit), params: {
      habit: {
        name: habit.name,
        description: habit.description,
        habit_metrics_attributes: css_select("input[name$='[id]']").each_with_index.to_h do |input, index|
          metric = HabitMetric.find(input["value"])
          [ index.to_s, {
            id: metric.id,
            key: metric.key,
            label: metric.label,
            value_type: metric.value_type,
            unit: metric.unit,
            position: index + 1
          } ]
        end
      }
    }

    assert_redirected_to habits_path
    assert_equal [ habit_metrics(:sauna_temperature).id, habit_metrics(:sauna_duration).id ], habit.reload.habit_metrics.pluck(:id)
  end

  private
    def turbo_stream_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end
end
