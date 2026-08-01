require "application_system_test_case"

class TodayNavigationTest < ApplicationSystemTestCase
  test "runs the current-person Today path and traverses the new information architecture" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      sign_in_via_browser users(:one)

      assert_selector "h1", text: "Today"
      assert_selector "[data-activity-kind='planned_meal']", text: recipes(:observed_soup).title
      assert_selector "[data-activity-kind='workout']", text: training_sessions(:in_progress).snapshot_title

      within "[data-activity-kind='simple_habit']", text: "Water" do
        click_button "Check off"
      end
      assert_current_path root_path, wait: 5
      assert_selector "[data-activity-kind='habit_check_in']", text: "Water"

      click_link_and_wait_for_path "Meals", meal_week_path
      click_link_and_wait_for_path "Activities", activity_week_path

      click_link_and_wait_for_path people(:one).name, person_path(people(:one)), match: :first
      assert_link "Open #{people(:one).name}'s meals"

      click_link_and_wait_for_path "Hearth", root_path
      click_link_and_wait_for_path "Household overview", household_week_path
      assert_selector "h1", text: "Household week"
    end
  end


  test "converts a due meal plan and links the completed Today row to the Meal" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      plan = planned_meals(:shared_soup_target_week)

      within "[data-activity-kind='planned_meal']", text: plan.recipe.title do
        click_button "Log as eaten"
      end
      assert_text "was logged for #{people(:one).name}", wait: 5
      meal = plan.meals.find_by!(person: people(:one))
      assert_current_path meal_path(meal), wait: 5

      click_link_and_wait_for_path "Hearth", root_path
      within "[data-activity-kind='meal']", text: meal.description do
        click_link meal.description
      end
      assert_current_path meal_path(meal), wait: 5
    end
  end

  test "keeps plan corrections on Today and starts a due workout from there" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      plan = planned_workouts(:planned_balanced)

      within "[data-activity-kind='workout']", text: workout_templates(:balanced).title do
        fill_in "Skip reason (optional)", with: "Not ready"
        click_button "Skip"
      end
      assert_current_path root_path, wait: 5
      assert_selector "[data-activity-status='skipped']", text: "Not ready"

      within "[data-activity-status='skipped']", text: workout_templates(:balanced).title do
        click_button "Restore"
      end
      assert_current_path root_path, wait: 5

      within "[data-activity-kind='workout']", text: workout_templates(:balanced).title do
        click_button "Start"
      end
      assert_current_path %r{/training_sessions/\d+/edit\z}, wait: 15
      assert_text "Workout started."
      assert_current_path edit_training_session_path(plan.reload.training_session), wait: 5
      assert_equal :in_progress, plan.status
    end
  end


  test "renders the daily summary on mobile and reaches a measured habit recording unit in one activation" do
    browser = page.driver.browser
    browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 390,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )
    browser.execute_cdp(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: "light" } ]
    )

    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_sauna).habit_check_ins.destroy_all
      planned_workouts(:planned_balanced).update!(skipped_at: Time.current, skip_reason: "Recovery")
      sign_in_via_browser users(:one)

      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert_selector "#today-summary-heading", text: "Today at a glance"
      assert_selector "[data-today-summary-fact]", count: 3
      assert_no_text "Planned meal"
      assert_no_text "Simple habit"
      assert_no_text "Measured habit"
      summary_card = find("[data-today-summary-fact='meals']")
      attention_card = find("[data-today-summary-fact='attention'][data-tone='attention']")
      light_background = page.evaluate_script("getComputedStyle(arguments[0]).backgroundColor", summary_card)
      refute_equal page.evaluate_script("getComputedStyle(arguments[0]).boxShadow", summary_card),
        page.evaluate_script("getComputedStyle(arguments[0]).boxShadow", attention_card)

      browser.execute_cdp(
        "Emulation.setEmulatedMedia",
        features: [ { name: "prefers-color-scheme", value: "dark" } ]
      )
      dark_background = page.evaluate_script("getComputedStyle(arguments[0]).backgroundColor", summary_card)
      assert_not_equal light_background, dark_background

      within "[data-activity-kind='measured_habit']", text: habits(:sauna).name do
        click_link "Record details"
      end

      target_id = "recovery-person-habit-#{person_habits(:alex_sauna).id}"
      assert_current_path recovery_day_path, ignore_query: true, wait: 5
      assert_selector "##{target_id}:focus", wait: 5
      assert_equal target_id, page.evaluate_script("document.activeElement.id")
      assert_equal "solid", page.evaluate_script("getComputedStyle(arguments[0]).outlineStyle", find("##{target_id}"))
      within "##{target_id}" do
        assert_button "Record today's check-in"
      end
    end
  ensure
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
