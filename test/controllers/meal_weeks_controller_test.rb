require "test_helper"

class MealWeeksControllerTest < ActionDispatch::IntegrationTest
  test "renders the selected person's planned and eaten week" do
    sign_in_as users(:one)

    get meal_week_path, params: { date: "2026-07-27" }

    assert_response :success
    assert_select "h1", text: "Meals"
    assert_select "section[aria-labelledby='day-2026-07-27'] > div > div:first-child li",
      text: /#{Regexp.escape(recipes(:salad).title)}/
    assert_select "section[aria-labelledby='day-2026-07-28'] > div > div:first-child li",
      text: /#{Regexp.escape(recipes(:alex_only).title)}/
    assert_select "section[aria-labelledby='day-2026-07-28'] > div > div:nth-child(2) li",
      text: /Dinner with friends/
    assert_select "section[aria-labelledby='day-2026-07-29'] li p",
      text: people(:two).name,
      count: 0
    assert_select "form[action='#{planned_meals_path}']"
    assert_select "a[href^='#{new_meal_path}?date=']", text: "Log meal"
    assert_select "section[aria-labelledby='log-meal-heading'] form", count: 0
  end

  test "invalid date inputs safely render the current week" do
    sign_in_as users(:one)

    travel_to Date.new(2026, 7, 27) do
      [ "not-a-date", "2026-02-31" ].each do |date|
        get meal_week_path, params: { date: date }

        assert_response :success
        assert_select "p", text: /July 27, 2026/
        assert_select "h2", text: "July 27, 2026"
      end
    end
  end
end
