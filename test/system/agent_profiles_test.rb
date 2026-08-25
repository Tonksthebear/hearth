require "application_system_test_case"

class AgentProfilesTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  test "signed in user explicitly approves authentication and can cancel queued work" do
    installation = agent_installations(:local)
    installation.update!(
      authentication_methods: [ { "id" => "fake-auth", "name" => "Fake authentication",
        "description" => "/private/credential-canary/token.json" } ].map { |method| method.slice("id", "name") },
      authentication_status: "required",
      authentication_method_id: nil,
      authentication_approved_at: nil,
      authentication_origin: nil
    )
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "browser-detection", origin: "web", status: "succeeded",
      cli_available: true, cli_version: "grok 1.0", adapter_available: true, adapter_version: "1.0")
    sign_in_via_browser users(:two)

    visit_and_wait_for_path agent_profiles_path
    assert_selector "h1", text: "Agents"
    assert_text "Connect an agent once"
    assert_no_text "credential-canary"
    within "#agent_provider_grok" do
      choose "Fake authentication"
      click_button "Finish connection"
    end
    assert_current_path agent_profiles_path
    assert_text "Agent setup request queued.", wait: 5
    request = Agent::SetupRequest.uncached { Agent::SetupRequest.order(:id).last }
    assert_equal "authenticate", request.action
    assert_equal "fake-auth", request.authentication_method_id
    assert_equal "pending", request.status

    within "#agent_provider_grok" do
      click_button "Cancel setup"
    end
    assert_text "Setup request cancelled.", wait: 5
    assert_equal "cancelled", request.reload.status
    assert_selector "#agent_provider_grok", text: "Setup cancelled"
  end

  test "a first connection can be cancelled while the runtime is offline" do
    agent_profiles(:hearth).update!(enabled: false)
    Agent::RuntimeStatus.where(household: households(:home)).delete_all
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      click_button "Connect"
    end

    assert_text "Agent setup request queued.", wait: 5
    request = Agent::SetupRequest.uncached { Agent::SetupRequest.order(:id).last }
    assert_equal "enable", request.action
    assert_equal "pending", request.status

    within "#agent_provider_grok" do
      assert_text "Setting up"
      assert_button "Cancel setup"
      click_button "Cancel setup"
    end

    assert_text "Setup request cancelled.", wait: 5
    assert_equal "cancelled", request.reload.status
    assert_selector "#agent_provider_grok", text: "Setup cancelled"
  end

  test "a pending authentication request hides duplicate authentication controls" do
    installation = agent_installations(:local)
    installation.update!(authentication_status: "required", authentication_method_id: nil,
      authentication_approved_at: nil, authentication_origin: nil)
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "authenticate", authentication_method_id: "cached_token",
      idempotency_key: "pending-authentication", origin: "web", status: "pending")
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      assert_text "Setting up"
      assert_button "Cancel setup"
      assert_no_selector "input[name='setup_request[authentication_method_id]']"
      assert_no_button "Finish connection"
    end
  end

  test "failed authentication shows the error and a reauthentication form" do
    installation = agent_installations(:local)
    installation.update!(authentication_status: "failed", authentication_method_id: nil,
      authentication_approved_at: nil, authentication_origin: nil)
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "authenticate", authentication_method_id: "cached_token",
      idempotency_key: "failed-authentication", origin: "web", status: "failed",
      error_category: "authentication_failed", error_message: "Provider authentication did not complete.")
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      assert_text "Needs attention"
      assert_selector "[role='alert']", text: "Provider authentication did not complete."
      assert_no_button "Try again"
      assert_selector "input[name='setup_request[authentication_method_id]']"
      assert_text "cached_token"
      assert_selector "input[name='setup_request[action]'][value='reauthenticate']", visible: :all
      assert_button "Finish connection"
    end
  end

  test "disconnect is confirmed and narrow cards do not overflow" do
    long_version = "version-#{"x" * 192}"
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "mobile-detection", origin: "web", status: "succeeded",
      cli_available: true, cli_version: long_version, adapter_available: true, adapter_version: long_version)
    sign_in_via_browser users(:two)
    original_size = page.current_window.size
    page.current_window.resize_to(390, 844)
    visit_and_wait_for_path agent_profiles_path

    within("#agent_provider_grok") { find("summary", text: "Connection details").click }
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
    dismiss_confirm do
      within("#agent_provider_grok") { click_button "Disconnect" }
    end
    assert_nil Agent::SetupRequest.find_by(action: "disable")
    accept_confirm do
      within("#agent_provider_grok") { click_button "Disconnect" }
    end
    assert_text "Agent setup request queued.", wait: 5
    assert_equal "pending", Agent::SetupRequest.uncached { Agent::SetupRequest.find_by!(action: "disable") }.status
  ensure
    page.current_window.resize_to(original_size[0], original_size[1]) if original_size
  end

  test "authenticated provider hides routine setup controls" do
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "reauth-detection", origin: "web", status: "succeeded",
      cli_available: true, adapter_available: true, adapter_version: "1.0")
    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime")
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      assert_text "Connected"
      assert_text "Available automatically while Hearth is running."
      assert_no_button "Re-check availability"
      assert_no_button "Re-authenticate"
      assert_no_selector "input[name='setup_request[authentication_method_id]']"
    end
  end

  test "runtime footer preserves its structure across supervised lifecycle states" do
    sign_in_via_browser users(:two)
    household = households(:home)
    footer = "#agent_provider_grok > div.bg-gray-50"
    offline_states = {
      "never_started" => "Hearth supervisor has not started ACP yet",
      "starting" => "Hearth supervisor is starting ACP",
      "recovering" => "Hearth supervisor is recovering ACP",
      "stopped" => "Hearth ACP runtime stopped",
      "failed" => "Hearth ACP runtime failed"
    }

    offline_states.each do |state, heading|
      Agent::RuntimeStatus.where(household: household).delete_all
      unless state == "never_started"
        persisted = state == "recovering" ? "online" : state
        heartbeat = state == "recovering" ? 1.minute.ago : Time.current
        Agent::RuntimeStatus.create!(household: household, owner: "runtime", status: persisted,
          started_at: 1.minute.ago, heartbeat_at: heartbeat,
          stopped_at: persisted.in?(%w[ stopped failed ]) ? Time.current : nil,
          failure_category: persisted == "failed" ? "runtime_error" : nil)
      end

      visit_and_wait_for_path agent_profiles_path
      within footer do
        assert_selector "div[role='status'] p", text: heading
        assert_selector "div[role='status'] p", count: 2
        assert_no_button "Queue availability check"
      end
    end

    Agent::RuntimeStatus.where(household: household).delete_all
    Agent::RuntimeStatus.create!(household: household, owner: "runtime", status: "online",
      started_at: Time.current, heartbeat_at: Time.current)
    visit_and_wait_for_path agent_profiles_path
    within footer do
      assert_selector "p", text: "Available automatically while Hearth is running."
      assert_no_selector "div[role='status']"
    end
  end

  test "runtime status transitions update an open Agent Settings page" do
    household = households(:home)
    Agent::RuntimeStatus.where(household: household).delete_all
    Agent::RuntimeStatus.start_all!(owner: "runtime")
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      assert_text "Hearth supervisor is starting ACP"
    end

    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime")

    within "#agent_provider_grok" do
      assert_text "Available automatically while Hearth is running.", wait: 5
      assert_no_text "Hearth supervisor is starting ACP"
    end
  end
end
