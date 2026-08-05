require "test_helper"

class HouseholdWeeksControllerTest < ActionDispatch::IntegrationTest
  test "authenticated root renders the selected household week and direct actions" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:one)

      get household_week_path(date: "2026-07-29")

      assert_response :success
      assert_select "h1", "Household week"
      assert_select "p", text: /July 27, 2026/
      assert_select "p", text: /August 02, 2026/
      assert_select "a[href=?]", household_week_path(date: "2026-07-20"), text: "Previous week"
      assert_select "a[href=?]", household_week_path(date: "2026-08-03"), text: "Next week"
      assert_select "a[href=?]", meal_week_path(date: "2026-07-27"), text: /Log a meal/
      assert_select "a[href=?][data-turbo-prefetch='false']", shopping_list_path(date: "2026-07-27"), text: "Open shopping list"
      assert_select "a[href=?]", new_training_session_path(date: "2026-07-27"), text: "Log a workout"
      assert_select "a[href=?]", recovery_day_path, text: "Check in on habits"
      assert_select "p", text: /does not provide medical advice, diagnosis, or treatment/

      get new_setup_household_path
      assert_redirected_to root_path
      follow_redirect!
      assert_select "#alert", text: "Household setup is already complete.", count: 1
    end
  end

  test "authenticated root renders all plans once and isolates each person's activity" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:one)

      get household_week_path

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

  test "signed-in person emphasis changes without narrowing household plans" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:two)

      get household_week_path

      assert_response :success
      assert_select "article[data-current-person='true'] h3", people(:two).name
      assert_select "#household-plans li", count: 4
      assert_select "#household-plans", text: /#{Regexp.escape(recipes(:alex_only).title)}/
    end
  end

  test "non-current and empty weeks render their dated action and empty plan state" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_as users(:one)

      get household_week_path(date: "2026-08-12")

      assert_response :success
      assert_select "a[href=?]", new_training_session_path(date: "2026-08-10"), text: "Log a workout"
      assert_select "#household-plans li", count: 0
      assert_select "p", text: "Nothing planned for this week."
    end
  end
end
