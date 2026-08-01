require "test_helper"
require "rbconfig"
require "tmpdir"

class Agent::Profile::CertifiedTest < ActiveSupport::TestCase
  test "detects provider cli separately from its ACP adapter" do
    Dir.mktmpdir("certified-profile-path") do |directory|
      executable = File.join(directory, "codex")
      File.write(executable, "#!/bin/sh\necho 'codex-cli 9.9.9'\n")
      File.chmod(0o700, executable)
      original_path = ENV["PATH"]
      ENV["PATH"] = directory

      detection = Agent::Profile::Certified.fetch("codex").detection

      assert_equal executable, detection[:cli]
      assert_equal "codex-cli 9.9.9", detection[:cli_version]
      assert_nil detection[:acp_executable]
      assert_equal false, detection[:acp_available]
    ensure
      ENV["PATH"] = original_path
    end
  end

  test "certified definitions use exact argv and environment name allowlists" do
    definitions = Agent::Profile::Certified.all.map(&:definition)

    assert_equal %w[grok codex claude], definitions.map(&:key)
    definitions.each do |definition|
      assert_kind_of Array, definition.arguments
      assert definition.arguments.all? { |argument| argument.is_a?(String) }
      assert definition.environment_keys.all? { |key| key.match?(/\A[A-Z][A-Z0-9_]*\z/) }
    end
    assert_equal "grok", definitions.first.adapter_command
    assert_equal %w[--no-auto-update agent stdio], definitions.first.arguments
    assert_equal "codex-acp", definitions.second.adapter_command
    assert_equal "claude-agent-acp", definitions.third.adapter_command
  end

  test "operator approved installation identity is reused by the production supervisor" do
    definition = Agent::Profile::Certified::Definition.new(
      key: "fake",
      name: "Fake certified agent",
      cli_command: RbConfig.ruby,
      adapter_command: RbConfig.ruby,
      arguments: [ Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s ],
      environment_keys: %w[FAKE_ACP_MODE FAKE_AUTH_LOG],
      credential_store: "the fake test store"
    )
    candidate = Agent::Profile::Certified.new(definition)
    original_mode = ENV["FAKE_ACP_MODE"]
    original_log = ENV["FAKE_AUTH_LOG"]

    Dir.mktmpdir("certified-auth") do |root|
      instance = Hearth::Instance.new(root).initialize!
      auth_log = File.join(root, "auth.log")
      ENV["FAKE_ACP_MODE"] = "sole_auth"
      ENV["FAKE_AUTH_LOG"] = auth_log
      household = households(:home)

      candidate.with_probe(instance: instance) do |probe|
        installation = candidate.persist_authentication!(
          household: household,
          probe: probe,
          method_id: "fake-auth"
        )
        assert_equal %w[authenticate], File.readlines(auth_log, chomp: true)
        conversation = installation.profile.conversations.create!(
          household: household,
          person: people(:two),
          title: "Certified identity proof"
        )
        supervisor = Acp::Supervisor.new(instance_root: root).start!

        session = supervisor.start_session(conversation: conversation)

        assert_equal installation.id, session.installation_id
        assert_equal "profile-#{installation.profile_id}", installation.external_id
        assert_equal "connected", session.status
        assert_equal %w[authenticate authenticate], File.readlines(auth_log, chomp: true)
      ensure
        supervisor&.shutdown!
      end
    end
  ensure
    ENV["FAKE_ACP_MODE"] = original_mode
    ENV["FAKE_AUTH_LOG"] = original_log
  end
end
