require "application_system_test_case"

class ActivitiesAgendaTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "navigates dates and changes planned and skipped workout outcomes" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      planned_workouts(:planned_balanced).destroy!
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_week_path

      assert_selector "[data-activity-date='2026-07-30']", text: "Today"
      click_link_and_wait_for_path "Previous", activity_week_path(date: WEEK_START - 7.days)
      assert_selector "[data-activity-date='2026-07-20']"
      click_link_and_wait_for_path "Current week", activity_week_path

      existing_plan_ids = PlannedWorkout.ids
      within "section[aria-labelledby='schedule-workout-heading']" do
        select_and_wait workout_templates(:balanced).title, from: "Workout template"
        set_date_and_wait "Scheduled date", "2026-07-30"
        click_button "Add to agenda"
      end
      assert_text "Workout scheduled.", wait: 5
      plan = PlannedWorkout.where.not(id: existing_plan_ids).sole
      assert_equal people(:one), plan.person
      assert_equal Date.new(2026, 7, 30), plan.scheduled_on

      within "[data-activity-date='2026-07-30'] li", text: workout_templates(:balanced).title do
        set_date_and_wait "Reschedule date", "2026-07-31"
        click_button "Reschedule"
      end
      assert_current_path activity_week_path(date: "2026-07-31"), wait: 5
      assert_selector "[data-activity-date='2026-07-31'] li", text: workout_templates(:balanced).title

      within "[data-activity-date='2026-07-31'] li", text: workout_templates(:balanced).title do
        accept_confirm("Remove this workout from the plan?") { click_button "Remove" }
      end
      assert_no_selector "form[action='#{planned_workout_path(plan)}']", wait: 5

      skipped_plan = people(:one).planned_workouts.create!(
        household: households(:home),
        workout_template: workout_templates(:balanced),
        scheduled_on: Date.current
      )
      visit_and_wait_for_path activity_week_path
      within "[data-activity-date='2026-07-30'] li", text: workout_templates(:balanced).title do
        fill_in "Skip reason (optional)", with: "Recovery day"
        click_button "Skip"
      end
      assert_selector "[data-activity-status='skipped']", text: "Recovery day", wait: 5

      click_link_and_wait_for_path "History", activity_history_path
      assert_selector "[data-history-status='skipped']", text: "Recovery day"
      click_link_and_wait_for_path "Week", activity_week_path
      within "[data-activity-date='2026-07-30'] [data-activity-status='skipped']", text: workout_templates(:balanced).title do
        click_button "Restore"
      end
      assert_selector "form[action='#{planned_workout_path(skipped_plan)}']", wait: 5
    end
  end

  test "switching people removes prior person agenda controls and records" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_week_path

      assert_selector "form[action='#{planned_workout_path(planned_workouts(:planned_balanced))}']"
      switch_person_via_browser people(:two)

      assert_no_selector "form[action='#{planned_workout_path(planned_workouts(:planned_balanced))}']"
      assert_selector "form[action='#{planned_workout_path(planned_workouts(:sam_balanced))}']"
      assert_no_text training_sessions(:in_progress).snapshot_title
    end
  end
end
