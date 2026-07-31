# ACP supported-agent contract

Status: production ACP runtime implemented; MCP endpoint remains conformance-only.

This contract records two deliberately separate paths:

1. `bin/hearth-acp-runtime` supervises configured ACP agents over ordinary stdin/stdout pipes, persists recovery truth, and runs as an operating-system sibling of Puma.
2. Rails still mounts the ticket-01 stateless Streamable HTTP MCP transport at loopback-only `/mcp` as quarantined conformance scaffolding for ticket 04.

The runtime does not add product UI, `hearth serve`, automatic installation/update,
or a production MCP route. Its `mcpServers` default is exactly `[]`; after
transport recovery, a session is connected but MCP-inert until an authenticated
browser flow issues a fresh grant.

## Running the production ACP host

The selected directory must already contain `.hearth/instance.yml`. Missing
markers fail before Rails boots and write nothing. A source checkout is not
initialized implicitly, and `Procfile.dev` is intentionally unchanged.

```sh
bin/hearth-acp-runtime \
  --root /path/to/initialized-instance \
  --conversation CONVERSATION_ID \
  --auth-method cached_token
```

`Agent::Profile` supplies a single executable plus JSON argv, a working directory
contained by the instance root, an environment-name allowlist, and manual update
policy. The runtime never evaluates a shell command. To recover a persisted
session:

```sh
bin/hearth-acp-runtime \
  --root /path/to/initialized-instance \
  --session AGENT_SESSION_ID \
  --auth-method cached_token \
  --prompt 'Reply HEARTH_ACP_RECOVERED_OK.' \
  --evidence /tmp/hearth-acp-runtime.jsonl \
  --once
```

The evidence is explicitly ACP-only. It records no prompt, session ID, headers,
environment values, household data, or developer path.

## Reproducing the process and database boundaries

The automated production-entry campaign starts Puma with
`SOLID_QUEUE_IN_PUMA=true`, holds a fake ACP child under the standalone runtime,
proves the child's parent is the runtime rather than Puma, stops and restarts
Puma, completes a prompt, and checks the exact child PID is absent. It also runs
a real second Rails process holding a SQLite write transaction while runtime
shutdown persists its lifecycle transition:

```sh
bin/rails test test/integration/acp_runtime_test.rb
```

Rails 8.1 applies `timeout: 5000` through sqlite3-ruby's GVL-releasing busy
handler. Therefore `PRAGMA busy_timeout` remains `0`; the regression records
both the pragma and configured timeout, then proves the concurrent write path
completes without `SQLite3::BusyException`.

The ticket-01 stdio MCP fallback remains reproducible, but the ACP runtime never
references it:

```sh
HEARTH_MCP_URL=http://127.0.0.1:3411/mcp \
  bin/hearth-mcp-spike-proxy < test/fixtures/files/acp/mcp_requests.jsonl
```

## Boundary decision

ACP is the UI-to-agent boundary. MCP is the agent-to-Hearth/Lorester tool boundary.

The production ACP runtime is a Hearth-owned Ruby pipe supervisor, run as an operating-system sibling of Puma and eventually supervised by the packaged `hearth serve` launcher. It does not run from a controller, Rails executor, job, Puma plugin, or Solid Queue, and it does not require a separately routed `botster-core` worker.

The process proof recorded in `docs/acp-evidence/process-boundary.jsonl` shows:

- the fake agent is a direct child of the standalone ACP proof supervisor;
- the agent is not a child of Puma;
- the same supervisor/agent pair remains alive while Puma stops and restarts;
- non-MCP ACP traffic succeeds after that restart; and
- stopping the supervisor leaves no agent process.

Ticket 03 owns the production supervisor, concurrent sessions, bounded queues,
persistent recovery, standalone entry, and `.hearth/tmp/acp` transient state.
`Acp::Probe` and `bin/hearth-acp-spike` were cold-replaced, leaving one ACP
client. Ticket 09 owns `hearth serve`/Tebako supervision.

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
- retains the latest 128 streamed notifications per connection, counts older
  notifications dropped from that diagnostic buffer, and never disconnects an
  otherwise healthy turn merely because the diagnostic consumer is slower;
- returns bounded errors for malformed frames, oversized frames, timeouts, and early exit; and
- releases its process tree when the supervising client exits.

`session/list`, `session/load`, `session/resume`, `session/close`, HTTP MCP, images, and embedded resources are capability-gated. The protocol core branches on negotiated capabilities, never provider identity. `session/list` is discovery rather than restoration, but it is recovery-relevant and must be observed separately.

ACP protocol version 1 is the current stable wire contract and is pinned deliberately by the initialize request and response check. Draft ACP v2 work reorganizes agent capabilities beneath `capabilities.session`, moves agent identity to `info`, and removes the v1 optional `list`/`resume`/`close` capability fields; the hard version check is the intended migration seam if that draft stabilizes.

## Content contract

Text is always allowed. Resource links are part of the ACP baseline but are not
exercised by the production runtime proof.

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

After successful MCP initialization, live Grok requested `/mcp`, `/.well-known/oauth-protected-resource/mcp`, `/mcp/.well-known/oauth-protected-resource`, `/.well-known/oauth-protected-resource`, `/.well-known/oauth-authorization-server`, `/.well-known/oauth-authorization-server/mcp`, `/.well-known/openid-configuration/mcp`, and `/mcp/.well-known/openid-configuration`. The unauthenticated spike returned 404 for every discovery request. Ticket 04 must decide and test the authenticated endpoint's discovery metadata rather than assuming successful tool calls prove authentication negotiation.

## Compatibility matrix

| Agent path | Install/auth | Session + stream | Session list | Permission | MCP HTTP | MCP stdio | Text resource | Image | Cancel/failure | Close | Load/resume |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Fake ACP peer | observed | observed | observed | deny observed | observed config | observed config and proxy E2E | observed | observed | observed | observed | observed |
| Grok Build 0.2.117 native | installed; `cached_token` authenticate observed | production runtime new + recovered prompt observed | observed | no live request; deny policy active | not injected (`mcpServers=[]`) | not injected | historical spike-only observation | unsupported by capability | automated protocol proof; live failure not induced | unsupported | load observed through production runtime; resume unsupported |
| Codex ACP adapter | unavailable locally | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred |
| Claude ACP adapter | unavailable locally | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred |

Codex CLI 0.146.0 and Claude Code 2.1.220 are installed as CLIs, but no `codex-acp` or `claude-agent-acp` executable is installed. Their registered Botster agent choices do not supply a local ACP adapter executable to this probe, so adapter cells are explicitly deferred rather than inferred from the non-ACP CLIs.

HTTP and stdio are separate columns intentionally: an agent advertising HTTP does not prove the fallback executable.

## Evidence and privacy

Machine-readable summaries live in `docs/acp-evidence/*.jsonl`.
`runtime-live-agent.jsonl` was emitted directly by `bin/hearth-acp-runtime` and
records the 0.2.117 new/load proof with `mcpServers=[]`; exact recorded agent
PIDs were absent after both runs. The older `live-agents.jsonl` and
`process-boundary.jsonl` remain dated ticket-01 history generated by commits
`8f3e9d6e9f5844c18c6a92f524491634df695e0a` and its ancestors. Their MCP
tool-call evidence is historical and is not attributed to the production
runtime.

`bin/hearth-acp-runtime` writes the same sanitized result to stdout and to the
optional JSONL evidence path. Its result narrows agent identity and negotiated
capabilities to the fields consumed by this contract; it contains no
credentials, authorization headers, raw prompts, raw tool payloads, session
IDs, household data, developer home paths, or agent-controlled `_meta`. Stderr
is diagnostic only and must not be copied wholesale.

## Primary references

- [ACP v1 initialization and capability negotiation](https://agentclientprotocol.com/protocol/v1/initialization)
- [ACP v1 session setup and MCP server shapes](https://agentclientprotocol.com/protocol/v1/session-setup)
- [ACP v1 prompt lifecycle and cancellation](https://agentclientprotocol.com/protocol/v1/prompt-turn)
- [ACP v1 content blocks](https://agentclientprotocol.com/protocol/v1/content)
- [ACP v1 stdio transport](https://agentclientprotocol.com/protocol/v1/transports)
- [Official MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk)
