require "test_helper"
require_relative "../../test_helpers/exercise_visual_test_helper"
require_relative "../../test_helpers/workout_guide_import_test_helper"

class Exercise::SourceLinksControllerTest < ActionDispatch::IntegrationTest
  include ExerciseVisualTestHelper
  include WorkoutGuideImportTestHelper

  test "requires authentication" do
    get new_exercise_source_link_path(exercises(:squat))
    assert_redirected_to new_session_path

    post exercise_source_link_path(exercises(:squat)), params: { source_link: { source_key: "workout_guide:bench-press" } }
    assert_redirected_to new_session_path
  end

  test "unknown exercise ids raise rather than falling back to Exercise.find" do
    sign_in_as users(:one)

    post exercise_source_link_path(Exercise.maximum(:id) + 1), params: { source_link: { source_key: "workout_guide:bench-press" } }
    assert_response :not_found
  end

  test "foreign household exercise ids are not found and remain unchanged" do
    foreign_id = insert_foreign_exercise
    sign_in_as users(:one)

    get new_exercise_source_link_path(foreign_id)
    assert_response :not_found

    assert_no_changes -> { Exercise.find(foreign_id).source_key } do
      post exercise_source_link_path(foreign_id), params: { source_link: { source_key: "workout_guide:bench-press" } }
    end
    assert_response :not_found
  end

  test "link refuses without mutation when an import starts after the availability check" do
    sign_in_as users(:one)
    exercise = exercises(:squat)

    assert_no_changes -> { exercise.reload.source_key } do
      with_import_started_during_record_for do
        post exercise_source_link_path(exercise),
          params: { source_link: { source_key: "workout_guide:bench-press" } },
          as: :turbo_stream
      end
    end

    assert_response :conflict
    assert_match(/already running/, response.body)
    assert WorkoutGuide::ImportRun.active?(households(:home))
  end

  test "links a household exercise and returns applied and preserved values" do
    sign_in_as users(:one)
    exercise = exercises(:squat)
    exercise.update!(equipment: "Household dumbbell")

    post exercise_source_link_path(exercise),
      params: { source_link: { source_key: "workout_guide:bench-press" } },
      as: :turbo_stream

    assert_response :success
    assert_match(/preserved/i, response.body)
    assert_match(/Goblet squat|name/i, response.body)
    exercise.reload
    assert_equal "workout_guide:bench-press", exercise.source_key
    assert_equal "Goblet squat", exercise.name
    assert_equal "Household dumbbell", exercise.equipment
    assert_equal "Keep the torso tall.", exercise.guidance
  end

  test "refuses link without mutation while a catalog run is active" do
    sign_in_as users(:one)
    exercise = exercises(:squat)
    WorkoutGuide::ImportRun.create!(household: households(:home), status: "queued")

    assert_no_changes -> { exercise.reload.source_key } do
      post exercise_source_link_path(exercise),
        params: { source_link: { source_key: "workout_guide:bench-press" } },
        as: :turbo_stream
    end

    assert_response :conflict
    assert_match(/already running/, response.body)
  end

  test "the html conflict response renders the full show page" do
    sign_in_as users(:one)
    exercise = exercises(:squat)
    WorkoutGuide::ImportRun.create!(household: households(:home), status: "running", started_at: Time.current)

    assert_no_changes -> { exercise.reload.source_key } do
      post exercise_source_link_path(exercise),
        params: { source_link: { source_key: "workout_guide:bench-press" } }
    end

    assert_response :conflict
    assert_match(/already running/, response.body)
    assert_select "article#exercise_show"
    assert_select "section[aria-label='Muscle map']"
  end
end
