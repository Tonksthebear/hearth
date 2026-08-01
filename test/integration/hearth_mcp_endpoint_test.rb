require "test_helper"

class HearthMcpEndpointTest < ActionDispatch::IntegrationTest
  SUPPORTED_PROTOCOLS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze

  setup do
    @agent_session = create_runtime_session
    @credential = @agent_session.issue_runtime_grant!
    host! "localhost"
  end

  test "negotiates every stable protocol and lists the exact read catalog without session affinity" do
    SUPPORTED_PROTOCOLS.each do |protocol|
      initialize_response = mcp_post(id: 1, method: "initialize", params: {
        protocolVersion: protocol,
        capabilities: {},
        clientInfo: { name: "test", version: "1" }
      })
      assert_equal protocol, initialize_response.dig("result", "protocolVersion")
      assert_nil response.headers["Mcp-Session-Id"]

      listed = mcp_post(id: 2, method: "tools/list", params: {})
      assert_equal HearthMcp::Tools::ALL.map(&:tool_name), listed.dig("result", "tools").pluck("name")
      assert_equal "private, no-store", response.headers["Cache-Control"]
    end

    assert_empty Agent::ToolActivity.where(agent_session: @agent_session)
  end

  test "requires a valid bearer on every loopback request and rejects remote requests" do
    post "/mcp", params: request_body, headers: request_headers.except("Authorization")
    assert_response :unauthorized

    post "/mcp", params: request_body, headers: request_headers.merge("Authorization" => "Bearer invalid.invalid")
    assert_response :unauthorized

    host! "hearth.example"
    post "/mcp", params: request_body, headers: request_headers.merge("REMOTE_ADDR" => "203.0.113.10")
    assert_response :forbidden

    post "/mcp", params: request_body, headers: request_headers.merge("REMOTE_ADDR" => "127.0.0.1")
    assert_response :forbidden
  end

  test "calls a real catalog tool and records only digests" do
    called = mcp_post(id: 3, method: "tools/call", params: {
      name: "get_current_context",
      arguments: {}
    })

    assert_equal "hearth_database", called.dig("result", "structuredContent", "origin"), called.inspect
    assert_equal people(:two).id, called.dig("result", "structuredContent", "data", "person", "id")
    assert_equal called.dig("result", "content", 0, "text"), JSON.generate(called.dig("result", "structuredContent"))

    activity = Agent::ToolActivity.where(agent_session: @agent_session).sole
    assert_equal "get_current_context", activity.tool_name
    assert_equal "health.read", activity.capability
    assert_equal "succeeded", activity.status
    assert_nil activity.input_body
    assert_nil activity.output_body
    assert_equal 64, activity.input_digest.length
    assert_equal 64, activity.output_digest.length
    assert_predicate activity, :redacted_at?
  end

  test "a grant without read capability exposes no tools and cannot dispatch one" do
    @credential.grant.update!(capability_groups: [ "health_write" ])

    listed = mcp_post(id: 4, method: "tools/list", params: {})
    assert_empty listed.dig("result", "tools")

    called = mcp_post(id: 5, method: "tools/call", params: { name: "get_current_context", arguments: {} })
    assert called["error"] || called.dig("result", "isError")
  end

  test "exact-context operational consent rotates to typed writes and executes an idempotent meal aggregate" do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    @agent_session = Agent::Session.create!(
      household: Current.household,
      person: Current.person,
      conversation: agent_conversations(:active),
      installation: agent_installations(:local),
      browser_session: Current.session,
      status: "starting",
      authentication_status: "authenticated",
      mcp_authorization_status: "not_configured"
    )
    @credential = @agent_session.issue_runtime_grant!
    Agent::OperationalAuthorization.authorize!(agent_session: @agent_session, reason: "Daily operations")
    @credential = @agent_session.issue_runtime_grant!

    listed = mcp_post(id: 30, method: "tools/list", params: {})
    names = listed.dig("result", "tools").pluck("name")
    assert_includes names, "create_meal"
    refute_includes names, "update_record"

    arguments = {
      eaten_on: "2026-07-31",
      meal_items: [ { source_kind: "free_text", snapshot_label: "MCP meal" } ],
      idempotency_key: "endpoint-create-meal"
    }
    first = mcp_post(id: 31, method: "tools/call", params: { name: "create_meal", arguments: arguments })
    second = mcp_post(id: 32, method: "tools/call", params: { name: "create_meal", arguments: arguments })

    assert_equal "executed", first.dig("result", "structuredContent", "status"), first.inspect
    assert_equal first.dig("result", "structuredContent", "result", "id"), second.dig("result", "structuredContent", "result", "id")
    assert_equal 1, people(:two).meals.where(notes: nil).joins(:meal_items).where(meal_items: { snapshot_label: "MCP meal" }).count
    assert_equal [ "health.write", "health.write" ], Agent::ToolActivity.where(agent_session: @agent_session).order(:id).last(2).pluck(:capability)
  ensure
    Current.reset
  end

  test "records tool errors as failed and charges their call budget" do
    called = mcp_post(id: 6, method: "tools/call", params: {
      name: "get_recipe",
      arguments: { id: Recipe.maximum(:id) + 10_000 }
    })

    assert_equal true, called.dig("result", "isError")
    activity = Agent::ToolActivity.where(agent_session: @agent_session).sole
    assert_equal "failed", activity.status
    assert_equal 1, @credential.grant.reload.calls_used
  end

  test "returns invalid cursors as bounded tool errors without Ruby internals" do
    [ "NQ", "IjUi", "e30", "eyJpZCI6ImFiYyJ9" ].each_with_index do |cursor, index|
      called = mcp_post(id: 10 + index, method: "tools/call", params: {
        name: "list_recipes",
        arguments: { cursor: cursor }
      })

      assert_equal true, called.dig("result", "isError")
      message = called.dig("result", "content", 0, "text")
      assert_includes message, "cursor is invalid"
      refute_match(/undefined method|key not found|Integer|String/, message)
    end
    assert_equal 4, Agent::ToolActivity.where(agent_session: @agent_session, status: "failed").count
  end

  test "does not write raw tool arguments to the Rails log" do
    sentinel = "mcp-raw-argument-sentinel-7f47c0"
    log_path = Rails.root.join("log/test.log")
    offset = File.exist?(log_path) ? File.size(log_path) : 0

    mcp_post(id: 20, method: "tools/call", params: {
      name: "list_recipes",
      arguments: { cursor: sentinel }
    })
    Rails.logger.flush if Rails.logger.respond_to?(:flush)

    assert_equal "[FILTERED]", request.filtered_parameters.dig("params", "arguments")
    assert_nil request.filtered_parameters["mcp"]
    appended = File.exist?(log_path) ? File.binread(log_path, File.size(log_path) - offset, offset) : ""
    refute_includes appended, sentinel
  end

  test "marks an expired grant for reauthorization and rejects the request" do
    travel_to @credential.grant.expires_at + 1.second do
      post "/mcp", params: request_body, headers: request_headers
      assert_response :unauthorized
    end

    assert_equal "reauthorization_required", @agent_session.reload.mcp_authorization_status
  end

  test "distinguishes a response that exceeds the remaining output budget" do
    @credential.grant.update!(output_tokens_limit: 1)

    called = mcp_post(id: 21, method: "tools/call", params: {
      name: "get_current_context",
      arguments: {}
    })

    assert_equal true, called.dig("result", "isError")
    assert_includes called.dig("result", "content", 0, "text"), "remaining output budget"
    assert_equal [ 1, 0 ], @credential.grant.reload.values_at(:calls_used, :output_tokens_used)
  end

  test "routes streamable HTTP verbs through the MCP transport" do
    get "/mcp", headers: request_headers
    assert_response :method_not_allowed

    delete "/mcp", headers: request_headers
    assert_response :success
    assert_equal({ "success" => true }, response.parsed_body)
  end

  private
    def mcp_post(id:, method:, params:)
      post "/mcp",
        params: JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params),
        headers: request_headers
      assert_response :success
      response.parsed_body
    end

    def request_body
      JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list", params: {})
    end

    def request_headers
      {
        "Authorization" => "Bearer #{@credential.bearer}",
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream"
      }
    end
end
