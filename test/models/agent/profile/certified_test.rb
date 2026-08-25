require "test_helper"
require "pty"
require "rbconfig"
require "shellwords"
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
    assert_equal %w[HOME PATH XDG_CONFIG_HOME XAI_API_KEY], definitions.first.environment_keys
    assert_equal "codex-acp", definitions.second.adapter_command
    assert_equal "claude-agent-acp", definitions.third.adapter_command
  end

  test "real Grok acceptance environment is fixed and cannot become generic runtime configuration" do
    environment = Agent::Profile::Certified::GROK_ACCEPTANCE_ENVIRONMENT

    assert_equal "0", environment.fetch("GROK_CLAUDE_AGENTS_ENABLED")
    assert_raises(ArgumentError) do
      Agent::Profile::Certified.validate_acceptance_environment("ARBITRARY_SECRET" => "value")
    end
  end

  test "runtime copy is defined for the online state" do
    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime")

    state = Agent::Profile::Certified.fetch("grok").state_for(households(:home))
    assert_equal "online", state.runtime_state
    assert_equal "Sibling ACP runtime online", state.runtime_heading
  end

  test "an authenticated enabled profile is a persistent connection" do
    state = Agent::Profile::Certified.fetch("grok").state_for(households(:home))

    assert_predicate state, :configured?
    assert_not_predicate state, :authentication_required?
    assert_equal :connected, state.connection_state
    assert_equal "Connected", state.connection_status
  end

  test "failed and expired setup requests need attention before authentication" do
    installation = agent_installations(:local)
    installation.update!(authentication_status: "failed")

    %w[ failed expired ].each do |status|
      Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
        action: "authenticate", authentication_method_id: "cached_token",
        idempotency_key: "#{status}-status", origin: "web", status: status,
        error_category: "authentication_failed", error_message: "Provider authentication did not complete.")

      state = Agent::Profile::Certified.fetch("grok").state_for(households(:home))

      assert_predicate state, :setup_failed?
      assert_equal :failed, state.connection_state
      assert_equal "Needs attention", state.connection_status
    end
  end

  test "a cancelled setup request has an explicit connection status" do
    agent_profiles(:hearth).update!(enabled: false)
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "enable", idempotency_key: "cancelled-status", origin: "web", status: "cancelled")

    state = Agent::Profile::Certified.fetch("grok").state_for(households(:home))

    assert_predicate state, :setup_cancelled?
    assert_equal :cancelled, state.connection_state
    assert_equal "Setup cancelled", state.connection_status
  end

  test "connection details keep the latest successful adapter detection" do
    successful = Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "enable", idempotency_key: "successful-adapter-detection", origin: "web", status: "succeeded",
      cli_available: true, cli_version: "grok 1.0", adapter_available: true, adapter_version: "1.0")
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "missing-adapter-detection", origin: "web", status: "succeeded",
      cli_available: true, cli_version: "grok 1.1", adapter_available: false)

    state = Agent::Profile::Certified.fetch("grok").state_for(households(:home))

    assert_equal successful, state.detection
    assert_predicate state.detection, :adapter_available?
  end

  test "legacy named profile is projected and claimed under its certified identity" do
    profile = agent_profiles(:hearth)
    profile.update!(certified_key: nil, name: "Grok Build")
    candidate = Agent::Profile::Certified.fetch("grok")
    connection = Object.new
    connection.define_singleton_method(:auth_methods) { [] }
    connection.define_singleton_method(:agent_capabilities) { {} }
    connection.define_singleton_method(:agent_info) { { "version" => "legacy 1.0" } }
    probe = Agent::Profile::Certified::Probe.new(
      definition: candidate.definition,
      executable_path: "/usr/bin/grok",
      cli_path: "/usr/bin/grok",
      version: "legacy 1.0",
      initialized: { "protocolVersion" => 1 },
      connection: connection
    )

    assert_equal profile, candidate.state_for(households(:home)).profile

    installation = candidate.observe_probe!(household: households(:home), probe: probe)

    assert_equal "grok", profile.reload.certified_key
    assert_equal profile, installation.profile
  end

  test "operator approved installation identity is reused by the production supervisor" do
    definition = Agent::Profile::Certified::Definition.new(
      key: "fake",
      name: "Fake certified agent",
      cli_command: RbConfig.ruby,
      adapter_command: RbConfig.ruby,
      arguments: [ Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s ],
      environment_keys: %w[FAKE_ACP_MODE FAKE_AUTH_LOG],
      credential_store: "the fake test store",
      guidance_url: "https://example.test/fake-agent"
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
        installation = candidate.authenticate_probe!(
          household: household,
          probe: probe,
          method_id: "fake-auth",
          origin: "operator_command"
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

  test "operator setup excludes provider credential paths at every persistence boundary" do
    canary = "/private/var/hearth-credential-canary/provider-token.json"
    fake_agent = Rails.root.join("test/fixtures/files/acp/fake_agent.rb")

    Dir.mktmpdir("certified-auth-path") do |workspace|
      root = File.join(workspace, "instance")
      bin = File.join(workspace, "bin")
      auth_log = File.join(workspace, "auth.log")
      FileUtils.mkdir_p([ root, bin ])
      wrapper = File.join(bin, "grok")
      File.write(wrapper, <<~SH)
        #!/bin/sh
        exec env FAKE_ACP_MODE=credential_path_auth FAKE_AUTH_LOG=#{auth_log.shellescape} \
          #{RbConfig.ruby.shellescape} #{fake_agent.to_s.shellescape} "$@"
      SH
      File.chmod(0o700, wrapper)
      environment = {
        "PATH" => [ bin, ENV.fetch("PATH") ].join(File::PATH_SEPARATOR),
        "HEARTH_DEMO_PASSWORD" => "credential-path-test-password"
      }
      _init_output, init_error, init_status = Open3.capture3(
        environment,
        RbConfig.ruby,
        Rails.root.join("bin/hearth").to_s,
        "init", "--demo", "--root", root
      )
      assert_predicate init_status, :success?, init_error

      output, setup_status = run_setup_in_terminal(environment, root)

      assert_predicate setup_status, :success?, output
      assert_includes output, "1. Fake authentication"
      refute_includes output, canary
      assert_equal %w[authenticate], File.readlines(auth_log, chomp: true)

      instance = Hearth::Instance.new(root)
      database = SQLite3::Database.new(instance.database_paths.fetch("DATABASE_URL").to_s)
      methods = JSON.parse(database.get_first_value("SELECT authentication_methods FROM agent_installations"))
      assert_equal [ { "id" => "fake-auth", "name" => "Fake authentication" } ], methods
      refute_includes database.execute("SELECT * FROM agent_installations").flatten.map(&:to_s).join, canary
      database.close

      snapshot = Dir.glob(instance.hearth_root.join("**/*").to_s, File::FNM_DOTMATCH)
        .select { |path| File.file?(path) }
        .map { |path| File.binread(path) }
        .join
      refute_includes snapshot, canary
      refute_includes Rails.root.join("docs/acp-evidence/certification.jsonl").binread, canary
    end
  end

  private
    def run_setup_in_terminal(environment, root)
      output = +""
      status = nil
      PTY.spawn(
        environment,
        RbConfig.ruby,
        Rails.root.join("bin/hearth").to_s,
        "agent", "setup", "--profile", "grok", "--root", root
      ) do |reader, writer, pid|
        writer.write("y\n1\n")
        writer.close
        output << reader.read
        _, status = Process.wait2(pid)
      rescue Errno::EIO
        _, status = Process.wait2(pid) unless status
      end
      [ output, status ]
    end
end
