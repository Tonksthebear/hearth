require "test_helper"

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

  private
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
        yield runtime
      ensure
        supervisor&.shutdown!
      end
    end
end
