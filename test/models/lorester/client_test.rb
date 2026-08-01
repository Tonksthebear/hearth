require "test_helper"
require "tmpdir"

class Lorester::ClientTest < ActiveSupport::TestCase
  ROOT_HELPER = Rails.root.join("test/fixtures/files/lorester/root_helper.rb").to_s

  test "discovers the authoritative root with the configured data directory" do
    Dir.mktmpdir do |directory|
      client = Lorester::Client.new(vault: "test", executable: ROOT_HELPER, data_dir: directory)

      root = client.send(:discover_root)

      assert_equal({ "vault_id" => "vault-test", "endpoint" => directory }, root)
    end
  end

  test "reports absent configuration and cleans up timed out root discovery" do
    error = assert_raises(Lorester::Client::Error) { Lorester::Client.new(vault: nil).discover }
    assert_equal "not_configured", error.code

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Lorester::Client::Error) do
      Lorester::Client.new(vault: "hang", executable: ROOT_HELPER, timeout: 0.05).send(:discover_root)
    end
    assert_equal "unavailable", error.code
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  test "performs hello then each of the six strict one-frame operations" do
    note = {
      "id" => "note_v1_abc",
      "title" => { "text" => "Title", "truncated" => false },
      "description" => nil,
      "excerpt" => { "text" => "Excerpt", "truncated" => false },
      "citation" => { "source_commit" => "abc123", "contract_version" => 1 }
    }
    exchanges = [
      [ :discover, [], "knowledge_discover", { "type" => "discovery", "contract_version" => 1, "control_protocol_version" => 1, "owner_started_at" => 1, "readiness" => "ready", "source_commit" => "abc123" } ],
      [ :search, [ "query" ], "knowledge_search", { "type" => "search", "notes" => [ note ], "truncated" => false } ],
      [ :read, [ "note_v1_abc" ], "knowledge_read", note.merge("type" => "note") ],
      [ :related, [ "note_v1_abc" ], "knowledge_related", { "type" => "related", "notes" => [ note ], "truncated" => false } ],
      [ :submit, [ { request_id: "request-123", origin: "hearth_agent", content: "safe", conversation_reference: "c", message_reference: "m", requested_intent: "capture" } ], "knowledge_submit", submission_response("submitted") ],
      [ :submission_status, [ "submission_v1_abc" ], "knowledge_submission_status", submission_response("submission_status") ]
    ]

    exchanges.each do |method, arguments, operation, response|
      with_server(response) do |client, requests|
        method == :submit ? client.public_send(method, **arguments.sole) : client.public_send(method, *arguments)
        assert_equal %w[hello].first, requests.first.fetch("operation")
        assert_equal operation, requests.second.fetch("operation")
        assert_equal 1, requests.second["contract_version"]
      end
    end
  end

  test "rejects oversized and incompatible responses without leaking transport paths" do
    with_server({ "type" => "search", "notes" => [], "truncated" => false }, declared_length: Lorester::Client::MAX_FRAME_BYTES + 1) do |client, _requests|
      error = assert_raises(Lorester::Client::Error) { client.search("query") }
      assert_equal "incompatible", error.code
      refute_includes error.message, "/tmp"
    end
  end

  test "maps every remote failure code to the bounded public taxonomy" do
    mappings = {
      "projection_pressure" => "pressure",
      "request_in_progress" => "in_progress",
      "idempotency_conflict" => "idempotency_conflict",
      "projection_stale" => "stale",
      "note_not_found" => "not_found",
      "contract_incompatible" => "incompatible",
      "projection_unavailable" => "unavailable",
      "authorization_denied" => "authorization",
      "validation_failed" => "validation",
      "unexpected_remote_failure" => "unavailable"
    }

    mappings.each do |remote_code, public_code|
      with_server(envelope: { "ok" => false, "error" => { "code" => remote_code } }) do |client, _requests|
        error = assert_raises(Lorester::Client::Error) { client.search("query") }
        assert_equal public_code, error.code
        refute_includes error.message, "/tmp"
      end
    end
  end

  test "reports a rejected hello as stopped without leaking its socket path" do
    with_server(hello_envelope: { "ok" => false, "error" => { "code" => "owner_stopped" } }) do |client, _requests|
      error = assert_raises(Lorester::Client::Error) { client.search("query") }
      assert_equal "stopped", error.code
      refute_includes error.message, "/tmp"
    end
  end

  test "rejects incompatible discovery and note payloads" do
    invalid_responses = [
      [ :discover, {
        "type" => "discovery", "contract_version" => 2, "control_protocol_version" => 1,
        "owner_started_at" => 1, "readiness" => "ready", "source_commit" => "abc123"
      } ],
      [ :discover, {
        "type" => "discovery", "contract_version" => 1, "control_protocol_version" => 1,
        "owner_started_at" => 1, "readiness" => "mystery", "source_commit" => "abc123"
      } ],
      [ :read, {
        "type" => "note", "id" => "note_v1_bad", "title" => { "text" => "Bad", "truncated" => false }
      } ]
    ]

    invalid_responses.each do |method, response|
      with_server(response) do |client, _requests|
        error = assert_raises(Lorester::Client::Error) do
          method == :read ? client.read("note_v1_bad") : client.discover
        end
        assert_equal "incompatible", error.code
        refute_includes error.message, "/tmp"
      end
    end
  end

  test "test method stubbing restores private methods and their visibility" do
    object = Object.new
    object.define_singleton_method(:private_value) { :original }
    object.singleton_class.send(:private, :private_value)

    with_stubbed_method(object, :private_value, :stubbed) do
      assert_equal :stubbed, object.send(:private_value)
      assert object.singleton_class.private_method_defined?(:private_value)
    end

    assert_equal :original, object.send(:private_value)
    assert object.singleton_class.private_method_defined?(:private_value)
  end

  private
    def submission_response(type)
      { "type" => type, "submission_id" => "submission_v1_abc", "state" => "materialized", "updated_at" => 1 }
    end

    def with_server(response = nil, declared_length: nil, envelope: nil, hello_envelope: nil)
      Dir.mktmpdir do |directory|
        path = File.join(directory, "lorester.sock")
        server = UNIXServer.new(path)
        requests = []
        thread = Thread.new do
          socket = server.accept
          requests << read_frame(socket)
          write_frame(
            socket,
            hello_envelope || { ok: true, result: { type: "hello_ack", vault_id: "vault-test", protocol_version: 1 } }
          )
          unless hello_envelope
            requests << read_frame(socket)
            operation_envelope = envelope || { ok: true, result: { type: "knowledge", response: response } }
            write_frame(socket, operation_envelope, declared_length: declared_length)
          end
          socket.close
        ensure
          server.close
        end
        client = Lorester::Client.new(vault: "test")
        with_stubbed_method(client, :discover_root, { "vault_id" => "vault-test", "endpoint" => path }) do
          yield client, requests
        end
      ensure
        thread&.join
      end
    end

    def read_frame(socket)
      length = socket.read(4).unpack1("N")
      JSON.parse(socket.read(length))
    end

    def write_frame(socket, payload, declared_length: nil)
      json = JSON.generate(payload)
      socket.write([ declared_length || json.bytesize ].pack("N"))
      socket.write(json) unless declared_length
    end
end
