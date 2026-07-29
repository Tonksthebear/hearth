require "application_system_test_case"

class ExercisesAndWorkoutTemplatesTest < ApplicationSystemTestCase
  test "creates a structured exercise and attributed workout template through the real UI" do
    sign_in_via_browser users(:one)

    within "nav[aria-label='Household and person context']" do
      click_link_and_wait_for_path "Exercises", exercises_path
    end
    click_link_and_wait_for_path "Add exercise", new_exercise_path
    fill_in_and_wait_for_value "Name", "Farmer carry"
    select_and_wait "Strength", from: "Modality"
    select_and_wait "Carry", from: "Movement pattern"
    fill_in_and_wait_for_value "Equipment", "Kettlebells"
    fill_in_and_wait_for_value "Guidance", "Walk tall and brace."
    click_button_and_wait_for_text "Create Exercise", "Farmer carry"

    within "nav[aria-label='Household and person context']" do
      click_link_and_wait_for_path "Workout templates", workout_templates_path
    end
    click_link_and_wait_for_path "Add workout template", new_workout_template_path
    fill_in_and_wait_for_value "Title", "Carry practice"
    select_and_wait "Personal", from: "Provenance"
    find_field("Block title").set("Loaded carries")
    assert_field "Block title", with: "Loaded carries"
    select_and_wait "Strength", from: "Block kind"
    select_and_wait "Strength", from: "Dose class"
    fill_in_and_wait_for_value "Planned minutes", "15"
    select_and_wait "Farmer carry", from: "Catalog exercise"
    select_and_wait "Set", from: "Entry kind"
    find_field("Sets / rounds").set("3")
    assert_field "Sets / rounds", with: "3"
    fill_in_and_wait_for_value "Min reps", "1"
    fill_in_and_wait_for_value "Max reps", "1"
    fill_in_and_wait_for_value "Target RPE", "7"
    click_button_and_wait_for_text "Create Workout template", "Carry practice"

    assert_selector "h1", text: "Carry practice"
    assert_text "Farmer carry"
    assert_text "Personal"
    assert_text "not clinical endorsement"
    assert_text "medical advice"
  end
end
