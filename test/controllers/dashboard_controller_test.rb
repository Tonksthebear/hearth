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

  test "authenticated root renders the current identity graph" do
    sign_in_as users(:one)

    get root_path

    assert_response :success
    assert_select "section[aria-labelledby='household-heading']" do
      assert_select "h1", households(:home).name
    end
    assert_select "section[aria-labelledby='current-person-heading']" do
      assert_select "h2", people(:one).name
      assert_select "h2", text: people(:two).name, count: 0
    end
  end

  test "authenticated root renders the selected person context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    get root_path

    assert_response :success
    assert_select "section[aria-labelledby='current-person-heading']" do
      assert_select "h2", people(:two).name
      assert_select "h2", text: people(:one).name, count: 0
    end
  end
end
