require "test_helper"

class NavigationRenderTest < ActionDispatch::IntegrationTest
  test "shared shell exposes the four primary destinations and relocates administration" do
    sign_in_as users(:one)

    get root_path

    assert_response :success
    assert_select "nav[aria-label='Household and person context']", count: 2 do |navigations|
      navigations.each do |navigation|
        assert_select navigation, "> ul > li:first-child a", count: 4
      end
    end
    assert_select "nav[aria-label='Household and person context'] a", text: "Today"
    assert_select "nav[aria-label='Household and person context'] a", text: "Meals"
    assert_select "nav[aria-label='Household and person context'] a", text: "Activities"
    assert_select "nav[aria-label='Household and person context'] a", text: "Coach"
    %w[Manage\ people Recipes Shopping Exercises Workout\ templates Recovery].each do |label|
      assert_select "nav[aria-label='Household and person context'] a", text: label, count: 0
    end
    assert_select "section[aria-labelledby='person-context-heading']", text: /Manage people/
    assert_select "section[aria-labelledby='person-context-heading']", text: /Manage recipes/
    assert_select "section[aria-labelledby='person-context-heading']", text: /Workout templates/
    assert_select "section[aria-labelledby='person-context-heading']", text: /Exercises/
    assert_select "section[aria-labelledby='person-context-heading']", text: /Habits/
  end

  test "nested destinations mark their primary area and render route subnavigation" do
    sign_in_as users(:one)

    get recipe_path(recipes(:porridge))
    assert_select "nav[aria-label='Household and person context'] a[aria-current='page']", text: "Meals"
    assert_select "nav[aria-label='Meals'] a[href=?][data-turbo-prefetch='false']", shopping_list_path
    assert_select "nav[aria-label='Meals'] > div[class=?]",
      ApplicationController.helpers.yass(nav_tabs: :list)
    assert_select "nav[aria-label='Meals'] a[class=?]",
      ApplicationController.helpers.yass(nav_tabs: :tab),
      minimum: 1

    get recovery_day_path
    assert_select "nav[aria-label='Household and person context'] a[aria-current='page']", text: "Activities"
    assert_select "nav[aria-label='Activities'] a[href=?]", activity_week_path
    assert_select "nav[aria-label='Activities'] a[href=?]", activity_library_path
    assert_select "nav[aria-label='Activities'] a[href=?]", activity_history_path
    assert_select "nav[aria-label='Activities'] a", text: "Overview", count: 0
  end


  test "every rendered shopping link opts out of Turbo prefetch" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)
      list = ShoppingList.for(household: households(:home), date: "2026-07-27")
      item = list.items.first

      [
        root_path,
        recipe_path(recipes(:porridge)),
        meal_week_path(date: "2026-07-27"),
        household_week_path(date: "2026-07-27"),
        shopping_list_path(date: "2026-07-27"),
        edit_shopping_list_item_path(item, date: "2026-07-27")
      ].each do |path|
        get path
        assert_response :success
        assert_select "a[href*='shopping_list']" do |links|
          assert links.all? { |link| link["data-turbo-prefetch"] == "false" }, "Expected every Shopping link on #{path} to disable prefetch"
        end
      end
    end
  end

  test "every Activities destination marks the primary tab and the correct secondary tab" do
    sign_in_as users(:one)

    {
      activity_week_path => "Week",
      training_week_path => "Week",
      activity_library_path => "Library",
      activity_history_path => "History"
    }.each do |path, secondary_label|
      get path

      assert_response :success
      assert_select "nav[aria-label='Household and person context'] a[aria-current='page']", text: "Activities"
      assert_select "nav[aria-label='Activities'] a[aria-current='page']", text: secondary_label
    end
  end

  test "administrative pages do not falsely mark a primary destination current" do
    sign_in_as users(:one)

    get person_path(people(:one))

    assert_response :success
    assert_select "nav[aria-label='Household and person context'] a[aria-current='page']", count: 0
  end

  test "form pages retain their prepared route subnavigation" do
    sign_in_as users(:one)

    get new_training_session_path

    assert_response :success
    assert_select "nav[aria-label='Activities'] a[aria-current='page']", text: "Week"

    get new_recipe_path

    assert_response :success
    assert_select "nav[aria-label='Meals'] a[aria-current='page']", text: "Recipes"
  end
end
