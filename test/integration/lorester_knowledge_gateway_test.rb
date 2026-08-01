require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class LoresterKnowledgeGatewayTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  LORESTER_ROOT = ENV["LORESTER_TEST_ROOT"]
  LORESTER = LORESTER_ROOT && File.join(LORESTER_ROOT, "target/debug/lorester")
  FIXTURE = LORESTER_ROOT && File.join(LORESTER_ROOT, "examples/vaults/research")

  test "all six grant-filtered tools cross the official endpoint into one isolated Lorester owner" do
    skip "Set LORESTER_TEST_ROOT to run the live Lorester contract" unless LORESTER && File.executable?(LORESTER)

    Dir.mktmpdir("hearth-lorester-live") do |directory|
      vault = File.join(directory, "vault")
      data_dir = File.join(directory, "data")
      FileUtils.cp_r(FIXTURE, vault)
      git!(vault, "init", "-q")
      git!(vault, "config", "user.name", "Hearth Lorester Test")
      git!(vault, "config", "user.email", "hearth-lorester@example.invalid")
      git!(vault, "add", ".")
      git!(vault, "commit", "-qm", "fixture")
      source_commit = git!(vault, "rev-parse", "HEAD").strip
      lorester_environment = {
        "LORESTER_DATA_DIR" => data_dir,
        "LORESTER_BOTSTER_SESSION_WORKER" => "/usr/bin/true",
        "LORESTER_CODEX_EXECUTABLE" => "/usr/bin/true"
      }
      command!(lorester_environment, LORESTER, "--json", "projection", "rebuild", "HEAD", "--vault", vault)
      owner = start_owner(lorester_environment, vault)
      wait_for_owner(vault, data_dir)

      session = create_runtime_session
      credential = session.issue_runtime_grant!
      host! "localhost"
      environment = { "LORESTER_VAULT" => vault, "LORESTER_EXECUTABLE" => LORESTER, "LORESTER_DATA_DIR" => data_dir }
      with_environment(environment) do
        listed = mcp_post(credential, id: 1, method: "tools/list", params: {})
        names = listed.dig("result", "tools").pluck("name")
        assert_equal HearthMcp::KnowledgeTools::ALL.map(&:tool_name), names.grep(/\Aknowledge\./)

        summary = call_tool(credential, 2, "knowledge.health.summary", {})
        assert_equal "ready", summary.dig("result", "readiness")
        assert_equal source_commit, summary.dig("result", "source_commit")

        search = call_tool(credential, 3, "knowledge.search", { query: "research" })
        note = search.dig("result", "notes").first
        assert note, search.inspect
        assert_equal source_commit, note.dig("citation", "source_commit")
        assert_equal 1, note.dig("citation", "contract_version")

        read = call_tool(credential, 4, "knowledge.note.read", { note_id: note.fetch("id") })
        assert_equal note.fetch("id"), read.dig("result", "id")
        assert_equal source_commit, read.dig("result", "citation", "source_commit")

        related = call_tool(credential, 5, "knowledge.related", { note_id: note.fetch("id") })
        assert_kind_of Array, related.dig("result", "notes")

        message = Agent::Message.create!(
          household: credential.grant.household,
          person: credential.grant.person,
          conversation: credential.grant.conversation,
          agent_session: session,
          role: "user",
          body: "Remember this safe live integration observation",
          body_digest: Digest::SHA256.hexdigest("Remember this safe live integration observation")
        )
        before_files = Dir[File.join(vault, "inbox", "hearth-*.md")]
        staged = call_tool(credential, 6, "knowledge.inbox.submit", {
          message_id: message.id,
          content: "A household-safe live integration observation",
          requested_intent: "capture",
          idempotency_key: "live-lorester-submission"
        })
        submission = Agent::KnowledgeSubmission.find(staged.dig("result", "submission_id"))
        assert_equal "pending", submission.status
        assert_equal before_files, Dir[File.join(vault, "inbox", "hearth-*.md")]

        submission.permission_request.decide!(outcome: "approved", by: users(:two))
        assert_equal "materialized", submission.reload.status
        assert_equal before_files.size + 1, Dir[File.join(vault, "inbox", "hearth-*.md")].size

        replay = call_tool(credential, 7, "knowledge.inbox.submit", {
          message_id: message.id,
          content: "A household-safe live integration observation",
          requested_intent: "capture",
          idempotency_key: "live-lorester-submission"
        })
        assert_equal submission.id, replay.dig("result", "submission_id")
        assert_equal before_files.size + 1, Dir[File.join(vault, "inbox", "hearth-*.md")].size

        status = call_tool(credential, 8, "knowledge.inbox.status", { submission_id: submission.id })
        assert_equal submission.lorester_submission_id, status.dig("result", "lorester_submission_id")
        assert_includes %w[materialized admitted processing complete], status.dig("result", "status")
        assert_equal %w[
          knowledge.read knowledge.read knowledge.read knowledge.read knowledge.submit knowledge.submit knowledge.read
        ], Agent::ToolActivity.where(agent_session: session).order(:id).pluck(:capability)
      end
    ensure
      stop_owner(owner)
      delete_runtime_session_records(session)
    end
  end

  private
    def call_tool(credential, id, name, arguments)
      response = mcp_post(credential, id: id, method: "tools/call", params: { name: name, arguments: arguments })
      refute_equal true, response.dig("result", "isError"), response.inspect
      response.dig("result", "structuredContent")
    end

    def mcp_post(credential, id:, method:, params:)
      post "/mcp",
        params: JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params),
        headers: {
          "Authorization" => "Bearer #{credential.bearer}",
          "Content-Type" => "application/json",
          "Accept" => "application/json, text/event-stream"
        }
      assert_response :success
      response.parsed_body
    end

    def start_owner(environment, vault)
      stdout_reader, stdout_writer = IO.pipe
      stderr_reader, stderr_writer = IO.pipe
      pid = Process.spawn(
        environment,
        LORESTER, "--json", "run", "--vault", vault,
        out: stdout_writer,
        err: stderr_writer
      )
      stdout_writer.close
      stderr_writer.close
      { pid: pid, stdout: stdout_reader, stderr: stderr_reader }
    end

    def wait_for_owner(vault, data_dir)
      client = Lorester::Client.new(vault: vault, executable: LORESTER, data_dir: data_dir, timeout: 0.2)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      loop do
        return if client.discover["readiness"] == "ready"
      rescue Lorester::Client::Error
        raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.02
      end
    end

    def stop_owner(owner)
      return unless owner
      Process.kill("TERM", owner.fetch(:pid))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      loop do
        waited = Process.waitpid(owner.fetch(:pid), Process::WNOHANG)
        break if waited
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          Process.kill("KILL", owner.fetch(:pid))
          Process.waitpid(owner.fetch(:pid))
          break
        end
        sleep 0.02
      end
    rescue Errno::ESRCH, Errno::ECHILD
    ensure
      owner&.fetch(:stdout)&.close
      owner&.fetch(:stderr)&.close
    end

    def command!(environment, *command)
      stdout, stderr, status = Open3.capture3(environment, *command)
      assert_predicate status, :success?, "#{command.join(' ')} failed: #{stderr}\n#{stdout}"
      stdout
    end

    def git!(root, *arguments) = command!({}, "git", "-C", root, *arguments)

    def with_environment(values)
      previous = values.to_h { |key, _value| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    def delete_runtime_session_records(session)
      return unless session
      submissions = Agent::KnowledgeSubmission.where(agent_session: session)
      requests = Agent::PermissionRequest.where(agent_session: session)
      Agent::AuditEvent.where(agent_session: session).delete_all
      Agent::PermissionDecision.where(permission_request: requests).delete_all
      requests.update_all(permission_subject_type: nil, permission_subject_id: nil)
      submissions.delete_all
      requests.delete_all
      Agent::ToolActivity.where(agent_session: session).delete_all
      Agent::Message.where(agent_session: session).delete_all
      Agent::Grant.where(agent_session: session).delete_all
      session.delete
    end
end
