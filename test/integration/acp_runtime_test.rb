require "test_helper"
require "json"
require "net/http"
require "open3"
require "rbconfig"
require "securerandom"
require "socket"
require "tmpdir"

class AcpRuntimeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  RUNTIME = Rails.root.join("bin/hearth-acp-runtime").to_s
  FAKE_AGENT = Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s
  PROCESS_START_TIMEOUT = 20

  def before_setup
    @runtime_test_lock = File.open(
      Rails.root.join("tmp/acp-runtime-integration.lock"),
      File::RDWR | File::CREAT,
      0o600
    )
    @runtime_test_lock.flock(File::LOCK_EX)
    super
  rescue
    release_runtime_test_lock
    raise
  end

  def after_teardown
    super
  ensure
    release_runtime_test_lock
  end

  test "uninitialized root fails before Rails boot and writes nothing" do
    Dir.mktmpdir("hearth-uninitialized-runtime") do |root|
      stdout, stderr, status = Open3.capture3(
        {
          "RAILS_ENV" => "environment-that-must-not-boot"
        },
        RbConfig.ruby,
        RUNTIME,
        "--root",
        root,
        "--once",
        chdir: root
      )

      assert_not status.success?
      assert_empty stdout
      assert_match(/Hearth instance is not initialized/, stderr)
      assert_empty Dir.children(root)
    end
  end

  test "sibling runtime claims web setup and persists only advertised method identity" do
    with_instance_root do |root|
      executable_directory = File.join(root, "bin")
      FileUtils.mkdir_p(executable_directory)
      fake_grok = File.join(executable_directory, "grok")
      File.write(fake_grok, <<~RUBY)
        #!/usr/bin/env ruby
        ENV["FAKE_ACP_MODE"] = "credential_path_auth"
        load #{FAKE_AGENT.inspect}
      RUBY
      FileUtils.chmod(0o700, fake_grok)
      environment = {
        "PATH" => "#{executable_directory}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}"
      }
      profile = agent_profiles(:hearth)
      profile.update!(enabled: false)
      enable_request = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
        certified_key: "grok", action: "enable", idempotency_key: "runtime-web-enable")

      enable_runtime = start_runtime(root, environment: environment)
      enable_result = enable_runtime.wait

      assert_predicate enable_result.fetch(:status), :success?, enable_result.fetch(:stderr)
      assert_equal "succeeded", enable_request.reload.status
      installation = Agent::Installation.uncached { Agent::Installation.where(profile: profile).order(:id).last }
      assert_equal [ { "id" => "fake-auth", "name" => "Fake authentication" } ], installation.authentication_methods
      assert_no_match(/hearth-credential-canary|provider-token/, installation.attributes.to_json)
      assert_equal "required", installation.authentication_status

      authenticate_request = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
        certified_key: "grok", action: "authenticate", authentication_method_id: "fake-auth",
        idempotency_key: "runtime-web-authenticate")
      authenticate_runtime = start_runtime(root, environment: environment)
      authenticate_result = authenticate_runtime.wait

      assert_predicate authenticate_result.fetch(:status), :success?, authenticate_result.fetch(:stderr)
      assert_equal "succeeded", authenticate_request.reload.status
      assert_equal "authenticated", installation.reload.authentication_status
      assert_equal "web_setting", installation.authentication_origin
    ensure
      authenticate_runtime&.stop
      enable_runtime&.stop
    end
  end

  test "production runtime remains agent parent across an unconditional Puma stop and restart" do
    with_instance_root do |root|
      configure_runtime_profile
      port = available_port
      puma = start_puma(root, port)
      wait_for_http(port, process: puma)

      release = File.join(root, "release")
      info_file = File.join(root, "agent-info.json")
      evidence = File.join(root, "runtime-evidence.jsonl")
      runtime = start_runtime(
        root,
        "--conversation", agent_conversations(:active).id.to_s,
        "--hold-until", release,
        "--prompt", "boundary",
        "--evidence", evidence,
        environment: {
          "FAKE_ACP_MODE" => "streaming",
          "FAKE_SESSION_ID" => "puma-boundary-#{SecureRandom.hex(6)}",
          "FAKE_AGENT_INFO_FILE" => info_file
        }
      )
      agent_info = wait_for_json(info_file, process: runtime)

      assert_equal runtime.pid, agent_info.fetch("ppid")
      refute_equal puma.pid, agent_info.fetch("ppid")

      puma.stop
      puma = start_puma(root, port)
      wait_for_http(port, process: puma)
      File.write(release, "continue\n")
      runtime_result = runtime.wait

      assert_predicate runtime_result.fetch(:status), :success?, runtime_result.fetch(:stderr)
      assert_process_gone(agent_info.fetch("pid"))
      row = JSON.parse(File.readlines(evidence).last)
      assert_equal "ACP runtime and sanitized MCP configuration", row["proof_scope"]
      assert_equal [ { "name" => "Hearth", "transport" => "http", "authenticated" => true } ], row["mcp_servers"]
      assert_equal "end_turn", row["stop_reason"]
      assert_equal 300, row["update_count"]
      assert_equal Acp::Connection::DEFAULT_QUEUE_SIZE, row["retained_update_count"]
      assert_equal 300 - Acp::Connection::DEFAULT_QUEUE_SIZE, row["dropped_update_count"]
    ensure
      runtime&.stop
      puma&.stop
    end
  end

  test "standalone runtime correlates a staged MCP proposal and recovers read-only after execution" do
    with_instance_root do |root|
      configure_runtime_profile
      port = available_port
      puma = start_puma(root, port)
      wait_for_http(port, process: puma)
      release = File.join(root, "guarded-release")
      evidence = File.join(root, "guarded-runtime-evidence.jsonl")
      external_session_id = "guarded-runtime-#{SecureRandom.hex(6)}"
      meal = meals(:sam_recipe_target_week)
      idempotency_key = "runtime-delete-meal"
      runtime = start_runtime(
        root,
        "--conversation", agent_conversations(:active).id.to_s,
        "--hold-until", release,
        "--prompt", "request staged permission",
        "--evidence", evidence,
        environment: {
          "FAKE_ACP_MODE" => "permission_allow",
          "FAKE_SESSION_ID" => external_session_id,
          "FAKE_PERMISSION_OPERATION" => "delete_meal",
          "FAKE_PERMISSION_INPUT" => JSON.generate(id: meal.id, idempotency_key: idempotency_key)
        }
      )
      agent_session = nil
      wait_until(timeout: 10) do
        flunk "runtime exited before binding the ACP session: #{runtime.stderr}" unless runtime.alive?
        agent_session = Agent::Session.uncached do
          Agent::Session.find_by(external_session_id: external_session_id)
        end
      end

      Current.session = sessions(:browser)
      Current.household = households(:home)
      Current.person = people(:two)
      # The standalone process has no Rack session; attach the already-authenticated
      # browser context that would normally launch it before enabling writes.
      agent_session.update_columns(browser_session_id: Current.session.id, status: "starting")
      authorization = Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Runtime proof")
      authorization.update!(expires_at: 8.seconds.from_now)
      credential = agent_session.issue_runtime_grant!

      wait_for_http(port, process: puma)
      staged = mcp_call(port, credential.bearer, "delete_meal", {
        id: meal.id, idempotency_key: idempotency_key
      })
      assert_equal "pending", staged.dig("result", "structuredContent", "status"), staged.inspect
      proposal = Agent::MutationProposal.find(staged.dig("result", "structuredContent", "proposal_id"))
      assert Meal.exists?(meal.id)

      File.write(release, "continue\n")
      wait_until(timeout: 10) { proposal.permission_request.reload.external_request_id == "fake-tool" }
      proposal.decide!(outcome: "approved", by: users(:two), token: proposal.confirmation_token)
      runtime_result = runtime.wait

      assert_predicate runtime_result.fetch(:status), :success?, runtime_result.fetch(:stderr)
      assert_equal "executed", proposal.reload.status
      assert_not Meal.exists?(meal.id)
      assert_equal %w[mutation.proposed mutation.approved mutation.executed],
        Agent::AuditEvent.where(subject_type: proposal.class.name, subject_id: proposal.id).order(:id).pluck(:event_type)
      assert_equal [ { "name" => "delete_meal", "status" => "succeeded" } ],
        JSON.parse(File.readlines(evidence).last).fetch("mcp_tool_calls")

      recovered_evidence = File.join(root, "guarded-recovery-evidence.jsonl")
      recovered_runtime = start_runtime(
        root,
        "--session", agent_session.id.to_s,
        "--evidence", recovered_evidence,
        environment: {
          "FAKE_ACP_MODE" => "normal",
          "FAKE_SESSION_ID" => external_session_id
        }
      )
      recovered_result = recovered_runtime.wait

      assert_predicate recovered_result.fetch(:status), :success?, recovered_result.fetch(:stderr)
      assert_equal %w[health_read knowledge_read knowledge_submit], agent_session.grants.order(:id).last.capability_groups
    ensure
      recovered_runtime&.stop
      runtime&.stop
      puma&.stop
      delete_runtime_session_records(agent_session)
      Current.reset
    end
  end

  test "runtime shutdown waits through a real second-process SQLite writer and records pragmas" do
    with_instance_root do |root|
      configure_runtime_profile
      release = File.join(root, "release")
      info_file = File.join(root, "agent-info.json")
      writer_ready = File.join(root, "writer-ready")
      runtime = start_runtime(
        root,
        "--conversation", agent_conversations(:active).id.to_s,
        "--hold-until", release,
        "--prompt", "sqlite",
        environment: {
          "FAKE_ACP_MODE" => "normal",
          "FAKE_SESSION_ID" => "sqlite-#{SecureRandom.hex(6)}",
          "FAKE_AGENT_INFO_FILE" => info_file
        }
      )
      wait_for_json(info_file, process: runtime)

      writer = ProcessHarness.new(
        {
          "RAILS_ENV" => "test",
          "DATABASE_URL" => test_database_url
        },
        RbConfig.ruby,
        Rails.root.join("bin/rails").to_s,
        "runner",
        <<~RUBY,
          connection = ActiveRecord::Base.connection
          Agent::Profile.transaction do
            Agent::Profile.where(id: #{agent_profiles(:hearth).id}).update_all(updated_at: Time.current)
            File.write(#{writer_ready.inspect}, "ready")
            sleep 0.5
            Agent::Profile.where(id: #{agent_profiles(:hearth).id}).update_all(updated_at: Time.current)
          end
          puts JSON.generate(
            journal_mode: connection.select_value("PRAGMA journal_mode"),
            busy_timeout: connection.select_value("PRAGMA busy_timeout"),
            configured_timeout: connection.pool.db_config.configuration_hash.fetch(:timeout)
          )
        RUBY
        chdir: Rails.root.to_s
      ).start
      wait_until(timeout: PROCESS_START_TIMEOUT) do
        flunk "writer exited before becoming ready: #{writer.stderr}" unless writer.alive?
        File.exist?(writer_ready)
      end
      File.write(release, "continue\n")
      runtime_result = runtime.wait
      writer_result = writer.wait

      assert_predicate runtime_result.fetch(:status), :success?, runtime_result.fetch(:stderr)
      assert_predicate writer_result.fetch(:status), :success?, writer_result.fetch(:stderr)
      refute_match(/BusyException|database is locked/, runtime_result.values_at(:stdout, :stderr).join)
      refute_match(/BusyException|database is locked/, writer_result.values_at(:stdout, :stderr).join)
      writer_pragmas = JSON.parse(writer_result.fetch(:stdout).lines.last)
      runtime_connection = ActiveRecord::Base.connection
      assert_equal 5_000, writer_pragmas.fetch("configured_timeout")
      assert_equal 5_000, runtime_connection.pool.db_config.configuration_hash.fetch(:timeout)
      # Rails 8.1 installs sqlite3-ruby's GVL-releasing busy handler from
      # `timeout`; that handler deliberately leaves PRAGMA busy_timeout at 0.
      assert_equal 0, writer_pragmas.fetch("busy_timeout")
      assert_equal 0, runtime_connection.select_value("PRAGMA busy_timeout")
      assert_equal runtime_connection.select_value("PRAGMA journal_mode"), writer_pragmas.fetch("journal_mode")

      production_targets = ActiveRecord::Base.configurations
        .configs_for(env_name: "production")
        .map(&:database)
      assert_equal 4, production_targets.uniq.length
    ensure
      writer&.stop
      runtime&.stop
    end
  end

  test "SIGTERM performs idempotent runtime cleanup without leaving the exact child" do
    with_instance_root do |root|
      configure_runtime_profile
      info_file = File.join(root, "agent-info.json")
      runtime = start_runtime(
        root,
        "--conversation", agent_conversations(:active).id.to_s,
        "--hold-until", File.join(root, "never-release"),
        once: false,
        environment: {
          "FAKE_ACP_MODE" => "normal",
          "FAKE_SESSION_ID" => "signal-#{SecureRandom.hex(6)}",
          "FAKE_AGENT_INFO_FILE" => info_file
        }
      )
      agent_pid = wait_for_json(info_file, process: runtime).fetch("pid")

      runtime.terminate
      result = runtime.wait

      assert_predicate result.fetch(:status), :success?, result.fetch(:stderr)
      assert_process_gone(agent_pid)
      refute File.exist?(File.join(root, ".hearth/tmp/acp/supervisor.pid"))
      runtime.stop
    ensure
      runtime&.stop
    end
  end

  test "evidence records a retryable recovery failure and exits nonzero" do
    with_instance_root do |root|
      configure_runtime_profile
      evidence = File.join(root, "failed-runtime-evidence.jsonl")
      runtime = start_runtime(
        root,
        "--session", agent_sessions(:connected).id.to_s,
        "--evidence", evidence,
        environment: {
          "FAKE_ACP_MODE" => "early_exit",
          "FAKE_SESSION_ID" => agent_sessions(:connected).external_session_id
        }
      )

      result = runtime.wait
      row = JSON.parse(File.readlines(evidence).sole)

      assert_not_predicate result.fetch(:status), :success?
      assert_equal "failed", row["outcome"]
      assert_equal "disconnected", row.dig("lifecycle", "transport_status")
      assert_match(/agent exited/, row.dig("lifecycle", "recovery_error"))
      assert_nil row["agent_pid"]
    ensure
      runtime&.stop
    end
  end

  test "default production runtime resolves four isolated instance databases" do
    with_instance_root do |root|
      prepare_production_databases(root)
      evidence = File.join(root, "production-runtime-evidence.jsonl")
      runtime = ProcessHarness.new(
        {
          "RAILS_ENV" => nil,
          "DATABASE_URL" => nil,
          "CACHE_DATABASE_URL" => nil,
          "QUEUE_DATABASE_URL" => nil,
          "CABLE_DATABASE_URL" => nil,
          "SECRET_KEY_BASE" => "test-secret-key-base-" * 4
        },
        RbConfig.ruby,
        RUNTIME,
        "--root",
        root,
        "--once",
        "--evidence",
        evidence,
        chdir: root
      ).start

      result = runtime.wait
      assert_predicate result.fetch(:status), :success?, result.fetch(:stderr)
      row = JSON.parse(File.readlines(evidence).sole)
      assert_equal(
        {
          "primary" => "production.sqlite3",
          "cache" => "production_cache.sqlite3",
          "queue" => "production_queue.sqlite3",
          "cable" => "production_cable.sqlite3"
        },
        row["database_targets"]
      )
      assert row["database_targets"].values.none? { |target| target == "[outside-instance]" }
    ensure
      runtime&.stop
    end
  end

  private
    def release_runtime_test_lock
      @runtime_test_lock&.flock(File::LOCK_UN)
      @runtime_test_lock&.close
      @runtime_test_lock = nil
    end

    class ProcessHarness
      attr_reader :pid

      def alive? = @wait_thread.alive?
      def stderr = @stderr_buffer.dup

      def initialize(environment, *command, chdir:)
        @environment = environment
        @command = command
        @chdir = chdir
        @stdout_buffer = +""
        @stderr_buffer = +""
      end

      def start
        @stdin, stdout, stderr, @wait_thread = Open3.popen3(
          @environment,
          *@command,
          chdir: @chdir,
          pgroup: true
        )
        @pid = @wait_thread.pid
        @stdin.close
        @stdout_thread = Thread.new { drain(stdout, @stdout_buffer) }
        @stderr_thread = Thread.new { drain(stderr, @stderr_buffer) }
        self
      end

      def wait(timeout: 20)
        wait_until(timeout) { !@wait_thread.alive? }
        @wait_thread.join
        @stdout_thread.join
        @stderr_thread.join
        { status: @wait_thread.value, stdout: @stdout_buffer, stderr: @stderr_buffer }
      rescue Timeout::Error
        stop
        raise
      end

      def stop
        return unless @wait_thread

        signal("TERM") if @wait_thread.alive?
        @wait_thread.join(2)
        if @wait_thread.alive?
          signal("KILL")
          @wait_thread.join(2)
        end
        @stdout_thread&.join(2)
        @stderr_thread&.join(2)
      end

      def terminate
        Process.kill("TERM", pid)
      rescue Errno::ESRCH
        nil
      end

      private
        def signal(name)
          Process.kill(name, -pid)
        rescue Errno::ESRCH
          nil
        end

        def drain(io, buffer)
          buffer << io.readpartial(4096) while true
        rescue EOFError, IOError
          nil
        end

        def wait_until(timeout)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          until yield
            raise Timeout::Error if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 0.02
          end
        end
    end

    def start_runtime(root, *arguments, environment:, once: true)
      runtime_arguments = [ "--root", root ]
      runtime_arguments << "--once" if once
      runtime_arguments.concat(arguments)
      ProcessHarness.new(
        {
          "RAILS_ENV" => "test",
          "DATABASE_URL" => test_database_url
        }.merge(environment),
        RbConfig.ruby,
        RUNTIME,
        *runtime_arguments,
        chdir: root
      ).start
    end

    def start_puma(root, port)
      ProcessHarness.new(
        {
          "RAILS_ENV" => "test",
          "DATABASE_URL" => test_database_url
        },
        RbConfig.ruby,
        Rails.root.join("bin/rails").to_s,
        "server",
        "--binding", "127.0.0.1",
        "--port", port.to_s,
        "--pid", File.join(root, "puma.pid"),
        chdir: Rails.root.to_s
      ).start
    end

    def prepare_production_databases(root)
      storage = File.join(root, ".hearth/storage")
      FileUtils.mkdir_p(storage)
      environment = {
        "RAILS_ENV" => "production",
        "DATABASE_URL" => "sqlite3:#{File.join(storage, 'production.sqlite3')}",
        "CACHE_DATABASE_URL" => "sqlite3:#{File.join(storage, 'production_cache.sqlite3')}",
        "QUEUE_DATABASE_URL" => "sqlite3:#{File.join(storage, 'production_queue.sqlite3')}",
        "CABLE_DATABASE_URL" => "sqlite3:#{File.join(storage, 'production_cable.sqlite3')}",
        "SECRET_KEY_BASE" => "test-secret-key-base-" * 4
      }
      result = ProcessHarness.new(
        environment,
        RbConfig.ruby,
        Rails.root.join("bin/rails").to_s,
        "db:prepare",
        chdir: Rails.root.to_s
      ).start.wait
      assert_predicate result.fetch(:status), :success?, result.fetch(:stderr)
    end

    def configure_runtime_profile
      agent_profiles(:hearth).update!(
        executable_path: RbConfig.ruby,
        arguments: [ FAKE_AGENT ],
        environment_keys: %w[
          FAKE_ACP_MODE FAKE_SESSION_ID FAKE_AGENT_INFO_FILE
          FAKE_PERMISSION_OPERATION FAKE_PERMISSION_INPUT
        ]
      )
    end

    def mcp_call(port, bearer, name, arguments)
      request = Net::HTTP::Post.new("/mcp")
      request["Authorization"] = "Bearer #{bearer}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json, text/event-stream"
      request.body = JSON.generate(
        jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments }
      )
      response = Net::HTTP.start("127.0.0.1", port, open_timeout: 1, read_timeout: 5) { |http| http.request(request) }
      assert_kind_of Net::HTTPSuccess, response
      JSON.parse(response.body)
    end

    def delete_runtime_session_records(agent_session)
      return unless agent_session&.persisted?

      proposal_ids = Agent::MutationProposal.where(agent_session: agent_session).ids
      request_ids = Agent::PermissionRequest.where(agent_session: agent_session).ids
      Agent::AuditEvent.where(agent_session: agent_session).delete_all
      Agent::MutationExecution.where(mutation_proposal_id: proposal_ids).delete_all
      Agent::PermissionDecision.where(permission_request_id: request_ids).delete_all
      Agent::PermissionRequest.where(id: request_ids).update_all(permission_subject_type: nil, permission_subject_id: nil)
      Agent::MutationProposal.where(id: proposal_ids).delete_all
      Agent::OperationalAuthorization.where(agent_session: agent_session).delete_all
      Agent::PermissionRequest.where(id: request_ids).delete_all
      Agent::ToolActivity.where(agent_session: agent_session).delete_all
      Agent::Message.where(agent_session: agent_session).delete_all
      Agent::Grant.where(agent_session: agent_session).delete_all
      Agent::Session.where(id: agent_session.id).delete_all
    end

    def test_database_url
      "sqlite3:#{File.expand_path(ActiveRecord::Base.connection_db_config.database, Rails.root)}"
    end

    def with_instance_root
      Dir.mktmpdir("hearth-runtime-integration") do |root|
        Hearth::Instance.new(root).initialize!
        yield root
      end
    end

    def available_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def wait_for_http(port, process:, timeout: PROCESS_START_TIMEOUT)
      wait_until(timeout: timeout) do
        flunk "Puma exited before becoming ready: #{process.stderr}" unless process.alive?
        response = Net::HTTP.start("127.0.0.1", port, open_timeout: 0.2, read_timeout: 0.2) do |http|
          http.get("/up")
        end
        response.is_a?(Net::HTTPSuccess)
      rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, EOFError
        false
      end
    end

    def wait_until(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until yield
        flunk "condition did not become true" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.02
      end
    end

    def wait_for_json(path, process:, timeout: PROCESS_START_TIMEOUT)
      value = nil
      wait_until(timeout: timeout) do
        flunk "process exited before writing #{path}: #{process.stderr}" unless process.alive?
        value = JSON.parse(File.read(path))
      rescue Errno::ENOENT, JSON::ParserError
        false
      end
      value
    end

    def assert_process_gone(pid)
      wait_until do
        Process.kill(0, pid)
        false
      rescue Errno::ESRCH
        true
      end
    end
end
