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
