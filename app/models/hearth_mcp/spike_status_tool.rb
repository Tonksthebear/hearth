require "mcp"

module HearthMcp
  class SpikeStatusTool < MCP::Tool
    description "Proves that the local-only Hearth MCP spike can reach the Rails database"
    input_schema(properties: {}, required: [])

    class << self
      def call(server_context:)
        ActiveRecord::Base.connection.select_value("SELECT 1")
        MCP::Tool::Response.new([ { type: "text", text: '{"database":"reachable"}' } ])
      end
    end
  end
end
