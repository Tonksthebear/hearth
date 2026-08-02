require "application_system_test_case"

class AgentGrokLiveTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  test "real Grok is enabled authenticated and completes one read only Coach turn" do
    skip "Set HEARTH_REAL_GROK_SYSTEM_TEST=1 to run the isolated real-provider seam" unless
      ENV["HEARTH_REAL_GROK_SYSTEM_TEST"] == "1"

    base_url = ENV.fetch("HEARTH_REAL_GROK_BASE_URL")
    Capybara.app_host = base_url
    Capybara.run_server = false
    visit "/session/new"
    fill_in "Email address", with: "demo@hearth.local"
    fill_in "Password", with: ENV.fetch("HEARTH_DEMO_PASSWORD")
    click_button "Sign in"
    assert_text "Today", wait: 10

    visit "/agent/profiles"
    within "#agent_provider_grok" do
      click_button "Re-check availability"
      assert_text "Available", wait: 30
      click_button "Enable"
      assert_text "Choose and approve an authentication method", wait: 30
      first("input[name='setup_request[authentication_method_id]']", visible: :all).choose
      click_button "Approve authentication"
      assert_text "Authentication: authenticated", wait: 45
    end

    visit "/agent/conversations/new"
    select "Grok Build", from: "Agent"
    fill_in "Conversation title", with: "Read-only acceptance"
    click_button "Create conversation"
    fill_in "Message the coach", with: "Using only Hearth read tools and synthetic data, reply with HEARTH_GROK_READ_ONLY_OK and do not write, submit, or request operational access."
    click_button "Send"
    assert_selector "#agent_turn_status", text: "Succeeded", wait: 90
    within("#agent_messages > li", text: "Grok Build", wait: 10) do
      assert_text "HEARTH_GROK_READ_ONLY_OK"
    end
    assert_no_text(/credential|oauth code|bearer|\/Users\//i)
  ensure
    Capybara.app_host = nil
    Capybara.run_server = true
  end
end
