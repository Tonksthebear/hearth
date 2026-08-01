require "test_helper"
require "timeout"

class Agent::Turn::RuntimeTest < ActiveSupport::TestCase
  FAKE_AGENT = Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s

  test "the sibling runtime claims dispatches and persists streamed output" do
    conversation = Agent::Conversation.create!(
      household: households(:home), person: people(:two), profile: agent_profiles(:hearth), title: "Runtime projection"
    )
    turn = conversation.enqueue_turn!(
      body: "Stream the response", browser_session: sessions(:browser), idempotency_key: "runtime-turn"
    )

    with_runtime do |runtime|
      processed = runtime.run_next

      assert_equal turn, processed
      assert_equal "succeeded", turn.reload.status, turn.error_message
      assert_predicate turn, :dispatched_at?
      assert_equal "HEARTH_ACP_OK", conversation.messages.where(role: "agent").sole.body
      assert_equal 1, conversation.sessions.count
    end
  end

  test "the runtime sends cancellation and records the terminal turn" do
    conversation = Agent::Conversation.create!(
      household: households(:home), person: people(:two), profile: agent_profiles(:hearth), title: "Runtime cancellation"
    )
    turn = conversation.enqueue_turn!(
      body: "Stop the response", browser_session: sessions(:browser), idempotency_key: "runtime-cancel"
    )

    with_runtime(mode: "cancel", stopping: -> { true }) do |runtime|
      runtime.run_next

      assert_equal "cancelled", turn.reload.status, turn.error_message
      assert_predicate turn, :cancel_requested_at?
      assert_predicate turn, :cancel_sent_at?
      assert_equal "started", conversation.messages.where(role: "agent").sole.body
    end
  end

  test "the runtime keeps supervisor housekeeping active while a prompt is running" do
    conversation = Agent::Conversation.create!(
      household: households(:home), person: people(:two), profile: agent_profiles(:hearth), title: "Runtime housekeeping"
    )
    turn = conversation.enqueue_turn!(
      body: "Keep ticking", browser_session: sessions(:browser), idempotency_key: "runtime-housekeeping"
    )

    with_runtime(mode: "cancel") do |runtime, supervisor|
      runner = Thread.new { runtime.run_next }
      wait_until { turn.reload.status == "running" }
      agent_profiles(:hearth).update!(enabled: false)
      runner.join(3)

      refute runner.alive?, "runtime did not observe supervisor housekeeping"
      assert_equal "disconnected", conversation.sessions.sole.reload.status
      assert_equal "failed", turn.reload.status
      assert_raises(Acp::Supervisor::Error) { supervisor.connection_for(conversation.sessions.sole) }
    ensure
      agent_profiles(:hearth).update!(enabled: true)
    end
  end

  test "the runtime surfaces bounded connection event loss" do
    conversation = Agent::Conversation.create!(
      household: households(:home), person: people(:two), profile: agent_profiles(:hearth), title: "Runtime overflow"
    )
    turn = conversation.enqueue_turn!(
      body: "Stream quickly", browser_session: sessions(:browser), idempotency_key: "runtime-overflow"
    )

    with_runtime(mode: "streaming") { |runtime| runtime.run_next }

    assert_equal "succeeded", turn.reload.status
    assert_operator turn.dropped_event_count, :>, 0
    assert_match(/updates were omitted/, turn.warning_message)
  end

  private
    def wait_until(timeout: 3)
      Timeout.timeout(timeout) do
        loop do
          return if yield

          sleep 0.02
        end
      end
    end

    def with_runtime(mode: "normal", stopping: -> { false })
      Dir.mktmpdir("hearth-turn-runtime") do |root|
        FileUtils.mkdir_p(File.join(root, ".hearth"))
        File.write(File.join(root, ".hearth/instance.yml"), "---\n")
        agent_profiles(:hearth).update!(
          executable_path: RbConfig.ruby,
          arguments: [ FAKE_AGENT ],
          environment_keys: []
        )
        factory = lambda do |**arguments|
          Acp::Connection.new(**arguments.merge(
            environment: arguments.fetch(:environment).merge("FAKE_ACP_MODE" => mode),
            timeout: 2,
            termination_grace: 0.2
          ))
        end
        supervisor = Acp::Supervisor.new(instance_root: root, connection_factory: factory).start!
        runtime = Agent::Turn::Runtime.new(supervisor: supervisor, owner: "test-runtime", stopping: stopping)
        yield runtime, supervisor
      ensure
        supervisor&.shutdown!
      end
    end
end
