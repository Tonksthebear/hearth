require "test_helper"
require "socket"
require "stringio"

class HearthMcp::SpikeStdioProxyTest < ActiveSupport::TestCase
  test "relays newline JSON to loopback HTTP without owning tool definitions" do
    requests = Queue.new
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      headers = +""
      headers << socket.gets until headers.end_with?("\r\n\r\n")
      content_length = headers[/Content-Length: (\d+)/i, 1].to_i
      requests << JSON.parse(socket.read(content_length))
      body = JSON.generate(jsonrpc: "2.0", id: 1, result: { tools: [] })
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end

    input = StringIO.new(%({"jsonrpc":"2.0","id":1,"method":"tools/list"}\n))
    output = StringIO.new
    url = "http://127.0.0.1:#{server.local_address.ip_port}/mcp"
    HearthMcp::SpikeStdioProxy.new(url: url, input: input, output: output).run

    assert_equal "tools/list", requests.pop["method"]
    assert_equal({ "jsonrpc" => "2.0", "id" => 1, "result" => { "tools" => [] } }, JSON.parse(output.string))
  ensure
    server&.close
    thread&.join
  end

  test "rejects non-loopback upstreams and oversized frames" do
    assert_raises(ArgumentError) { HearthMcp::SpikeStdioProxy.new(url: "https://example.com/mcp") }

    proxy = HearthMcp::SpikeStdioProxy.new(
      input: StringIO.new("x" * 20),
      output: StringIO.new,
      max_line_bytes: 10
    )
    assert_raises(ArgumentError) { proxy.run }
  end
end
