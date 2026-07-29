require "test_helper"

class PersonHabitsControllerTest < ActionDispatch::IntegrationTest
  test "activation always belongs to Current person and defaults to all days" do
    sign_in_as users(:one)

    assert_difference("people(:one).person_habits.count", 1) do
      post person_habits_path, params: { habit_id: habits(:movement).id, person_id: people(:two).id }
    end

    configuration = people(:one).person_habits.find_by!(habit: habits(:movement))
    assert_redirected_to edit_person_habit_path(configuration)
    assert PersonHabit::WEEKDAYS.all? { |weekday| configuration.public_send(weekday) }
    assert_not_equal people(:two), configuration.person
  end

  test "update saves a typed target and changes active visibility" do
    sign_in_as users(:one)
    configuration = person_habits(:alex_sauna)
    target = person_habit_metrics(:alex_sauna_duration_target)

    patch person_habit_path(configuration), params: {
      person_habit: {
        active: "0",
        monday: "1",
        person_habit_metrics_attributes: {
          "0" => {
            id: target.id,
            habit_metric_id: target.habit_metric_id,
            duration_value: "25"
          }
        }
      }
    }

    assert_redirected_to recovery_day_path
    assert_not configuration.reload.active?
    assert_equal 25, target.reload.duration_value
  end

  test "cannot update another person's configuration" do
    sign_in_as users(:one)

    patch person_habit_path(person_habits(:sam_sauna)), params: { person_habit: { active: "0" } }

    assert_response :not_found
    assert_predicate person_habits(:sam_sauna).reload, :active?
  end

  test "forged metric definition rerenders with model errors" do
    sign_in_as users(:one)
    configuration = person_habits(:alex_sauna)

    patch person_habit_path(configuration), params: {
      person_habit: {
        active: "1",
        person_habit_metrics_attributes: {
          "0" => { habit_metric_id: habit_metrics(:movement_duration).id, duration_value: "10" }
        }
      }
    }

    assert_response :unprocessable_entity
    assert_select "body", text: /must belong to the configured habit/
    assert_nil PersonHabitMetric.find_by(
      person_habit: configuration,
      habit_metric: habit_metrics(:movement_duration)
    )
  end

  test "saving an inactive configuration preserves inactive state" do
    sign_in_as users(:one)
    configuration = person_habits(:alex_lights_out)

    get edit_person_habit_path(configuration)

    assert_response :success
    configuration_form = css_select("form[action='#{person_habit_path(configuration)}']")
      .find { |form| form.at_css("input[type='submit'][value='Save configuration']") }
    assert_not_nil configuration_form
    assert_nil configuration_form.at_css("input[name='person_habit[active]']")

    patch person_habit_path(configuration), params: {
      person_habit: {
        monday: "1",
        tuesday: "0",
        wednesday: "1",
        thursday: "1",
        friday: "1",
        saturday: "1",
        sunday: "1"
      }
    }

    assert_redirected_to recovery_day_path
    assert_not configuration.reload.active?
    assert_not configuration.tuesday?
  end
end
