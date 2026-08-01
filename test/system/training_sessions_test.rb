require "application_system_test_case"

class TrainingSessionsTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "requires confirmation before deleting an in-progress workout" do
    training_session = training_sessions(:in_progress)
    sign_in_via_browser users(:one)
    ensure_person_via_browser people(:one)
    visit_and_wait_for_path training_session_path(training_session)

    dismiss_confirm("Delete this in-progress workout?") { click_button "Delete in-progress workout" }
    assert TrainingSession.exists?(training_session.id)
    assert_current_path training_session_path(training_session)

    accept_confirm("Delete this in-progress workout?") { click_button "Delete in-progress workout" }
    assert_current_path training_week_path(date: training_session.performed_on), wait: 5
    assert_not TrainingSession.exists?(training_session.id)
  end

  test "starts a template snapshot records actual rows completes and updates progress" do
    travel_to WEEK_START do
      sign_in_via_browser users(:one)
      ensure_person_via_browser people(:one)
      click_link_and_wait_for_path "Activities", activity_week_path
      within "section[aria-labelledby='schedule-workout-heading']" do
        select_and_wait workout_templates(:balanced).title, from: "Workout template"
        set_date_and_wait "Scheduled date", WEEK_START.iso8601
        click_button "Add to agenda"
      end
      assert_text "Workout scheduled.", wait: 5
      within "[data-activity-date='#{WEEK_START.iso8601}'] li", text: workout_templates(:balanced).title do
        click_button "Start"
      end
      assert_selector "h1", text: "Record Balanced training day", wait: 15

      reps = all("input[name*='training_sets_attributes'][name$='[reps]']")
      loads = all("input[name*='training_sets_attributes'][name$='[load_amount]']")
      load_units = all("el-select[name*='training_sets_attributes'][name$='[load_unit]']")
      durations = all("input[name*='training_sets_attributes'][name$='[duration_seconds]']")
      completed = all("input[type='checkbox'][name*='training_sets_attributes'][name$='[completed]']")

      set_and_wait reps[0], "8"
      set_and_wait reps[1], "8"
      set_and_wait loads[0], "35"
      set_and_wait loads[1], "35"
      choose_elements_option load_units[0], "lb"
      choose_elements_option load_units[1], "lb"
      set_and_wait durations.first, "1800"
      completed.each { |field| check_and_wait field }

      click_button_and_wait_for_text "Complete workout", "Workout completed."
      assert_text(/completed workout/i)
      assert_text "Goblet squat"
      assert_text "Stationary bike"
      assert_text "per side"
      assert_text "3 sec lowering"

      click_link_and_wait_for_path "History", activity_history_path
      assert_text "Balanced training day"
      click_link_and_wait_for_path "Week", activity_week_path
      click_link_and_wait_for_path "Open training details", training_week_path(date: WEEK_START), match: :first
      assert_selector "article", text: /Structured minutes\s+100 min/
      assert_selector "article", text: /Strength sessions\s+2 sessions/
    end
  end

  test "saves resumes and completes a structured inline ad hoc workout without catalog mutation" do
    travel_to WEEK_START do
      exercise_count = Exercise.count
      sign_in_via_browser users(:one)
      ensure_person_via_browser people(:one)
      click_link_and_wait_for_path "Activities", activity_week_path
      click_link_and_wait_for_path "Open training details", training_week_path(date: WEEK_START), match: :first
      click_link_and_wait_for_path "Log ad hoc workout", new_training_session_path

      assert_field "Workout title", with: "Ad hoc workout", wait: 5
      fill_in "Workout title", with: "Neighborhood walk"
      assert_field "Workout title", with: "Neighborhood walk"
      fill_in_and_wait_for_value "Block title", "Outdoor walk"
      select_and_wait "Zone2", from: "Block kind"
      select_and_wait "Zone2", from: "Block dose"
      fill_in_and_wait_for_value "Actual duration (seconds)", "1800"
      fill_in_and_wait_for_value "Exercise name", "Neighborhood walk"
      select_and_wait "Cardio", from: "Modality"
      select_and_wait "Locomotion cardio", from: "Movement pattern"
      set_and_wait all("input[name*='training_sets_attributes'][name$='[reps]']").first, "12"
      exercise_performance_kind = all("el-select[name*='training_session_exercises_attributes'][name$='[snapshot_performance_kind]']").first
      choose_elements_option exercise_performance_kind, "Duration"
      select_and_wait "Zone2", from: "Default dose"
      select_and_wait "Zone2", from: all("el-select[name*='training_sets_attributes'][name$='[dose_class]']").first[:id]
      set_and_wait all("input[name*='training_sets_attributes'][name$='[duration_seconds]']").first, "1800"
      set_and_wait all("input[name*='training_sets_attributes'][name$='[count]']").first, "6"
      choose_elements_option all("el-select[name*='training_sets_attributes'][name$='[count_unit]']").first, "Laps"
      set_and_wait all("input[name*='training_sets_attributes'][name$='[average_heart_rate_bpm]']").first, "135"
      set_and_wait all("input[name*='training_sets_attributes'][name$='[peak_heart_rate_bpm]']").first, "148"
      check_and_wait all("input[type='checkbox'][name*='training_sets_attributes'][name$='[completed]']").first
      within "details", text: "Exercise feedback" do
        find("summary").click
        select_and_wait "About right", from: "Difficulty"
        fill_in_and_wait_for_value "Soreness or pain noted", "Mild calf tightness"
        fill_in_and_wait_for_value "Substitution used", "Outdoor route"
        fill_in_and_wait_for_value "Adjust next time", "Keep the same pace"
      end
      click_button_and_wait_for_text "Save progress", "Workout in progress saved."

      click_link_and_wait_for_path "Week", activity_week_path, match: :first
      click_link_and_wait_for_path "Open training details", training_week_path(date: WEEK_START), match: :first
      assert_selector "article", text: /Neighborhood walk.*excluded from progress until completed/m
      session = TrainingSession.find_by!(snapshot_title: "Neighborhood walk")
      within find("article", text: /Neighborhood walk/) do
        click_link "Resume workout"
      end
      assert_current_path edit_training_session_path(session)
      click_button_and_wait_for_text "Complete workout", "Workout completed."

      assert_equal exercise_count, Exercise.count
      assert_text "Neighborhood walk"
      assert_text(/completed workout/i)
      assert_text "About right"
      assert_text "Mild calf tightness"
      assert_text "Keep the same pace"
      assert_text "6 laps"
      assert_text "avg HR 135 bpm"
      assert_nil session.reload.training_session_blocks.first.training_session_exercises.first.training_sets.first.reps
    end
  end

  test "switching people removes prior person training and targets from rendered HTML" do
    travel_to WEEK_START do
      people(:one).update!(weekly_structured_minutes_target: 123)
      people(:two).update!(weekly_structured_minutes_target: 45)
      sign_in_via_browser users(:one)
      ensure_person_via_browser people(:one)

      click_link_and_wait_for_path "Activities", activity_week_path
      click_link_and_wait_for_path "Open training details", training_week_path(date: WEEK_START), match: :first
      assert_text "Resume me"
      assert_field "Structured minutes", with: "123"

      switch_person_via_browser people(:two)
      click_link_and_wait_for_path "Activities", activity_week_path
      click_link_and_wait_for_path "Open training details", training_week_path(date: WEEK_START), match: :first
      assert_no_text "Resume me"
      assert_no_text "Sunday balanced day"
      assert_text "Sam workout"
      assert_field "Structured minutes", with: "45"
      assert_no_field "Structured minutes", with: "123"
    end
  end

  test "records catalog interval rounds with separate work and recovery" do
    sign_in_via_browser users(:one)
    ensure_person_via_browser people(:one)

    [ [ 8, 20, 20 ], [ 8, 60, 60 ], [ 4, 240, 180 ] ].each do |rounds, work_seconds, rest_seconds|
      template = interval_template(rounds:, work_seconds:, rest_seconds:)
      session = TrainingSession.start_from(template:, person: people(:one), performed_on: WEEK_START)
      visit_and_wait_for_path edit_training_session_path(session)

      work_fields = all("input[name*='training_sets_attributes'][name$='[duration_seconds]']")
      recovery_fields = all("input[name*='training_sets_attributes'][name$='[rest_seconds]']")
      assert_equal rounds, work_fields.size
      assert_equal rounds, recovery_fields.size
      work_fields.each { |field| assert_equal work_seconds.to_s, field.value }
      recovery_fields.each { |field| assert_equal rest_seconds.to_s, field.value }
      all("input[type='checkbox'][name*='training_sets_attributes'][name$='[completed]']").each { |field| check_and_wait field }

      click_button_and_wait_for_text "Complete workout", "Workout completed."
      assert_text "#{work_seconds} sec work / #{rest_seconds} sec recovery"
    end
  end

  private
    def interval_template(rounds:, work_seconds:, rest_seconds:)
      template = households(:home).workout_templates.create!(
        title: "#{work_seconds}/#{rest_seconds} intervals",
        provenance_status: :personal
      )
      block = template.workout_blocks.create!(
        position: 1,
        title: "Intervals",
        block_kind: :hiit_interval,
        dose_class: :vigorous,
        planned_duration_minutes: (rounds * (work_seconds + rest_seconds) / 60.0).ceil
      )
      block.exercise_prescriptions.create!(
        exercise: exercises(:bike),
        position: 1,
        performance_kind: :interval,
        sets_count: rounds,
        work_seconds: work_seconds,
        rest_seconds: rest_seconds,
        dose_class: :vigorous
      )
      template
    end
end
