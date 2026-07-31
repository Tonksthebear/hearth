require "test_helper"

class NavigationRenderTest < ActionDispatch::IntegrationTest
  test "shared shell exposes exactly three primary destinations and relocates administration" do
    sign_in_as users(:one)

    get root_path

    assert_response :success
    assert_select "nav[aria-label='Household and person context']", count: 2 do |navigations|
      navigations.each do |navigation|
        assert_select navigation, "> ul > li:first-child a", count: 3
      end
    end
    assert_select "nav[aria-label='Household and person context'] a", text: "Today"
    assert_select "nav[aria-label='Household and person context'] a", text: "Meals"
    assert_select "nav[aria-label='Household and person context'] a", text: "Activities"
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
    assert_select "nav[aria-label='Meals'] a[href=?]", shopping_list_path

    get recovery_day_path
    assert_select "nav[aria-label='Household and person context'] a[aria-current='page']", text: "Activities"
    assert_select "nav[aria-label='Activities'] a[href=?]", exercises_path
  end
end
