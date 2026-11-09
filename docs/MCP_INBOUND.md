# MCP inbound — what pt1 ships + what's deferred

Phase 6 of the plan file describes "MCP server" as one of the ship surfaces that lets Claude Desktop, Cursor, Zed, and any MCP-speaking client connect to a running `crossengin-chat` daemon. **This document is honest about what pt1 actually ships** and what's deferred to pt2+.

## The existing surface

`src/io/effectors/effector_mcp.nova` (50 lines, shipped under ADR-0054) is **not an MCP server**. It's an in-memory service → canned-response registry:

```nova
fn mcp_registry_new()
fn mcp_register(reg, service, response)
fn mcp_call(reg, service, method, request)      // (method, request) unused
fn mcp_call_direct(service, request, canned)
```

ADR-0054 explicitly states: *"A production connector speaks the MCP JSON protocol over a transport; here a service is bound to a canned response so the agent can be exercised end-to-end offline, and the transport is a documented seam."*

ADR-0054 also frames MCP as an **outbound** connector (CrossEngin calls out to external services), not as an inbound server (external clients call CrossEngin's exposed tools). The inbound direction has no ADR today.

## What Phase 6 pt1 ships

A thin `/mcp` chat command set that exposes the existing registry so an operator can inspect and extend it from the REPL:

| Command | Behaviour |
|---|---|
| `/mcp list` | Enumerate registered services (`service=... canned="..."`) + total count. |
| `/mcp register <service> <response>` | Upsert a canned response for a service name. |
| `/mcp call <service>` | Exercise `mcp_call` against the registry. Prints `ok=0/1 body="..."`. Debug surface only; no transport fires. |

Example session:

```
> /mcp list
mcp_services_registered=0
(registry empty -- /mcp register <service> <response>)

> /mcp register weather sunny-72F
registered: weather

> /mcp register news tech-headlines-x3
registered: news

> /mcp list
mcp_services_registered=2
  service=weather  canned="sunny-72F"
  service=news  canned="tech-headlines-x3"

> /mcp call weather
ok=1  bytes=9  body="sunny-72F"

> /mcp call unknown
ok=0  body="unknown-service"
```

### Why the registry is inlined in the chat example

The dispatcher inlines a 3-function local shim (`_mcp_local_new / register / lookup`) rather than importing `src/io/effectors/effector_mcp.nova` directly. **Reason:** importing the module transitively pulls `tool.nova`, whose `_g_TR_TAG` global collides with the one already in the chat's transitive import graph (NOVA runtime gap **D-3**, symbol collision across modules). The shim shape matches the effector's API exactly, so behavioural parity with any caller is preserved.

Once the upstream symbol-collision issue closes, the inline shim collapses to a direct `import "../src/io/effectors/effector_mcp.nova"` and the `/mcp` command surface is unchanged.

## Phase 6 pt2a — minimum viable stdio MCP server (shipped)

`bin/crossengin-mcp` is a standalone binary that speaks enough JSON-RPC 2.0 to let a Claude Desktop / Cursor / Zed instance complete the MCP handshake and call a tool. The source lives in two places:

- `src/io/effectors/mcp_server_stdio.nova` — the server loop + handshake dispatch. No full JSON parser: method / id / tool-name are extracted via substring search over the request line. Output is template-formatted JSON.
- `examples/crossengin_mcp.nova` — the binary entry point. Registers two canned tools (`hello`, `echo`) so the handshake path can be exercised with scripted stdin.

Supported methods:

| method | behaviour |
|---|---|
| `initialize` | `{"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"crossengin-mcp","version":"0.1"}}}` |
| `notifications/initialized` | Accepted silently (notification, no response). |
| `tools/list` | Enumerates every tool registered via `mcp_srv_register_tool`. Each tool emits `{name, description, inputSchema:{type:"object",properties:{}}}`. |
| `tools/call` with `"name":"<tool>"` | Looks up by name; returns `{"content":[{"type":"text","text":"<canned>"}],"isError":false}`. Unknown tool → error -32602. |
| anything else | Error -32601 "Method not found". |

### Wire into Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or the equivalent on your OS:

```json
{
  "mcpServers": {
    "crossengin": {
      "command": "/absolute/path/to/bin/crossengin-mcp"
    }
  }
}
```

Restart Claude Desktop. The `hello` and `echo` tools appear in the tool picker.

### Scripted stdin smoke test

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hello"}}\n' \
  | ./bin/crossengin-mcp
```

Output (three response frames, one per line, each valid JSON with matching `id`):

```
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"crossengin-mcp","version":"0.1"}}}
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"hello","description":"Returns a canned greeting","inputSchema":{"type":"object","properties":{}}}, ...]}}
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"hello from crossengin-mcp pt2a"}],"isError":false}}
```

### Deferred to later pt2 sub-PRs

- **pt2b** — wire the chat REPL's live MCP registry so `/mcp register <svc> <resp>` in-chat adds a tool the external MCP client sees. Needs an IPC seam between the chat process and the stdio server process (unix socket or shared-file registry).
- **pt2c** — route `tools/call` through `_gate_or_prompt(CAP_INGEST_ATOM, ...)` with the invoking client's identity as the `authorized_user`. External clients can't bypass CrossEngin's policy gates.
- **pt2d** — tool manifest file loading from `~/.crossengin/mcp-tools/index` (mirrors the Phase 5 `agent_bundle.nova` pattern). Lets an operator add a tool without recompiling.
- **pt2e** — HTTP+SSE transport for clients that don't spawn stdio servers (web MCP clients, remote servers).
- Real JSON parser — the substring search handles the fields pt2a-c need, but pt2d's tool manifests will want a proper byte-buffer parser (`src/nl/json_parser.nova`).

## What a real inbound MCP server needs (deferred)

A real MCP server a Claude Desktop / Cursor / Zed instance can connect to needs all of:

### 1. Transport

MCP speaks either stdio (child-process spawn) or HTTP+SSE (long-lived HTTP connection with Server-Sent Events). Neither exists in NOVA today:

- **Stdio server loop**: `read_line` works for one-shot client commands, but an MCP server must multiplex `stdin → router → stdout` on every frame without blocking. NOVA has no non-blocking I/O primitive (`select`/`poll`); the NOVA runtime gaps doc lists this as the P-1 family.
- **HTTP+SSE**: `src/io/transducers/http_client.nova` exists but is a client; the matching HTTP *server* with SSE support is not shipped. Writing one would need chunked-encoding, keep-alive, and an event-loop seam NOVA doesn't expose.

### 2. JSON-RPC

MCP frames every message as JSON-RPC 2.0 (`{"jsonrpc": "2.0", "id": ..., "method": ..., "params": ...}`). CrossEngin has no shipped JSON parser. The NOVA runtime gap list flags B-1 (NOVA strings are NUL-terminated) which makes a general JSON parser awkward: JSON strings routinely carry `\u0000` escapes, and the parser's byte buffer path has to use `[buf, len]` pairs throughout (see `src/net/tls/der.nova`'s convention). A minimal JSON parser would be ~300 LOC of careful byte handling.

### 3. MCP handshake + tool discovery

MCP requires:
- `initialize` request/response with protocol version negotiation.
- `tools/list` returning tool manifests (name, description, input schema).
- `tools/call` dispatch to the actual implementation.
- Capability bits in the handshake for prompts, resources, logging, sampling.

Tool discovery wants to enumerate a directory (e.g. `~/.crossengin/mcp-tools/*.json`). NOVA runtime gap **F-2** (no `sys_readdir`) blocks that; the workaround is the index-file convention `/agent list` uses in Phase 5 pt1.

### 4. Capability bridging

Every inbound `tools/call` should route through the Phase 1 `_gate_or_prompt` cap gate so an external MCP client can't bypass `CAP_INGEST_ATOM` / `CAP_DELETE` policy. That's architecturally compatible — just needs wiring per tool.

## Phase 6 pt2+ roadmap

1. **Issue tracker**: the four NOVA upstream issues (nova#7 fork return, nova#8 store64-of-0, nova#9 envp=NULL, nova#10 sys_read-on-new-fd) are strictly prerequisite for a reliable stdio/HTTP server loop, because the server fork+exec'd child-process handling and buffered-stream reads sit on all of them.
2. **JSON parser**: new `src/nl/json_parser.nova` module using `[buf, len]` byte pairs per B-1. Target: enough JSON-RPC 2.0 to round-trip MCP frames; no need for a general parser.
3. **Stdio server loop**: new `src/io/effectors/mcp_server_stdio.nova` reading newline-framed JSON-RPC from stdin, dispatching, writing responses to stdout. Lives under the same `ACT_NET_FETCH` + `_gate_or_prompt` gate as other outbound effectors.
4. **Tool registry via `~/.crossengin/mcp-tools/index`**: mirror the Phase 5 `agent_bundle.nova` pattern — one tool manifest per line in an index file, each manifest a JSON blob with `name / description / schema`.
5. **ADR-0211 inbound-MCP**: a new ADR documenting the above, since ADR-0054 only covers outbound.

## Rollback of pt1

The `/mcp` command surface is additive; removing the three dispatch entries restores pre-pt1 behaviour. The inline shim functions are dormant without a caller.

## Verified in pt1

```
> /mcp register weather sunny-72F
registered: weather

> /mcp call weather
ok=1  bytes=9  body="sunny-72F"
```

Phase 0 10-query `fever` regression retains `mc_hits=9`, `ff_goodness=486000`, `synapse_mean_weight=300`, `ia_strength=10`.

Build: all modules compile; all 9 example binaries link.
