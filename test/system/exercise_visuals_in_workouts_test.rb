require "application_system_test_case"
require_relative "../test_helpers/exercise_visual_test_helper"
require_relative "../test_helpers/workout_guide_import_test_helper"

class ExerciseVisualsInWorkoutsTest < ApplicationSystemTestCase
  include ExerciseVisualTestHelper
  include WorkoutGuideImportTestHelper

  test "imported catalog thumbnails appear on the template and recording form" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercises_path

    with_fixture_workout_guide_import do
      click_button "Import Workout Guide"
      assert_text(/queued|running/i, wait: 5)
      perform_enqueued_jobs
      assert_text "Last import summary", wait: 10
      assert_text "Created"
    end

    imported = households(:home).exercises.find_by!(source_key: "workout_guide:bench-press")
    visit_and_wait_for_path exercises_path
    click_link_and_wait_for_path "Bench Press", exercise_path(imported), match: :first
    assert_selector "h1", text: "Bench Press"

    click_link_and_wait_for_path "Library", activity_library_path
    click_link_and_wait_for_path "All templates", workout_templates_path
    click_link_and_wait_for_path "Add workout template", new_workout_template_path
    fill_in_and_wait_for_value "Title", "Imported bench day"
    select_and_wait "Personal", from: "Provenance"
    fill_in_and_wait_for_value "Block title", "Presses"
    select_and_wait "Strength", from: "Block kind"
    select_and_wait "Strength", from: "Dose class"
    select_and_wait "Bench Press", from: "Catalog exercise"
    select_and_wait "Reps", from: "Primary performance"
    fill_in_and_wait_for_value "Sets / rounds", "3"
    fill_in_and_wait_for_value "Minimum reps", "5"
    fill_in_and_wait_for_value "Maximum reps", "5"
    click_button_and_wait_for_text "Create Workout template", "Imported bench day"

    assert_selector "h1", text: "Imported bench day"
    assert_operator page.evaluate_script("document.querySelector('[data-exercise-thumbnail] img').naturalWidth"), :>, 0

    click_button "Start workout"
    assert_current_path %r{/training_sessions/\d+/edit}, wait: 5
    assert_operator page.evaluate_script("document.querySelector('[data-exercise-thumbnail] img').naturalWidth"), :>, 0
  end
end
