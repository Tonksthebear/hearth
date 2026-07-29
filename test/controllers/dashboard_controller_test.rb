require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "fresh anonymous root redirects to setup" do
    clear_installation

    get root_path

    assert_redirected_to new_setup_household_path
  end

  test "configured anonymous root redirects to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "authenticated root renders the selected household week and direct actions" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:one)

      get root_path(date: "2026-07-29")

      assert_response :success
      assert_select "h1", "Household week"
      assert_select "p", text: /July 27, 2026/
      assert_select "p", text: /August 02, 2026/
      assert_select "a[href=?]", root_path(date: "2026-07-20"), text: "Previous week"
      assert_select "a[href=?]", root_path(date: "2026-08-03"), text: "Next week"
      assert_select "a[href=?]", meal_week_path(date: "2026-07-27"), text: /Log a meal/
      assert_select "a[href=?]", shopping_list_path(date: "2026-07-27"), text: "Open shopping list"
      assert_select "a[href=?]", new_training_session_path(date: "2026-07-27"), text: "Log a workout"
      assert_select "a[href=?]", recovery_day_path, text: "Check in on habits"
      assert_select "p", text: /does not provide medical advice, diagnosis, or treatment/
      assert_select "#alert", count: 0
    end
  end

  test "authenticated root renders all plans once and isolates each person's activity" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:one)

      get root_path

      assert_response :success
      assert_select "#household-plans li", count: 4
      assert_select "#household-plans li", text: /#{Regexp.escape(recipes(:salad).title)}/, count: 2
      assert_select "#household-plans li", text: /#{Regexp.escape(recipes(:alex_only).title)}/, count: 1
      assert_select "#household-plans", text: /Alex/
      assert_select "#household-plans", text: /Sam/
      assert_select "#household-plans", text: /Whole household/

      assert_select "article[data-current-person='true']", count: 1 do
        assert_select "h3", people(:one).name
      end
      assert_select "article", text: /^#{Regexp.escape(people(:one).name)}/ do
        assert_select "li", text: /Dinner with friends/
        assert_select "li", text: /Sunday balanced day/
        assert_select "li", text: /Water/
        assert_select "li", text: /Sam workout/, count: 0
      end
      assert_select "article", text: /^#{Regexp.escape(people(:two).name)}/ do
        assert_select "li", text: /Sam workout/
        assert_select "li", text: /Post-meal movement/
        assert_select "li", text: /Dinner with friends/, count: 0
      end
      assert_select "article", text: /^#{Regexp.escape(people(:without_login).name)}/ do
        assert_select "p", text: "No meals logged this week."
        assert_select "p", text: "No training logged this week."
        assert_select "p", text: "No habits configured or recorded this week."
      end
    end
  end

  test "selected person emphasis changes without narrowing household plans" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:one)
      patch person_context_path, params: { person_id: people(:two).id }

      get root_path

      assert_response :success
      assert_select "article[data-current-person='true'] h3", people(:two).name
      assert_select "#household-plans li", count: 4
      assert_select "#household-plans", text: /#{Regexp.escape(recipes(:alex_only).title)}/
    end
  end
end
