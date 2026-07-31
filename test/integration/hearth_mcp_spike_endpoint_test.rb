require "test_helper"
require "open3"

class HearthMcpSpikeEndpointTest < ActionDispatch::IntegrationTest
  test "local request reaches the mounted MCP transport" do
    host! "localhost"
    post "/mcp",
      params: {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/list",
        params: {}
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream"
      }

    assert_response :success
    assert_equal [ "spike_status_tool" ], response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }
  end

  test "remote request cannot reach the mounted MCP transport" do
    host! "hearth.example"
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
      headers: {
        "REMOTE_ADDR" => "203.0.113.10",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }

    assert_response :not_found
  end

  test "production routes do not include the spike endpoint" do
    output, error, status = Open3.capture3(
      { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1" },
      Rails.root.join("bin/rails").to_s,
      "routes",
      "--grep",
      "mcp"
    )

    assert status.success?, error
    assert_match(/No routes were found/, output)
  end
end
