require "json"
require "net/http"
require "uri"

module HearthMcp
  class SpikeStdioProxy
    DEFAULT_MAX_LINE_BYTES = 4 * 1024 * 1024

    def initialize(url: ENV.fetch("HEARTH_MCP_URL", "http://127.0.0.1:3000/mcp"), input: $stdin, output: $stdout, max_line_bytes: DEFAULT_MAX_LINE_BYTES)
      @uri = URI(url)
      raise ArgumentError, "spike proxy requires a loopback HTTP URL" unless @uri.is_a?(URI::HTTP) && loopback_host?

      @input = input
      @output = output
      @max_line_bytes = max_line_bytes
    end

    def run
      while (line = @input.gets(@max_line_bytes + 1))
        raise ArgumentError, "MCP frame exceeds #{@max_line_bytes} bytes" unless line.end_with?("\n")

        call(JSON.parse(line)).each do |message|
          @output.puts(JSON.generate(message))
          @output.flush
        end
      end
    end

    def call(message)
      relay(JSON.generate(message)).map { |payload| JSON.parse(payload) }
    end

    private
      def loopback_host?
        %w[127.0.0.1 ::1 localhost].include?(@uri.host)
      end

      def relay(payload)
        request = Net::HTTP::Post.new(@uri)
        request["Accept"] = "application/json, text/event-stream"
        request["Content-Type"] = "application/json"
        request.body = payload

        response = Net::HTTP.start(
          @uri.hostname,
          @uri.port,
          use_ssl: @uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 30
        ) { |http| http.request(request) }

        return [] if response.code == "202"
        raise "Hearth MCP returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        if response["content-type"]&.include?("text/event-stream")
          response.body.each_line.filter_map do |line|
            data = line.delete_prefix("data: ").strip
            data unless data.empty?
          end
        else
          [ response.body ]
        end
      end
  end
end
