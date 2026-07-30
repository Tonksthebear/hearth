require "test_helper"

class ExercisesControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get exercises_path
    assert_redirected_to new_session_path
  end

  test "renders and maintains the household exercise catalog" do
    sign_in_as users(:one)

    get exercises_path
    assert_response :success
    assert_select "h2", text: exercises(:squat).name

    assert_difference "Exercise.count", 1 do
      post exercises_path, params: {
        exercise: {
          name: "Farmer carry",
          modality: "strength",
          movement_pattern: "carry",
          equipment: "Kettlebells",
          guidance: "Walk tall."
        }
      }
    end

    exercise = households(:home).exercises.find_by!(name: "Farmer carry")
    assert_redirected_to exercise_path(exercise)

    patch exercise_path(exercise), params: { exercise: { guidance: "Brace and walk tall." } }
    assert_redirected_to exercise_path(exercise)
    assert_equal "Brace and walk tall.", exercise.reload.guidance
  end

  test "invalid submissions render the complete form" do
    sign_in_as users(:one)

    post exercises_path, params: { exercise: { name: "", modality: "", movement_pattern: "" } }

    assert_response :unprocessable_entity
    assert_select "form[action='#{exercises_path}']"
    assert_select "el-select[name='exercise[modality]']"
    assert_select "el-select[name='exercise[movement_pattern]']"
  end

  test "does not render or load an exercise belonging to another household" do
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    other_household_id = Household.insert_all!([ {
      name: "Impossible second installation",
      installation_key: 2,
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    other_exercise_id = Exercise.insert_all!([ {
      household_id: other_household_id,
      name: "Other household movement",
      modality: "strength",
      movement_pattern: "carry",
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    connection.execute("PRAGMA ignore_check_constraints = OFF")
    sign_in_as users(:one)

    get exercises_path
    assert_response :success
    assert_select "h2", text: "Other household movement", count: 0

    get exercise_path(other_exercise_id)
    assert_response :not_found

    get new_workout_template_path
    assert_response :success
    assert_select "option[value='#{other_exercise_id}']", count: 0
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end
end
