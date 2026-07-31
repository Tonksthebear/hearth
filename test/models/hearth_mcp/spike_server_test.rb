require "test_helper"
require "rack/mock"

class HearthMcp::SpikeServerTest < ActiveSupport::TestCase
  test "official stateless transport initializes lists and calls the database status tool" do
    app = HearthMcp::SpikeServer.transport

    initialized = post(app, id: 1, method: "initialize", params: {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "test", version: "1.0" }
    })
    listed = post(app, id: 2, method: "tools/list", params: {})
    called = post(app, id: 3, method: "tools/call", params: {
      name: "spike_status_tool",
      arguments: {}
    })

    assert_equal "hearth-local-spike", initialized.dig("result", "serverInfo", "name")
    assert_equal [ "spike_status_tool" ], listed.dig("result", "tools").map { |tool| tool["name"] }
    assert_equal '{"database":"reachable"}', called.dig("result", "content", 0, "text")
  end

  private
    def post(app, message)
      response = Rack::MockRequest.new(app).post(
        "/mcp",
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json, text/event-stream",
        input: JSON.generate({ jsonrpc: "2.0" }.merge(message))
      )

      assert_equal 200, response.status
      JSON.parse(response.body)
    end
end
