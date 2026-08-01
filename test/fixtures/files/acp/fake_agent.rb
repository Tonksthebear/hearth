#!/usr/bin/env ruby

require "json"
require "rbconfig"

abort "ACP must use ordinary pipes" if $stdin.tty? || $stdout.tty?

$stderr.puts("fake-agent stderr remains separate")
$stderr.flush

mode = ENV.fetch("FAKE_ACP_MODE", "normal")
session_id = ENV.fetch("FAKE_SESSION_ID", "fake-session")
prompt_id = nil
permission_id = 900
expected_mcp_servers = nil
pending_lists = []
descendant_pid = nil
permission_flood_responses = []

if ENV["FAKE_AGENT_INFO_FILE"]
  File.write(ENV["FAKE_AGENT_INFO_FILE"], JSON.generate(pid: Process.pid, ppid: Process.ppid))
end

if mode == "descendant"
  descendant_pid = spawn(
    RbConfig.ruby,
    "-e",
    "trap('TERM') {}; loop { sleep 1 }",
    pgroup: false
  )
  File.write(ENV.fetch("FAKE_DESCENDANT_PID_FILE"), descendant_pid)
end

write = lambda do |message|
  $stdout.puts(JSON.generate(message))
  $stdout.flush
end

loop do
  line = $stdin.gets
  break unless line
  message = JSON.parse(line)

  if mode == "permission_flood" && message["id"].to_i.between?(900, 905) && message["result"]
    permission_flood_responses << message["result"]
    if permission_flood_responses.length == 6
      overflow = permission_flood_responses.count { |result| result.dig("_meta", "hearth", "code") == "request_capacity_exceeded" }
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "overflow=#{overflow}" } }
      })
      write.call(jsonrpc: "2.0", id: prompt_id, result: { stopReason: "end_turn" })
      prompt_id = nil
    end
    next
  end

  if message["id"] == permission_id && message["result"]
    outcome = message.dig("result", "outcome")
    expected_option = mode == "permission_allow" ? "allow" : "reject"
    abort "permission selected the wrong option" unless outcome == { "outcome" => "selected", "optionId" => expected_option }
    chunks = mode == "streaming" ? 300.times.map(&:to_s) : %w[HEARTH_ ACP_OK]
    chunks.each do |text|
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", messageId: "message-1", content: { type: "text", text: text } }
      })
    end
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
    when "invalid_utf8"
      $stdout.write("\xFF\n")
      $stdout.flush
      next
    when "partial"
      $stdout.write('{"jsonrpc":"2.0"')
      $stdout.flush
      exit 0
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
        loadSession: !%w[no_recovery resume_only].include?(mode),
        promptCapabilities: {
          image: mode != "no_attachments",
          embeddedContext: mode != "no_attachments"
        },
        mcpCapabilities: { http: mode != "stdio" },
        sessionCapabilities: {
          list: mode == "no_list" ? nil : {},
          resume: %w[load_only no_recovery].include?(mode) ? nil : {},
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
    if mode == "duplicate_id"
      write.call(jsonrpc: "2.0", id: message["id"], result: {})
    elsif mode == "backpressure"
      20.times do |index|
        write.call(jsonrpc: "2.0", method: "session/update", params: {
          sessionId: session_id,
          update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: index.to_s } }
        })
      end
    elsif mode == "stderr_flood"
      $stderr.write("noise" * 100_000)
      $stderr.flush
    end
  when "authenticate"
    abort "unexpected auth method" unless message.dig("params", "methodId") == "fake-auth"
    write.call(jsonrpc: "2.0", id: message["id"], result: {})
  when "session/new"
    expected_mcp_servers = message.dig("params", "mcpServers")
    result = mode == "missing_session_id" ? {} : { sessionId: session_id }
    write.call(jsonrpc: "2.0", id: message["id"], result: result)
  when "session/prompt"
    exit 12 if mode == "crash_prompt"
    sleep 60 if mode == "hang_prompt"
    prompt_id = message["id"]
    prompt = message.dig("params", "prompt")
    abort "unsupported attachment was written" if mode == "no_attachments" && prompt.any? { |block| %w[image resource].include?(block["type"]) }
    if mode == "chat_stream"
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", messageId: "live-message", content: { type: "text", text: "**Recorded fact:** " }, _meta: { hearth: { sourceKind: "hearth_fact" } } }
      })
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "tool_call", toolCallId: "live-tool", title: "Review weekly records", kind: "search", status: "in_progress", rawInput: { private: "digest-only" } }
      })
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "plan", entries: [ { content: "Review the week", status: "completed" }, { content: "Suggest next steps", status: "pending" } ] }
      })
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "citation", id: "live-citation", title: "Hearth weekly record", sourceKind: "hearth_fact" }
      })
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", messageId: "live-message", content: { type: "text", text: "streamed safely." }, _meta: { hearth: { sourceKind: "hearth_fact" } } }
      })
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "tool_call_update", toolCallId: "live-tool", status: "completed", rawOutput: { result: "redacted" } }
      })
      write.call(jsonrpc: "2.0", id: prompt_id, result: { stopReason: "end_turn" })
      prompt_id = nil
    elsif mode == "permission_flood"
      6.times do |index|
        write.call(jsonrpc: "2.0", id: 900 + index, method: "session/request_permission", params: {
          sessionId: session_id,
          toolCall: { toolCallId: "flood-#{index}" },
          options: [ { optionId: "reject", name: "Reject", kind: "reject_once" } ]
        })
      end
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "flood-dispatched" } }
      })
    elsif mode == "cancel"
      write.call(jsonrpc: "2.0", method: "session/update", params: {
        sessionId: session_id,
        update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "started" } }
      })
    else
      while ENV["FAKE_PERMISSION_RELEASE_FILE"] && !File.exist?(ENV["FAKE_PERMISSION_RELEASE_FILE"])
        sleep 0.02
      end
      tool_call = { toolCallId: "fake-tool" }
      if mode == "permission_allow"
        tool_call[:title] = ENV.fetch("FAKE_PERMISSION_OPERATION")
        tool_call[:rawInput] = JSON.parse(ENV.fetch("FAKE_PERMISSION_INPUT"))
      end
      write.call(jsonrpc: "2.0", id: permission_id, method: "session/request_permission", params: {
        sessionId: session_id,
        toolCall: tool_call,
        options: [ { optionId: "allow", name: "Allow", kind: "allow_once" }, { optionId: "reject", name: "Reject", kind: "reject_once" } ]
      })
    end
  when "session/cancel"
    write.call(jsonrpc: "2.0", id: prompt_id, result: { stopReason: "cancelled" }) if prompt_id
    prompt_id = nil
  when "session/list"
    if mode == "out_of_order"
      pending_lists << message
      if pending_lists.length == 2
        pending_lists.reverse_each do |pending|
          write.call(jsonrpc: "2.0", id: pending["id"], result: {
            sessions: [ { sessionId: session_id, cursor: pending.dig("params", "cursor") } ]
          })
        end
      end
    else
      write.call(jsonrpc: "2.0", id: message["id"], result: {
        sessions: [ { sessionId: session_id, cwd: message.dig("params", "cwd") || Dir.pwd } ]
      })
    end
  when "session/resume", "session/load"
    expected_mcp_servers ||= message.dig("params", "mcpServers")
    abort "MCP configuration changed across lifecycle" unless message.dig("params", "mcpServers") == expected_mcp_servers
    rejected = (message["method"] == "session/resume" && mode == "reject_resume") ||
      (message["method"] == "session/load" && mode == "reject_load")
    if rejected
      write.call(jsonrpc: "2.0", id: message["id"], error: { code: -32000, message: "recovery rejected" })
    else
      write.call(jsonrpc: "2.0", id: message["id"], result: {})
    end
  when "session/close"
    write.call(jsonrpc: "2.0", id: message["id"], result: {})
  else
    write.call(jsonrpc: "2.0", id: message["id"], error: { code: -32601, message: "unsupported" }) if message["id"]
  end
end
