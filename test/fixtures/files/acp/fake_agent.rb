#!/usr/bin/env ruby

require "json"

abort "ACP must use ordinary pipes" if $stdin.tty? || $stdout.tty?

$stderr.puts("fake-agent stderr remains separate")
$stderr.flush

mode = ENV.fetch("FAKE_ACP_MODE", "normal")
session_id = "fake-session"
prompt_id = nil
permission_id = 900
expected_mcp_servers = nil

write = lambda do |message|
  $stdout.puts(JSON.generate(message))
  $stdout.flush
end

loop do
  line = $stdin.gets
  break unless line
  message = JSON.parse(line)

  if message["id"] == permission_id && message["result"]
    outcome = message.dig("result", "outcome")
    abort "permission was not denied" unless outcome == { "outcome" => "selected", "optionId" => "reject" }
    write.call(jsonrpc: "2.0", method: "session/update", params: {
      sessionId: session_id,
      update: { sessionUpdate: "agent_message_chunk", messageId: "message-1", content: { type: "text", text: "HEARTH_" } }
    })
    write.call(jsonrpc: "2.0", method: "session/update", params: {
      sessionId: session_id,
      update: { sessionUpdate: "agent_message_chunk", messageId: "message-1", content: { type: "text", text: "ACP_OK" } }
    })
    write.call(jsonrpc: "2.0", id: prompt_id, result: { stopReason: "end_turn" })
    prompt_id = nil
    next
  end

  case message["method"]
  when "initialize"
    case mode
    when "malformed"
      $stdout.puts("{not-json")
      $stdout.flush
      next
    when "oversized"
      $stdout.write("x" * 4096)
      $stdout.flush
      next
    when "unknown_id"
      write.call(jsonrpc: "2.0", id: 123_456, result: {})
      next
    when "early_exit"
      exit 0
    when "hang"
      sleep 60
    end

    write.call(jsonrpc: "2.0", id: message["id"], result: {
      protocolVersion: 1,
      agentCapabilities: {
        loadSession: true,
        promptCapabilities: {
          image: mode != "no_attachments",
          embeddedContext: mode != "no_attachments"
        },
        mcpCapabilities: { http: mode != "stdio" },
        sessionCapabilities: {
          list: mode == "no_list" ? nil : {},
          resume: {},
          close: {}
        }.compact
      },
      agentInfo: {
        name: "fake-agent",
        version: "1.0.0",
        pid: Process.pid,
        ppid: Process.ppid
      },
      authMethods: mode == "auth" ? [
        { id: "other-auth", name: "Other authentication" },
        { id: "fake-auth", name: "Fake authentication" }
      ] : [],
      _meta: mode == "auth" ? { defaultAuthMethodId: "fake-auth" } : {}
    })
  when "authenticate"
    abort "unexpected auth method" unless message.dig("params", "methodId") == "fake-auth"
    write.call(jsonrpc: "2.0", id: message["id"], result: {})
  when "session/new"
    expected_mcp_servers = message.dig("params", "mcpServers")
    write.call(jsonrpc: "2.0", id: message["id"], result: { sessionId: session_id })
  when "session/prompt"
    prompt_id = message["id"]
    prompt = message.dig("params", "prompt")
    abort "unsupported attachment was written" if mode == "no_attachments" && prompt.any? { |block| %w[image resource].include?(block["type"]) }
    if mode == "cancel"
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "started" } }
      })
    else
      write.call(jsonrpc: "2.0", id: permission_id, method: "session/request_permission", params: {
        sessionId: session_id,
        toolCall: { toolCallId: "fake-tool" },
        options: [ { optionId: "allow", name: "Allow", kind: "allow_once" }, { optionId: "reject", name: "Reject", kind: "reject_once" } ]
      })
    end
  when "session/cancel"
    write.call(jsonrpc: "2.0", id: prompt_id, result: { stopReason: "cancelled" }) if prompt_id
    prompt_id = nil
  when "session/list"
    write.call(jsonrpc: "2.0", id: message["id"], result: {
      sessions: [ { sessionId: session_id, cwd: message.dig("params", "cwd") || Dir.pwd } ]
    })
  when "session/resume", "session/load"
    abort "MCP configuration changed across lifecycle" unless message.dig("params", "mcpServers") == expected_mcp_servers
    write.call(jsonrpc: "2.0", id: message["id"], result: {})
  when "session/close"
    write.call(jsonrpc: "2.0", id: message["id"], result: {})
  else
    write.call(jsonrpc: "2.0", id: message["id"], error: { code: -32601, message: "unsupported" }) if message["id"]
  end
end
