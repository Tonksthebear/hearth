require "test_helper"
require "socket"
require "stringio"

class HearthMcp::StdioProxyTest < ActiveSupport::TestCase
  test "relays newline JSON and bearer to loopback HTTP without domain logic" do
    requests = Queue.new
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      headers = +""
      headers << socket.gets until headers.end_with?("\r\n\r\n")
      content_length = headers[/Content-Length: (\d+)/i, 1].to_i
      requests << [ headers, JSON.parse(socket.read(content_length)) ]
      body = JSON.generate(jsonrpc: "2.0", id: 1, result: { tools: [] })
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end

    input = StringIO.new(%({"jsonrpc":"2.0","id":1,"method":"tools/list"}\n))
    output = StringIO.new
    url = "http://127.0.0.1:#{server.local_address.ip_port}/mcp"
    proxy = HearthMcp::StdioProxy.new(url: url, bearer: "sentinel", input: input, output: output)
    proxy.run

    headers, message = requests.pop
    assert_match(/Authorization: Bearer sentinel/i, headers)
    assert_equal "tools/list", message["method"]
    assert_equal({ "jsonrpc" => "2.0", "id" => 1, "result" => { "tools" => [] } }, JSON.parse(output.string))
    assert_equal "#<HearthMcp::StdioProxy [REDACTED]>", proxy.inspect
  ensure
    server&.close
    thread&.join
  end

  test "rejects non-loopback upstreams missing credentials partial and oversized frames" do
    assert_raises(ArgumentError) { HearthMcp::StdioProxy.new(url: "https://example.com/mcp", bearer: "x") }
    assert_raises(ArgumentError) { HearthMcp::StdioProxy.new(url: "http://127.0.0.1/mcp", bearer: "") }

    oversized = HearthMcp::StdioProxy.new(
      url: "http://127.0.0.1/mcp", bearer: "x",
      input: StringIO.new("x" * 20), output: StringIO.new, max_line_bytes: 10
    )
    assert_raises(ArgumentError) { oversized.run }

    partial = HearthMcp::StdioProxy.new(
      url: "http://127.0.0.1/mcp", bearer: "x",
      input: StringIO.new("{}"), output: StringIO.new
    )
    assert_raises(ArgumentError) { partial.run }
  end
end
