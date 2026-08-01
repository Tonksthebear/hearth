require "application_system_test_case"
require "timeout"

class AgentConversationsLiveTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  FAKE_AGENT = Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s

  setup do
    skip "Run through bin/agent-chat-acceptance" unless ENV["HEARTH_CROSS_PROCESS_SYSTEM_TEST"] == "1"

    # rails/test_help installs the in-memory cable adapter around every test.
    # This suite intentionally exercises the configured cross-process adapter.
    ActionCable.server.instance_variable_set(:@pubsub, @old_pubsub_adapter)
    @instance_root = Dir.mktmpdir("hearth-live-chat-instance")
    FileUtils.mkdir_p(File.join(@instance_root, ".hearth"))
    File.write(File.join(@instance_root, ".hearth/instance.yml"), "---\n")
    @agent_info_file = File.join(@instance_root, "agent-info.json")
    @release_file = File.join(@instance_root, "release-permission")
    @runtime_log = File.join(@instance_root, "runtime.log")
    @runtime_pids = []
  end

  teardown do
    @runtime_pids&.each { |pid| stop_runtime(pid) }
    FileUtils.remove_entry(@instance_root) if @instance_root && File.exist?(@instance_root)
    Current.reset
    %w[
      FAKE_ACP_MODE FAKE_AGENT_INFO_FILE FAKE_SESSION_ID FAKE_PERMISSION_OPERATION
      FAKE_PERMISSION_INPUT FAKE_PERMISSION_RELEASE_FILE
    ].each { |name| ENV.delete(name) }
  end

  test "external runtime streams persisted projections through Solid Cable and reload" do
    sign_in_via_browser users(:two)
    configure_fake_agent("chat_stream")
    submit_browser_turn("Stream a production-shaped response")
    runtime_pid = start_runtime
    wait_for_runtime_turn
    wait_until { latest_turn&.terminal? }
    completed_turn = latest_turn
    assert_equal "succeeded", completed_turn.status, "runtime turn failed: #{completed_turn.error_message}\n#{File.read(@runtime_log)}"
    assert_equal "**Recorded fact:** streamed safely.", Agent::Message.uncached { Agent::Message.find_by!(external_id: "live-message").body }
    assert_operator SolidCable::Message.uncached { SolidCable::Message.count }, :>, 0

    assert_text "Recorded fact: streamed safely.", wait: 10
    assert_text "Review weekly records", wait: 10
    assert_text "Review the week", wait: 10
    assert_text "Hearth weekly record", wait: 10
    assert_text "Succeeded", wait: 10
    turn = latest_turn
    assert_equal 1, Agent::Turn.uncached { Agent::Turn.where(idempotency_key: turn.idempotency_key).count }

    refresh
    assert_text "Recorded fact: streamed safely.", wait: 5
    assert_text "Hearth Fact"
    assert_agent_is_child_of_runtime(runtime_pid)
  end

  test "browser approval resolves an external runtime database wait without pubsub authority" do
    sign_in_via_browser users(:two)
    browser_session = users(:two).sessions.order(:created_at).last
    configure_fake_agent("permission_allow", {
      "FAKE_SESSION_ID" => "live-permission-session",
      "FAKE_PERMISSION_OPERATION" => "delete_meal",
      "FAKE_PERMISSION_INPUT" => JSON.generate(id: meals(:sam_recipe_target_week).id, idempotency_key: "live-permission"),
      "FAKE_PERMISSION_RELEASE_FILE" => @release_file
    })
    meal = meals(:sam_recipe_target_week)
    arguments = { id: meal.id }
    submit_browser_turn("Apply the approved change")
    runtime_pid = start_runtime
    wait_for_runtime_turn
    wait_until { latest_turn&.status.in?(%w[ running failed cancelled ]) }
    turn = latest_turn
    assert_equal "running", turn.status, "runtime did not reach permission wait: #{turn.error_message}\n#{File.read(@runtime_log)}"
    session = turn.agent_session
    click_link_and_wait_for_path "Today", root_path
    connect_turbo_cable_stream_sources
    Current.session = browser_session
    Current.household = households(:home)
    Current.person = people(:two)
    Agent::OperationalAuthorization.authorize!(
      agent_session: session,
      reason: "Enabled for the live approval acceptance path"
    )
    grant = Agent::Grant.issue!(
      conversation: session.conversation,
      agent_session: session,
      capability_groups: [ "health_write" ],
      expires_at: 1.minute.from_now
    ).grant
    proposal, = Agent::MutationProposal.propose!(
      grant: grant,
      capability: "health.write",
      operation: "delete_meal",
      arguments: arguments,
      preview: Agent::Mutation::Operations.preview(operation: "delete_meal", arguments: arguments, context: grant),
      expected_state: Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: arguments, proposal: grant),
      idempotency_key: "live-permission",
      deadline_at: 1.minute.from_now
    )
    FileUtils.touch(@release_file)
    connect_turbo_cable_stream_sources
    proposal.broadcast_confirmation(proposal.confirmation_token)
    assert_text "Confirm agent operation", wait: 10
    click_button "Approve once"

    assert_no_text "Confirm agent operation", wait: 10
    wait_until { latest_turn&.terminal? }
    assert_equal "succeeded", latest_turn.status
    assert_equal "executed", Agent::MutationProposal.uncached { Agent::MutationProposal.find(proposal.id).status }
    assert_not Agent::MutationProposal.uncached { Meal.exists?(meal.id) }
    assert_agent_is_child_of_runtime(runtime_pid)
  end

  test "reload reconstructs a running turn and browser cancellation reaches the runtime" do
    sign_in_via_browser users(:two)
    configure_fake_agent("cancel")
    submit_browser_turn("Cancel this production-shaped response")
    runtime_pid = start_runtime
    wait_for_runtime_turn
    wait_until do
      latest_turn&.status == "running" && Agent::Message.uncached { Agent::Message.where(body: "started").exists? }
    end

    refresh
    assert_text "started", wait: 5
    assert_selector "#agent_turn_status", text: "Running"
    connect_turbo_cable_stream_sources
    expect_turbo_load
    accept_confirm("Stop this coach response?") { click_button "Cancel" }
    wait_for_turbo_load

    wait_until { latest_turn&.terminal? }
    refresh
    assert_selector "#agent_turn_status", text: "Cancelled", wait: 5
    assert_predicate latest_turn, :cancel_sent_at?
    assert_equal 1, Agent::Turn.uncached { Agent::Turn.where(idempotency_key: latest_turn.idempotency_key).count }
    assert_agent_is_child_of_runtime(runtime_pid)
  end

  test "runtime crash becomes a persisted useful browser error" do
    sign_in_via_browser users(:two)
    configure_fake_agent("crash_prompt")
    submit_browser_turn("Surface a failed runtime")
    runtime_pid = start_runtime
    wait_for_runtime_turn
    wait_until { latest_turn&.terminal? }

    assert_equal "failed", latest_turn.status
    assert_selector "#agent_turn_status", text: "Failed", wait: 10
    assert_selector "#agent_turn_status .sr-only", text: /Error:/
    refresh
    assert_selector "#agent_turn_status", text: "Failed"
    assert_agent_is_child_of_runtime(runtime_pid)
  end

  private
    def submit_browser_turn(body)
      visit_and_wait_for_path agent_conversation_path(agent_conversations(:active))
      fill_in_and_wait_for_value "Message the coach", body
      expect_turbo_load
      click_button "Send"
      wait_for_turbo_load
      assert_selector "#agent_messages > li", count: 2, wait: 5
      assert_selector "#agent_turn_status", text: "Pending", wait: 5
      assert_field "Message the coach", with: "", wait: 5
      connect_turbo_cable_stream_sources
    end

    def expect_turbo_load
      page.execute_script(<<~JAVASCRIPT)
        window.__hearthTurnNavigationComplete = false
        document.addEventListener("turbo:load", () => {
          window.__hearthTurnNavigationComplete = true
        }, { once: true })
      JAVASCRIPT
    end

    def wait_for_turbo_load
      wait_until { page.evaluate_script("window.__hearthTurnNavigationComplete === true") }
    end

    def configure_fake_agent(mode, environment = {})
      values = {
        "FAKE_ACP_MODE" => mode,
        "FAKE_AGENT_INFO_FILE" => @agent_info_file
      }.merge(environment)
      values.each { |name, value| ENV[name] = value }
      agent_profiles(:hearth).update!(
        executable_path: RbConfig.ruby,
        arguments: [ FAKE_AGENT ],
        environment_keys: values.keys
      )
      agent_installations(:local).update!(
        external_id: "fake-agent",
        executable_path: RbConfig.ruby,
        agent_version: "1.0.0"
      )
    end

    def start_runtime
      pid = spawn(
        ENV.to_h,
        Rails.root.join("bin/hearth-acp-runtime").to_s,
        "--root", @instance_root,
        "--once",
        "--evidence", @runtime_log,
        out: @runtime_log,
        err: [ @runtime_log, "a" ]
      )
      @runtime_pids << pid
      pid
    end

    def stop_runtime(pid)
      Process.kill("TERM", pid)
      Timeout.timeout(5) { Process.wait(pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      Process.kill("KILL", pid) rescue nil
      Process.wait(pid) rescue nil
    end

    def assert_agent_is_child_of_runtime(runtime_pid)
      wait_until { File.exist?(@agent_info_file) }
      info = JSON.parse(File.read(@agent_info_file))
      assert_equal runtime_pid, info.fetch("ppid")
      assert_not_equal Process.pid, info.fetch("ppid"), "Puma/test process directly parented the ACP agent"
    end

    def wait_for_runtime_turn
      wait_until do
        turn = latest_turn
        (turn && turn.status != "pending") || @runtime_pids.any? { |pid| Process.waitpid(pid, Process::WNOHANG) }
      end
      turn = latest_turn
      assert turn, "browser did not persist a turn or runtime exited early:\n#{File.read(@runtime_log)}"
      assert_not_equal "pending", turn.status, "runtime did not claim the turn:\n#{File.read(@runtime_log)}"
    end

    def latest_turn
      Agent::Turn.uncached { Agent::Turn.order(:id).last }
    end

    def wait_until(timeout: 10)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until yield
        flunk "condition did not become true" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.05
      end
    end
end
