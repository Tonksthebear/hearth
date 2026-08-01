# ACP supported-agent contract

Status: production ACP runtime and authenticated guarded MCP operations implemented.

This contract records two deliberately separate paths:

1. `bin/hearth-acp-runtime` supervises configured ACP agents over ordinary stdin/stdout pipes, persists recovery truth, and runs as an operating-system sibling of Puma.
2. Rails serves the canonical stateless Streamable HTTP MCP transport at loopback-only `POST /mcp`, authenticated on every request by a short-lived `Agent::Grant`.

The runtime does not add product UI, `hearth serve`, automatic installation/update,
or automatic installation/update. Before the first `session/new`, Hearth persists
an initializing local `Agent::Session`, issues a server-owned runtime grant from
that persisted conversation/session context, and injects authorized `mcpServers`.
The returned external ACP session ID is then bound once. Initialization failures
retain the failed local row, revoke the grant, audit the failure, and stop the child.
Recovery rotates the credential and injects fresh configuration for load/resume.

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

The bounded stdio fallback relays to the same authenticated endpoint and owns no
catalog or domain behavior:

```sh
HEARTH_MCP_URL=http://127.0.0.1:3411/mcp \
  HEARTH_MCP_BEARER=REDACTED \
  bin/hearth-mcp-proxy < test/fixtures/files/acp/mcp_requests.jsonl
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

Hearth's guarded operational mutations use a bounded proposal-first ACP contract.
For a consequential write, the agent first calls the complete typed MCP tool. That
call validates the exact person/context and input, reserves one call from the
current grant, creates a durable no-op `MutationProposal` and `PermissionRequest`,
and returns `status: pending`, a proposal ID, the earliest deadline, and an explicit
next action. It does not change household health data.

The agent may then send `session/request_permission` with:

- `toolCall.title` equal to the exact Hearth MCP operation name;
- `toolCall.rawInput` equal to the staged tool input, including the same
  `idempotency_key`; and
- the same ACP session that owns the staged proposal.

Hearth accepts only an existing pending proposal whose household, person,
conversation, ACP session, operation, canonical input digest, staged grant,
deadline, and idempotency identity all still match. Permission handling runs off
the ACP stdout reader thread and waits on Action Cable pubsub, so other JSON-RPC
responses continue to dispatch and the supervisor does not poll the proposal row.
Production uses Solid Cable, which carries that notification across the web and
runtime processes. The test adapter proves the notification path in-process only;
the standalone multi-process test proves the bounded deadline/reload fallback and
correct result, not cross-process notification latency. Development's async adapter
has the same fallback when the runtime is a separate process.

ACP v1 permits permission-first requests and does not require `rawInput`, but those
generic requests cannot safely identify a typed Hearth mutation. Missing input,
missing keys, unknown operations, unstaged keys, and correlation mismatches are
therefore rejected once with stable `_meta.hearth.code` and message fields. They
create no generic proposal and retain no untrusted raw payload. A repeated typed
MCP staging call with the same session-scoped key and canonical input returns the
same pending or terminal proposal; reusing the key with different input fails
closed.

`session/list`, `session/load`, `session/resume`, `session/close`, HTTP MCP, images, and embedded resources are capability-gated. The protocol core branches on negotiated capabilities, never provider identity. `session/list` is discovery rather than restoration, but it is recovery-relevant and must be observed separately.

ACP protocol version 1 is the current stable wire contract and is pinned deliberately by the initialize request and response check. Draft ACP v2 work reorganizes agent capabilities beneath `capabilities.session`, moves agent identity to `info`, and removes the v1 optional `list`/`resume`/`close` capability fields; the hard version check is the intended migration seam if that draft stabilizes.

## Content contract

Text is always allowed. Resource links are part of the ACP baseline but are not
exercised by the production runtime proof.

Embedded text resources are sent only when `promptCapabilities.embeddedContext` is true. Images are sent only when `promptCapabilities.image` is true. The automated peer receives real content sourced from `attachment.txt` and `attachment.png`; unsupported content is rejected before `session/prompt` is written.

Live Grok accepted the embedded resource. It advertised images as unsupported, so no live image request was sent.

## MCP contract

Hearth's canonical tool boundary is the official `mcp` Ruby gem's stateless `MCP::Server::Transports::StreamableHTTPTransport`.

The endpoint exists in every environment but rejects non-loopback addresses before
dispatch, uses the official SDK's Host/Origin DNS-rebinding checks, and requires a
valid bearer on every independent POST. It constructs a fresh stateless server,
transport, and grant-filtered registry per request. `health_read` exposes the exact
read catalog. `health_write` is present only after an authenticated same-household user
enables operational access for the exact conversation, selected person, ACP session,
and browser session. Recovery issues a fresh digest-only grant; a session without an
active exact-context authorization remains read-only.
The injected runtime grant expires after 15 minutes or 200 calls and carries a
200,000-token output budget. The first request after expiry or exhaustion changes the
persisted session to `reauthorization_required`; the operator recovers or restarts
that session to inject a fresh credential. The current ACP v1 configuration is
immutable after session selection, so an attached connection is not silently rotated
in place.

Every runtime grant also carries `knowledge_read` and `knowledge_submit`. The exact
grant-filtered dotted tools are `knowledge.search`, `knowledge.note.read`,
`knowledge.related`, `knowledge.inbox.submit`, `knowledge.inbox.status`, and
`knowledge.health.summary`. The first five read/status/summary surfaces require
`knowledge.read`; submit requires `knowledge.submit`. These names intentionally form
a separate Lorester namespace while the existing Hearth health catalog retains its
snake_case wire names.

Knowledge reads cross the same authenticated official-`mcp` endpoint into Lorester's
typed version-1 Unix-socket contract. Inputs are closed and path-free. Results retain
opaque note IDs, bounded text with explicit truncation, exact projection
`source_commit`, and `contract_version`; Hearth persists only the bounded provenance
allowlist plus digest-only tool bodies. `knowledge.health.summary` preserves Lorester's
`ready`, `unavailable`, `stale`, and `incompatible` projection states. Hearth adds
distinct `not_configured`, `stopped`, and transport `unavailable` states without
returning a vault root, socket path, subprocess diagnostics, or raw response.

All conversation-derived inbox submissions require a durable Hearth
`PermissionRequest`, regardless of ACP harness approval. The first submit call binds
the exact household/person/conversation/session/grant/message context, requested
intent, deterministic redacted content, digest, preview, and session-scoped idempotency
identity and makes zero Lorester calls. Only an approved committed decision dispatches
the allowlisted subject callback with its deciding household user. Denial,
cancellation, expiry, and late decisions never dispatch. Retry reuses the unchanged
Lorester request identity, so remote acceptance can be recovered without replaying a
permission decision or creating a second capture. Status polls are no faster than one
second. Lorester alone chooses and writes the inbox artifact and continues to own note
creation, linking, processing, verification, projections, health policy, and Git.

All tools publish strict closed input schemas, output schemas, descriptions, and
truthful read/write/destructive annotations. Results contain structured content plus JSON text fallback, stable IDs,
UTC dates/timestamps, explicit units where the domain defines them, provenance, hard
row/window/output bounds, and `hearth_database` origin. They delegate to Hearth's
models and POROs; there is no SQL, Active Record passthrough, generic query language,
controller access, filesystem resource, generic record/column mutation, or catalog mutation.

Write tools are operation-specific: meal plan/log aggregates, training aggregates and
completion, weekly dose targets, person-habit configuration, and habit check-ins. One
non-destructive aggregate may execute immediately after model validation. Deletes,
nested destruction, replacement/removal of attributed feedback, completed-session
edits, dose targets, and habit configuration require a durable `MutationProposal` plus ACP
`PermissionRequest`. Hearth renders the exact person, graph effect, and earliest
deadline. Ambiguous-person and independent-root bulk requests are rejected by the
closed typed schemas rather than classified into a mutation lane. Staging reserves
grant call capacity; approval uses a one-time digest-stored token, rechecks the staged
grant and previewed state before commit, executes transactionally, and records requester,
approver, executor, operation, and complete before/after graph. Denial, cancellation,
timeout, revocation, scope drift, and stale state are terminal; late approval cannot
revive a proposal. Completed execution remains idempotently discoverable.

Meal writes preserve ordered 1-based `MealItem` rows and record `RecipeFeedback` only
when the user explicitly supplied it for an unambiguous recipe item. Feedback is never
inferred or strengthened. Removing or replacing existing feedback requires confirmation.
Logging an eligible explicit `PlannedMeal` delegates to `convert_for!`; a linked plan
scheduled in the future returns the stable error "A planned meal can only be logged
on or after its planned date." A linked plan cannot be unplanned until its meal is separately confirmed and unlogged. Completed
training sessions cannot be deleted.

The authenticated `agent_confirmation_center` is Ticket 05's minimal reusable Hotwire
seam. The future conversation UI must mount and reuse this authorization/proposal model
and Turbo target; it must not create a parallel confirmation or token path.

The endpoint is pre-authorized rather than an OAuth issuer. OAuth and OpenID discovery
paths remain absent (404); a configured valid bearer is the authentication contract.
HTTP-capable ACP agents receive the v1 HTTP shape with an Authorization header object.
All other v1 agents receive the absolute `bin/hearth-mcp-proxy` command and URL/bearer
only in ACP environment objects. Credentials never enter argv, tracked files, database
plaintext, evidence, or object inspection.

## Compatibility matrix

| Agent path | Install/auth | Session + stream | Session list | Permission | MCP HTTP | MCP stdio | Text resource | Image | Cancel/failure | Close | Load/resume |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Fake ACP peer | observed | observed | observed | deny observed | observed config | observed config and proxy E2E | observed | observed | observed | observed | observed |
| Grok Build 0.2.117 native | installed; `cached_token` authenticate observed | production runtime new + recovered prompt observed | observed | no live request; deny policy active | first-turn live proof observed: 8 read tools across meals/activity/training/habits/recovery, no DB/filesystem access | configuration + proxy E2E observed; live fallback not induced | historical spike-only observation | unsupported by capability | automated protocol proof; live failure not induced | unsupported | load observed; fresh MCP config implemented; resume unsupported |
| Codex ACP adapter | unavailable locally | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred |
| Claude ACP adapter | unavailable locally | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred | deferred |

Codex CLI 0.146.0 and Claude Code 2.1.220 are installed as CLIs, but no `codex-acp` or `claude-agent-acp` executable is installed. Their registered Botster agent choices do not supply a local ACP adapter executable to this probe, so adapter cells are explicitly deferred rather than inferred from the non-ACP CLIs.

HTTP and stdio are separate columns intentionally: an agent advertising HTTP does not prove the fallback executable.
If Grok 0.2.117 is unavailable or unauthenticated during verification, the live
acceptance check is escalated as a human question. The fake peer remains protocol
evidence and is never substituted for the required live-agent result.

## Evidence and privacy

Machine-readable summaries live in `docs/acp-evidence/*.jsonl`.
`runtime-live-agent.jsonl` was emitted directly by `bin/hearth-acp-runtime` and
records the earlier 0.2.117 new/load proof with `mcpServers=[]`; exact recorded agent
PIDs were absent after both runs. The older `live-agents.jsonl` and
`process-boundary.jsonl` remain dated ticket-01 history generated by commits
`8f3e9d6e9f5844c18c6a92f524491634df695e0a` and its ancestors. Their MCP
tool-call evidence is historical and is not attributed to the authenticated catalog.
New evidence reports only MCP server name, transport, and authenticated status—never
URLs, headers, environment values, raw tool arguments, or results. The ticket-04
Project Pipelines artifact additionally records Grok 0.2.117 pass/fail and sanitized
MCP tool names/statuses; fixture bodies and credentials were not committed.

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
