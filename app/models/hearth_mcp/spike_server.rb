require "mcp"

module HearthMcp
  class SpikeServer
    class << self
      def transport
        @transport ||= MCP::Server::Transports::StreamableHTTPTransport.new(
          MCP::Server.new(
            name: "hearth-local-spike",
            title: "Hearth Local MCP Spike",
            version: "0.1.0",
            instructions: "Architecture proof only. This endpoint is absent in production.",
            tools: [ SpikeStatusTool ]
          ),
          stateless: true,
          enable_json_response: true
        )
      end
    end
  end
end
