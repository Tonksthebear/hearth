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
      assert_select "p", /#{people(:one).name}/
      assert_select "p", text: /#{people(:two).name}/, count: 0
    end
  end

  private
    def clear_installation
      Session.delete_all
      User.delete_all
      Person.delete_all
      Household.delete_all
    end
end
