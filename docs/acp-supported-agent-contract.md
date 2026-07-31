# ACP supported-agent contract

Status: executable architecture spike, observed 2026-07-30.

This contract is the handoff from ticket 01 to the production implementations in tickets 03 and 04. It proves two real development paths:

1. `bin/hearth-acp-spike` owns an ACP agent subprocess over ordinary stdin/stdout pipes.
2. Rails mounts an official, stateless Streamable HTTP MCP transport at loopback-only `/mcp`.

It does not add a product UI, a `hearth serve` command, production agent recovery, production MCP authorization, or a production MCP route.

## Boundary decision

ACP is the UI-to-agent boundary. MCP is the agent-to-Hearth/Lorester tool boundary.

The first production ACP runtime should be a Hearth-owned Ruby pipe supervisor, run as an operating-system sibling of Puma and eventually supervised by the packaged `hearth serve` launcher. It must not run from a controller, Rails executor, job, Puma plugin, or Solid Queue, and it does not require a separately routed `botster-core` worker.

The process proof recorded in `docs/acp-evidence/process-boundary.jsonl` shows:

- the fake agent is a direct child of the standalone spike supervisor;
- the agent is not a child of Puma;
- the same supervisor/agent pair remains alive while Puma stops and restarts;
- non-MCP ACP traffic succeeds after that restart; and
- stopping the supervisor leaves no agent process.

Ticket 03 owns the production supervisor, concurrent sessions, bounded queues, persistent recovery, launcher integration, and `.hearth` state. It replaces `Acp::Probe` rather than maintaining two production clients.

## Required ACP v1 behavior

A supported agent:

- speaks UTF-8 newline-delimited JSON-RPC 2.0 on non-TTY stdin/stdout;
- writes logs only to stderr;
- agrees on protocol version 1;
- supports `session/new`, `session/prompt`, `session/update`, and `session/cancel`;
- treats omitted capabilities as unsupported;
- accepts the same negotiated `mcpServers` configuration on new, load, and resume;
- allows the client to deny `session/request_permission` without deadlock;
- correlates request IDs while allowing streamed notifications and agent-to-client requests;
- returns bounded errors for malformed frames, oversized frames, timeouts, and early exit; and
- releases its process tree when the supervising client exits.

`session/load`, `session/resume`, `session/close`, HTTP MCP, images, and embedded resources are capability-gated. The protocol core branches on negotiated capabilities, never provider identity.

## Content contract

Text is always allowed. Resource links are part of the ACP baseline but are not exercised by this spike.

Embedded text resources are sent only when `promptCapabilities.embeddedContext` is true. Images are sent only when `promptCapabilities.image` is true. The automated peer receives real content sourced from `attachment.txt` and `attachment.png`; unsupported content is rejected before `session/prompt` is written.

Live Grok accepted the embedded resource. It advertised images as unsupported, so no live image request was sent.

## MCP contract

Hearth's canonical tool boundary is the official `mcp` Ruby gem's stateless `MCP::Server::Transports::StreamableHTTPTransport`.

For this spike:

- the endpoint is mounted only when `Rails.env.local?`;
- a Rails local-request constraint rejects non-loopback callers;
- production route recognition proves `/mcp` is absent;
- the loopback URL defaults to `http://127.0.0.1:3000/mcp` and is overridden explicitly with `HEARTH_MCP_URL` or `--mcp-url`;
- an HTTP-capable agent receives `{type: "http", name: "hearth-spike", url: ..., headers: []}`;
- an agent without HTTP capability receives the absolute `bin/hearth-mcp-spike-proxy` command, empty args, and the same URL in its environment; and
- the stdio proxy owns no tools or domain policy. It only relays JSON-RPC to Rails.

The sole spike tool executes `SELECT 1` through Active Record and returns only `{"database":"reachable"}`. It exposes no household records.

Ticket 04 replaces the spike server and proxy with the authenticated production `Agent::Grant` endpoint and complete typed tool catalog. The local unauthenticated code must not be extended into production.

## Compatibility matrix

| Agent path | Install/auth | Session + stream | Permission | MCP HTTP | MCP stdio | Text resource | Image | Cancel/failure | Close | Load/resume |
|---|---|---|---|---|---|---|---|---|---|---|
| Fake ACP peer | observed | observed | deny observed | observed config | observed config and proxy E2E | observed | observed | observed | observed | observed |
| Grok Build 0.2.112 native | installed; existing local auth observed | observed | no live request; deny policy active | initialize/list/call observed through Rails | unsupported path not selected because HTTP is advertised | observed | unsupported by capability | automated protocol proof; live failure not induced | unsupported | load observed; resume unsupported |
| Codex ACP adapter | unavailable locally | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred |
| Claude ACP adapter | unavailable locally | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred |

Codex CLI 0.146.0 and Claude Code 2.1.220 are installed as CLIs, but no `codex-acp` or `claude-agent-acp` executable is installed. Their registered Botster agent choices do not supply a local ACP adapter executable to this probe, so adapter cells are explicitly deferred rather than inferred from the non-ACP CLIs.

HTTP and stdio are separate columns intentionally: an agent advertising HTTP does not prove the fallback executable.

## Evidence and privacy

Machine-readable summaries live in `docs/acp-evidence/*.jsonl`. They contain no credentials, authorization headers, raw prompts, raw tool payloads, session IDs, household data, or developer home paths.

The spike writes its result to stdout. Callers that persist additional evidence must apply the same allow-list policy; stderr is diagnostic only and must not be copied wholesale.

## Primary references

- [ACP v1 initialization and capability negotiation](https://agentclientprotocol.com/protocol/v1/initialization)
- [ACP v1 session setup and MCP server shapes](https://agentclientprotocol.com/protocol/v1/session-setup)
- [ACP v1 prompt lifecycle and cancellation](https://agentclientprotocol.com/protocol/v1/prompt-turn)
- [ACP v1 content blocks](https://agentclientprotocol.com/protocol/v1/content)
- [ACP v1 stdio transport](https://agentclientprotocol.com/protocol/v1/transports)
- [Official MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk)
