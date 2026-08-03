require "test_helper"

class Agent::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get agent_profiles_path
    assert_redirected_to new_session_path
  end

  test "renders certified providers and separates setup states" do
    sign_in_as users(:two)
    get agent_profiles_path

    assert_response :success
    assert_select "h1", "Agents"
    assert_select "article", count: Agent::Profile::Certified.keys.size
    assert_select "dt", text: "Provider CLI"
    assert_select "dt", text: "ACP adapter"
    assert_select "dt", text: "Hearth profile"
    assert_select "p", text: /Conversation permissions are separate/
    assert_no_match(/usr\/local\/bin|TEST_AGENT_HOME|one@example.com/, response.body)
  end
end
