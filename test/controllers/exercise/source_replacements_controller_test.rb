require "test_helper"
require_relative "../../test_helpers/exercise_visual_test_helper"
require_relative "../../test_helpers/workout_guide_import_test_helper"

class Exercise::SourceReplacementsControllerTest < ActionDispatch::IntegrationTest
  include ExerciseVisualTestHelper
  include WorkoutGuideImportTestHelper

  test "requires authentication" do
    post exercise_source_replacement_path(exercises(:squat))
    assert_redirected_to new_session_path
  end

  test "unknown exercise ids raise rather than falling back to Exercise.find" do
    sign_in_as users(:one)

    post exercise_source_replacement_path(Exercise.maximum(:id) + 1)
    assert_response :not_found
  end

  test "replace returns a turbo stream naming changed and preserved values" do
    sign_in_as users(:one)
    exercise = import_and_edit_bench_press

    post exercise_source_replacement_path(exercise), as: :turbo_stream

    assert_response :success
    assert_match(/Bench Press/, response.body)
    assert_match(/Changed:/, response.body)
    assert_match(/Preserved:/, response.body)
    assert_equal "Barbell", exercise.reload.equipment
  end

  test "replace is refused when source_removed_at is set" do
    sign_in_as users(:one)
    exercise = import_and_edit_bench_press
    exercise.update!(source_removed_at: Time.current)

    assert_no_changes -> { exercise.reload.equipment } do
      post exercise_source_replacement_path(exercise)
    end

    assert_redirected_to exercise_path(exercise)
  end

  test "refuses replace without mutation while a catalog run is active" do
    sign_in_as users(:one)
    exercise = import_and_edit_bench_press
    WorkoutGuide::ImportRun.create!(household: households(:home), status: "running", started_at: Time.current)

    assert_no_changes -> { exercise.reload.equipment } do
      post exercise_source_replacement_path(exercise), as: :turbo_stream
    end

    assert_response :conflict
    assert_match(/already running/, response.body)
  end

  private
    def import_and_edit_bench_press
      fixture_workout_guide_import.run
      exercise = households(:home).exercises.find_by!(source_key: "workout_guide:bench-press")
      exercise.update!(equipment: "Household bar")
      exercise
    end
end
