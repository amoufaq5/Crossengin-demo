# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

## Phase progress

- Phase 1 substrate kernel: **complete**
- Phase 2 reader and language: **complete**
- Phase 3 knowledge representation: **complete**
- Phase 4 memory and learning: **complete**
- Phase 5 self-directed learning: **complete**
- Phase 6 cognitive subsystems: **complete**
- Phase 7 agent architecture: **complete**
- Phase 8 safety and audit: **complete**
- Phase 9 IO and effectors: **complete**
- Phase 10 persistence and operations: **complete** (modules + spine artifact +
  the unified single-process daemon `bin/crossengin`; blocker #10 fixed in the
  NOVA toolchain — see below)
- P2.10 snapshot compaction pass: **complete**.
  After hours of operation a long-running snapshot grows linearly with KG
  size + moment count + episode count: a steady accumulation of dead atoms
  (mean < 0.05, kept for posterity but never reached at inference), archived
  episodes (tier == EP_ARCHIVED, past the active recall window), and weak
  synapses (|weight| < 0.2 milli) that all together push the wire format
  past 500KB and make /load take a noticeable beat. New module
  `src/persistence/snapshot_compaction.nova` is the in-memory editor: it
  takes a PARSED snapshot value and returns a NEW snapshot value with the
  same wire format (no SNAP_FORMAT_VERSION bump) but smaller payloads, by
  filtering each section's blob against a configurable opts struct.
  Sub-compactors:
  - `compact_kgs(snap, opts) -> [new_blob, dropped]` drops atoms whose
    posterior mean (alpha / (alpha+beta) in milli) is below
    `opts.dead_belief` (default 50, i.e. 0.05). Optionally also drops
    atoms whose label starts with `opts.drop_label_prefix` -- the
    scratch-namespace knob (`debug:` or test prefixes).
  - `compact_episodic(snap, opts) -> [new_blob, dropped_eps, dropped_moments]`
    drops episodes at tier EP_ARCHIVED (== 2) and moments older than
    `opts.moment_max_age_ns` (default 1h == 3,600,000,000,000 ns). "Older
    than" is computed relative to the newest moment timestamp in the
    stream, so it works without an external clock reference.
  - `compact_synapses(snap, opts) -> [new_blob, dropped]` tightens the
    already-applied SYN_SNAP_MIN cut (100 milli) to
    `opts.synapse_threshold` (default 200 milli). No-op when the blob's
    current threshold is already at or above the requested level (only
    ever tightens, never relaxes).
  - `snap_compact(snap, opts) -> new_snap` orchestrates all three +
    copies SOUL / SELFMODEL through unchanged. `snap_compact_stats(snap,
    opts) -> [kg_drop, ep_drop, m_drop, syn_drop]` does the same scan
    without producing the new snapshot (used by `/compact --dry-run`).
  Opts knobs are env-driven via `compact_opts_from_env()`:
  `CE_COMPACT_DEAD_BELIEF` (milli), `CE_COMPACT_MOMENT_MAX_AGE_NS` (ns),
  `CE_COMPACT_SYNAPSE_THRESHOLD` (milli), `CE_COMPACT_DROP_LABEL_PREFIX`
  (string). All four fall through to the static defaults when unset /
  invalid (mirrors `_dl_env_int` in decision_log).
  Chat surface (`examples/crossengin_chat.nova`): a single new
  `_admin_compact` admin function + dispatch line for `/compact`.
  `/compact` (no arg) builds the live snapshot via `_build_snapshot`,
  runs `snap_compact_stats` for the report, runs `snap_compact` for the
  payload, prints
  `(compacted: 47 dead atoms dropped, 12 archived episodes dropped,
   0 old moments dropped, 23 synapses below new threshold dropped;
   snapshot 540KB -> 320KB)` and stashes the compacted snapshot in a
  global `_pending_compact_snap` buffer keyed by `active_id`. The NEXT
  `/save` reads the buffer instead of rebuilding from live state and
  prints `(saved compacted snapshot: kg=N atom(s), M moment(s), K syn(s)
  -> path durably)`. Buffer is cleared after every /save; the per-session
  key lets a `/switch` invalidate a stale buffer.
  `/compact --dry-run` prints the same stats line with " (dry-run)" mode
  marker but does NOT touch the pending buffer -- the next /save still
  rebuilds from live state.
  Snapshot-disk hook: `snap_save(s, path)` honours
  `CE_AUTO_COMPACT_ON_SAVE=1` -- when set, the snapshot is passed through
  `snap_compact(s, compact_opts_from_env())` before serializing to text,
  so a daemon that wants to write only compacted images can opt in via
  env. Off by default (manual `/compact` is the primary surface).
  NOVA list-mutation safety: every per-section compactor copies survivors
  into a fresh list rather than removing in place (the brief calls this
  out -- list_set has no shift-and-remove semantics, so filter-while-
  iterate is a footgun). The 1-hour ns default sits above NOVA's
  pointer-threshold (0x100000) and is held in a `let` constant rather
  than inlined.
  Acceptance: `tests/unit/test_snapshot_compaction.nova` covers opts
  defaults + setters, KGS drops by dead-belief + by label prefix,
  EPISODIC drops by tier + by moment age, SYNAPSES tighten-only
  threshold (including the no-op-when-blob-already-tighter case), full
  orchestrator pipeline with mixed sections, round-trip through
  `snap_to_text / snap_from_text` (the compacted shape is still wire-
  format compatible), size-shrinks bound (100 atoms, half dead -> >25%
  byte savings), empty-snapshot edge case, and env-driven default
  helpers -- 48 assertions across 13 test functions.
  `tests/integration/scenario_n_compaction.sh` (NEW; 12 assertions): seed
  baseline /save -> /teach 50 unknowns + /pin each to confidence=10 ->
  /save baseline; then seed baseline -> /teach 50 + /pin -> /compact ->
  /save with `CE_COMPACT_DROP_LABEL_PREFIX=scenN`. Verifies the stats line
  format, the drop count (99 of 100 atoms -- 50 lang pinned to dead
  belief + 50 reasoning prefix-matched, one of the lang word atoms
  shares its alpha/beta state at the same address as the reasoning
  atom's), the `(in-memory snapshot replaced)` banner, the
  `(saved compacted snapshot: ...)` /save banner variant, and the
  acceptance check `compacted_growth < 50% of baseline_growth` (typically
  878B vs 16404B -- ~5%). Also exercises `/compact --dry-run` (must
  print "(dry-run)", must NOT print "in-memory snapshot replaced", and a
  subsequent /save must use live state) and verifies /help lists
  /compact.
  Sample stats output (verified): `(compacted: 99 dead atoms dropped, 0
  archived episodes dropped, 0 old moments dropped, 0 synapses below new
  threshold dropped; snapshot 184KB -> 168KB)`.
- P2.8 streaming event sources (stdin + Unix socket + HTTP webhook): **complete**
  for stdin; framework-only for the other two.
  Three new transducers under `src/io/transducers/` lift the daemon from a
  fixed pre-loaded event queue to a long-running event consumer fed by real
  input at runtime. Each ships a uniform poll surface
  (`stream_*_poll(state, hs)`) the daemon calls once per tick, plus an
  env-toggled `init_from_env` / `init` lifecycle so the default scripted-
  episode integration tests stay bit-identical.
  **stream_stdin (fully implemented):** `CE_STREAM_STDIN=1` switches fd 0
  to non-blocking via a raw `fcntl(72, F_SETFL=4, O_NONBLOCK=2048)` shim,
  then each poll calls `sys_read(0, ...)` non-blocking; complete
  newline-terminated lines are normalized via the existing
  `transduce_text` and posted as `EV_MESSAGE`. A persistent line-residual
  buffer holds partial reads until the next newline. EOF flushes any tail
  and marks the source done.
  **stream_unix_socket (framework + listen-socket lifecycle):**
  `CE_STREAM_SOCKET=<path>` (default `/tmp/crossengin.sock`) builds a
  sockaddr_un by hand (AF_UNIX=1, 110-byte struct, store8-per-byte to
  dodge the pointer-threshold), binds + listens, sets the listen fd to
  O_NONBLOCK, then per poll accepts one client and drains its lines
  synchronously. Multi-client + truly non-blocking accept are stubbed
  behind the same call surface.
  **stream_http (framework + JSON message-field extractor):**
  `CE_STREAM_HTTP_PORT=<int>` (default disabled) binds `127.0.0.1` by
  default (loopback enforced because the body feeds cognition).
  `POST /api/event` with `{"message":"text"}` -> EV_MESSAGE; all other
  paths/methods return 4xx. A tolerant single-field JSON extractor reads
  the `message` value (handles `\"` + `\\` escapes); a full JSON parser
  would be over-scope for this single endpoint. Concurrent client
  handling stubbed: one request per poll.
  **Daemon integration:** any of the three CE_STREAM_* envs trips
  `streaming_mode=1`, which (a) suppresses the scripted episode, (b) lifts
  the CE_MAXSTEP cap so the daemon runs indefinitely, (c) adds one poll
  per source per tick to the main loop, (d) suppresses the post-loop
  scripted-episode "must" assertions, (e) skips the reboot-rehydrate
  block (handled out-of-band by SIGINT/SIGTERM + the idle checkpoint).
  Default behaviour (no env set) is bit-identical to pre-P2.8.
  **NOVA gotcha worked around:** `str_new(buf, n)` (from
  `std/string`) hangs inside the daemon's compilation unit when called
  from a transducer poll. All three modules build their post-read NOVA
  string by `chr()`-concatenation in a tight loop instead; the loop is
  O(n) per syscall chunk (bounded by 4096 bytes) so the overhead is
  acceptable. The unit test `test_stream_stdin.nova` exercises the
  shared splitting+posting logic via a `stream_stdin_test_feed` helper
  that does NOT touch real stdin -- 28 assertions across 7 test
  functions (well above the ~10 target). The integration test
  `tests/integration/scenario_l_stream_stdin.sh` launches the daemon
  with `CE_STREAM_STDIN=1`, sends `fever` via a held-open FIFO, and
  asserts (a) the streaming-mode banner names stdin, (b) the driver
  line announces streaming-mode, (c) the percept line `msg "fever"
  perceive(m>=1` was emitted, (d) the scripted-episode messages were
  suppressed. Sample smoke run:
  ```
  echo "fever" | CE_STREAM_STDIN=1 ./bin/crossengin
  # ===                          ===
  # boot     : cold start (no prior snapshot); Aurora, 8 parts, 572 concepts
  # stream  : stdin
  # driver   : streaming-mode -- waiting for events from stream sources
  #   [100Hz] msg "fever" perceive(m=1,unk=0) reason=9 mood(v=656) ... say "see recover"
  ```
- P2.4 atom-store hash index (label + kind buckets): **complete**.
  `src/kg/multi_kg_manager.nova` now carries a side-table label hash index
  inside every KG (`KG_LABEL_IDX`, `LABEL_BUCKETS = 256` buckets of
  `[label_hash, atom_id]` pairs) plus a parallel kind index
  (`KG_KIND_IDX`, `ATOM_KIND_COUNT` lists of atom_ids). `kg_find_atom(kg,
  label)` now hashes the label (deterministic shift-xor in
  `atom_store.nova::label_hash` — `h = ((h * 31) + c) & 32767`, seed 5381,
  bucket = `h & 255`), jumps to the bucket, and linear-walks the small
  bucket; with 1000 atoms each bucket holds ~4 entries so lookup is
  effectively O(1) amortized. The hash function uses a 15-bit mask
  (32767 max) so the multiply intermediate stays well below NOVA's
  large-magnitude pointer-threshold (0x100000) — see footgun #11. Mutation
  hooks: `kg_add_atom` populates both indexes after appending the atom,
  `kg_remove_atom` (new, for atom_death_monitor's tombstone path) deletes
  the index entries but leaves the atom slot in place so existing handle
  callers don't blow up. Snapshot rehydrate: `kg_section_apply` in
  `snapshot_disk.nova` now ends with a per-KG `kg_rebuild_index(kg)` so
  rehydrated atoms are addressable on the first lookup; `kg_rebuild_index`
  also auto-installs the index slots on a legacy KG that lacks them
  (backwards-compat). Backwards-compat: `kg_find_atom` checks
  `_kg_has_index(kg)` and falls back to the original linear scan if
  absent (a snapshot rehydrated through some other path stays
  functional). `kg_atoms_by_kind(kg, kind)` is the matching public read
  surface for the kind index. Acceptance:
  `tests/unit/test_atom_store_index.nova` covers the hash function
  (determinism, range/mask invariants), fresh-KG index-slot presence,
  add->hit / remove->miss mutation hooks, hash-collision retrievability,
  1000-atom indexed lookup under 50ms wall-clock (via `nanotime()`), the
  snapshot rehydrate path (clear-then-`kg_rebuild_index` round-trip),
  5000-atom (2x 2500) cross-KG isolation including a shared-label probe
  in both KGs, and the legacy-snapshot linear-scan fallback for a
  hand-built indexless KG — 61 assertions across 10 test functions.
  `tests/benchmark/bench_kg_query.nova` extended with a head-to-head
  section (1000-atom KG, 1M lookups via `nanotime()`):
  `indexed elapsed(ms): ~170` vs `scalar elapsed(ms): ~8700`, **speedup
  ratio ~50x** (within the bounds of O(1) vs O(N/2=500) with constant
  factors). The legacy 3000-atom scalar-walk section is kept for
  comparison with prior benchmark runs.
- P0.6 real-time wall-clock pacer: **complete**.
  New `src/scheduler/realtime_pacer.nova` turns the abstract "100Hz active /
  10Hz idle" tiers into actual wall-clock pacing. The pacer samples
  `nanotime()` at each tick start, lets the tick body run, samples again,
  and `sleep_ms`'s the remainder of the 10ms / 100ms budget; if the tick
  overran, it counts the overrun and the worst-case nanoseconds-over and
  proceeds without sleeping (so the next tick is on time even if this one
  slipped). The wrapper `hs_step_paced(hs, modulator, error, pacer)` lives
  in `hybrid_scheduler.nova` and routes the active/idle budget by reading
  `hs_rate()`. Pacing is OPT-IN via `CE_REALTIME=1` -- when off, the pacer
  is a no-op so unit tests stay full-speed. The daemon prints
  `pacer: <N> ticks, <M> overruns (max <K>ms over budget)` at exit when
  pacing is enabled. A slow-mo factor (`pacer_set_factor`) multiplies the
  budget for regression tests that want to stretch wall-clock time without
  changing call sites. Pacing uses an inline `_imul_raw` asm shim because
  the budget * factor multiply both operands are well above NOVA's
  pointer-threshold (0x100000) and would otherwise dispatch into
  `_nova_mul`'s str_repeat / list_repeat path. Acceptance:
  `tests/unit/test_realtime_pacer.nova` covers construction defaults, the
  disabled no-op, real-sleep wall-clock confirmation via raw `nanotime`
  reads (50ms +/- 15ms), deliberate-overrun reporting, slow-mo (factor 3
  -> ~60ms wall), factor clamp on non-positive k, multi-tick counter
  accumulation, and the summary format -- 27 assertions across 8 test
  functions. Sample smoke: `CE_REALTIME=1 ./bin/crossengin 2>&1 | tail -3`
  ends with `pacer: 44 ticks, 0 overruns (max 0ms over budget)`.
- P0.7 decision-log durable path: **complete**.
  `src/audit/decision_log.nova` gained the runtime seam that was formerly
  the documented NOVA-enhancement #9. Each `dl_append` now ALSO writes a
  pipe-separated line to an `O_WRONLY|O_CREAT|O_APPEND` file (path from
  `getenv("CE_DLOG_PATH")`, default `/tmp/crossengin.dlog`). fsync is
  batched: every 16 entries (`CE_DLOG_FSYNC_EVERY`) or every 1000 ms
  (`CE_DLOG_FSYNC_INTERVAL_MS`) since the last fsync, whichever fires
  first -- so a single-entry burst doesn't pay the full fsync cost but a
  steady stream still gets a sub-second flush latency. Per-message
  ADR-0043 trace fields (the bulky visited-node list) are NOT serialized
  to the on-disk line because they are reconstructible from the snapshot;
  the hash chain is recomputed at recovery from the same fields, so
  `dl_verify` still works post-rehydrate (trace is empty in the recovered
  copy but the chain math agrees). On boot, `dl_open(path, log)` reads
  every line, replays each through `_dl_apply_line` (bypassing the
  re-write side-effect), and stops at the first corrupt line; the tail
  past that point is truncated via a fresh `O_TRUNC` write of the bytes
  that DID parse, with a `warning -- truncated corrupt tail` line printed
  to stdout. The dlog is "durable-but-separate" per ADR-0043: it lives at
  its own path, so a snapshot rehydrate does NOT roll back audit history.
  New API on top of the existing `dl_append`/`dl_verify`/`dl_get`/
  `dl_count`: `dl_open(log, path)`, `dl_close(log)`, `dl_path(log)`,
  `dl_pending_writes(log)`, `dl_is_durable(log)`, `dl_force_fsync(log)`.
  The daemon and chat both call `dl_open(log, ...)` after `dl_new()` and
  `dl_close(log)` at exit (the chat hooks `/quit` and `/exit` shutdown
  paths in `_try_admin` plus the bare `quit`/`exit`/EOF paths in `main`);
  no new admin command is added (`/history` already covers `dl_get`).
  Acceptance: `tests/unit/test_decision_log_durable.nova` covers fresh-
  path open + close, append-writes-to-disk, restart-preserves-entries,
  multi-entry recovery with follow-up append landing at the right seq,
  corrupt-tail truncation, batched-fsync threshold via `dl_pending_writes`,
  and in-memory-only behaviour -- 37 assertions across 7 test functions.
  `tests/integration/scenario_a3_dlog.sh` drives 3 chat messages, SIGKILL,
  relaunch, and confirms `/history` shows the prior entries with the
  `dlog: ... loaded N prior entries` boot banner. Sample smoke:
  `CE_DLOG_PATH=/tmp/test.dlog ./bin/crossengin && wc -l /tmp/test.dlog`
  prints `7 /tmp/test.dlog` first run, `14 /tmp/test.dlog` second run.
- P2.9 Prometheus `/metrics` scrape endpoint: **complete**.
  `scripts/web.py` now serves `GET /metrics` in the Prometheus text-format
  (`# HELP <name> <help>` + `# TYPE <name> gauge|counter|summary` framing
  followed by `name{labels} value` samples), so external monitors
  (Prometheus, Grafana Agent, vmagent, ...) can scrape live agent state at
  the usual 15s cadence. Probe path: the chat side gained an
  underscore-prefixed `/__metrics__` admin command that walks the live
  session and emits one `key=value` line per metric between explicit
  `METRICS_BEGIN` / `METRICS_END` markers (so the python parser doesn't
  depend on log-line ordering); web.py runs that probe lazily per cookie
  and caches each parsed response for `CE_METRICS_CACHE_S` seconds
  (default 10) so a tight scrape loop never serializes against `/api/chat`
  traffic. Metric families exposed: `crossengin_atom_count{kg=...,sid=...}`
  (reasoning + language KGs), `crossengin_refl_atom_count{sid=...}`,
  `crossengin_dlog_entries{sid=...}`, `crossengin_promotion_rate`
  + `crossengin_atrophy_rate` (`{source=...,sid=...}`, ADR-0050 milli
  percent rescaled to unit 0..1), `crossengin_soul_mood_valence` /
  `crossengin_soul_mood_arousal{sid=...}` (ADR-0034 mood, rescaled
  0..1), `crossengin_scheduler_tick_rate{sid=...}` (Hz),
  `crossengin_scheduler_overruns{sid=...}` (P0.6 pacer counter, 0 in
  chat mode), `crossengin_active_session_count` (live SessionStore size),
  `crossengin_evicted_session_count` (cumulative LRU evictions),
  `crossengin_request_total{cookie=...}` (per-cookie POST counter), and
  the `crossengin_request_duration_seconds` summary with `_count`,
  `_sum`, and `{quantile="0.5|0.9|0.99"}` over a 256-sample rolling
  window. The `/__metrics__` admin command is read-only -- the probe only
  calls `mo_poll` (the same idempotent side-effect `/meta` does) and
  reads `kg_atom_count` / `dl_count` / soul mood / `hs_now` / `hs_rate`.
  `/metrics` inherits the loopback bind default from `/api/chat`
  (`CE_BIND` env defaults to `127.0.0.1`), so a `CE_BIND=0.0.0.0` deploy
  must accept the same caveat as the rest of the admin surface (a curl
  from the LAN can scrape the agent's live state). The endpoint never
  spawns a `ChatChild` -- a Prometheus scraper with no cookie sees only
  the process-wide counters plus per-cookie data for whichever sessions
  are already alive, never extending the LRU footprint. Acceptance:
  `tests/integration/scenario_m_metrics_endpoint.sh` (35 assertions):
  asserts the static loopback bind + cache env, launches the server,
  POSTs `hello` to materialise a cookie's child, scrapes `/metrics`,
  validates HTTP 200 + `Content-Type: text/plain; version=0.0.4`,
  validates the `# HELP` / `# TYPE` framing for every metric family
  exposed, validates label shapes (`{kg="reasoning",sid="..."}`,
  `{cookie="..."}`, `{source=...,sid=...}`, etc.), asserts
  `request_total >= 1` after the POST, asserts the second scrape inside
  the cache window returns the same per-sid atom counts (cache hit, no
  re-probe), and confirms `/metrics` is read-only (active session count
  is unchanged across two scrapes). Sample output (10 lines):
  ```
  # HELP crossengin_atom_count Atoms in a per-session knowledge graph (kg label: reasoning|language).
  # TYPE crossengin_atom_count gauge
  crossengin_atom_count{kg="reasoning",sid="947f14a4-..."} 572.0
  crossengin_atom_count{kg="language",sid="947f14a4-..."} 547.0
  # HELP crossengin_dlog_entries Decision-log entries per session (ADR-0043).
  # TYPE crossengin_dlog_entries gauge
  crossengin_dlog_entries{sid="947f14a4-..."} 2.0
  # HELP crossengin_soul_mood_valence Soul mood valence (ADR-0034, unit scale 0..1).
  # TYPE crossengin_soul_mood_valence gauge
  crossengin_soul_mood_valence{sid="947f14a4-..."} 0.656
  ```
- Phase 13 Tier-2 item #1 -- meta-learning observer: **complete**.
  New `src/parts/meta/meta_observer.nova` (ADR-0050) is a low-frequency,
  purely-observational loop: it snapshots per-source atom-belief
  distributions and reports rolling promotion (tentative -> durable) and
  atrophy (durable -> sub-threshold or vanished) rates so the operator can
  tell which sources of evidence are productive. Source tagging is
  minimum-viable and explicit -- atoms only carry a source if a caller calls
  `mo_attribute(mo, tag, atom_id)` at creation time; the atom_store data
  shape is unchanged (the tag table lives entirely in the observer's
  side-table). The daemon attributes the contiguous seed-installed atom
  block as `"seed"` at boot and tags freshly-ingested concept atoms from
  the trigger-drain path as `"user-teach"`; the chat's `_admin_teach` does
  the same for `/teach`. Idle-tick polling (`mo_poll`, every
  `MO_POLL_EVERY` ticks, default 10) walks each source's attributed atoms,
  classifies each against the ADR-0030 mean threshold (>= 750/1000 =
  durable), accumulates per-source promotion / atrophy counters, and emits
  a `(meta: source 'X' promotion=N.N% atrophy=N.N%)` line only when either
  rate has activity (so normal stdout stays quiet). The chat has a new
  `/meta` admin command that prints the per-source table (`source / atoms /
  tentative / durable / promotion% / atrophy% / last_poll`). Defer for
  follow-up: feeding the rates back into `source_authority` (the dangerous
  up-/down-weight policy). Acceptance:
  `tests/unit/test_meta_observer.nova` covers empty observer, attribution
  dedup, the classification on poll (durable/tentative split for belief
  means 750/250 vs 500/500 vs 100/900), the promotion delta on a
  tentative-then-promoted atom, the atrophy delta on a durable-then-dropped
  atom, multi-poll accumulation, the report shape including every tracked
  source, the milli-percentage formatter, and the refl-kg promotion
  counter -- 39 assertions across 10 test functions. Sample `/meta` smoke
  run after `/teach widget` + `/teach gadget`: `seed 572 / 572 tentative /
  0 durable / 0.0 / 0.0` and `user-teach 2 / 0 / 2 / 100.0 / 0.0`.
- P1.3 -- kg-sync v2 protocol (N-subscriber + bidirectional + reconnect +
  auth + conflict): **complete**. Matures the P20 distributed-substrate
  seam from a one-shot single-subscriber demo into a production-shape
  pub/sub. The protocol bumps to v2 (HELLO + OK lines change version,
  three new event kinds, optional auth token, optional resume cursor); v1
  HELLO/OK strings are still recognised by the server so an old subscriber
  can attach to a new publisher. The end-to-end shape:
  - **N-subscriber fan-out**: publisher reads `CE_KGSYNC_SUBS` (default 1
    for backward compat) and accepts that many initial subscribers via
    `sync_pub_accept_n`. Each sub becomes a `[fd, last_ack_id,
    last_active_ns]` record; on every atom-birth (or PROMOTE / ATROPHY /
    DELETE event) the publisher iterates the live list and calls
    `_broadcast_line` -- round-robin per-event matches the brief's
    "background-style send loop" in a single process without
    threads. Rejected handshakes (bad token, malformed HELLO) do NOT
    count toward N; the publisher keeps accepting up to `3*N+4` total
    attempts. Subscribers whose `last_active` is older than
    `KGSYNC_PRUNE_NS` (30 s) are dropped before the next broadcast.
  - **Bidirectional**: SUB and PUB sides are symmetric after the
    handshake. Each subscriber can teach back to the publisher by
    piggybacking a `PUB <kg> <id> <kind> <a> <b> <label>` line on its
    ACK channel; the publisher's `_broadcast_line` collects PUB replies
    into an inbox the caller drains via `sync_apply_atom` (which is
    conflict-aware -- see below).
  - **Three new event kinds**: `PROMOTE <kg> <id> <alpha> <beta>` (belief
    update), `ATROPHY <kg> <id>` (sub-threshold mark), `DELETE <kg> <id>`
    (atom killed). The publisher exposes `sync_pub_broadcast_promote /
    _atrophy / _delete` helpers wired into a tiny stdin admin protocol
    (`promote <id>` / `atrophy <id>` / `delete <id>`); a full daemon
    would call them directly from the bayesian-update / evidence-cut /
    atom_death_monitor signal paths.
  - **Reconnect on disconnect**: subscriber holds a `[fd, host, port,
    token, since_atom_id]` state via `sync_sub_connect_state`. When
    `_recv_line` returns 0 mid-stream (peer closed mid-stream and not via
    BYE), `sync_sub_reconnect` closes the dead fd, re-dials with the
    60-attempt budget, and re-handshakes with `SUB FROM <cursor>` so the
    publisher can resume from the highest ATOM id the sub has applied.
    The subscriber distinguishes a clean BYE (don't reconnect, exit) from
    an unexpected EOF (reconnect).
  - **Auth handshake**: server reads `CE_KGSYNC_TOKEN` from env at
    accept-time. If set, the client must send `HELLO ce-kg-sync v2
    token=<TOK>` matching the server's token; otherwise the server
    replies `ERR auth` and closes. If unset, any HELLO is accepted
    (anonymous backwards-compat mode). The client's
    `sync_sub_connect`/`_state` mirrors the env so a single
    `export CE_KGSYNC_TOKEN=...` configures both sides.
  - **Conflict resolution**: `sync_apply_atom(kg, remote_id, kind, alpha,
    beta, label)` is the canonical receiver. Policy: (1) no local atom
    with `label` -> birth fresh; (2) local atom shares the remote id ->
    refresh belief in place; (3) local atom exists at a DIFFERENT id
    (the "two ends taught the same word" race) -> MERGE by averaging
    alpha and beta in-place, keeping the local id stable so any synapses
    that already point at it stay valid. No new atom is born on a merge.
    Documented in the module header.
  Wire constants live in `src/io/transducers/kg_sync.nova`:
  `KGSYNC_HELLO_V2_LINE`, `KGSYNC_OK_V2_LINE`, `KGSYNC_SUB_FROM_PREFIX`,
  `KGSYNC_PUB_PREFIX`, `KGSYNC_PROMOTE_PREFIX`, `KGSYNC_ATROPHY_PREFIX`,
  `KGSYNC_DELETE_PREFIX`, `KGSYNC_ERR_AUTH`, `KGSYNC_TOKEN_TAG`.
  Acceptance: `tests/unit/test_kg_sync.nova` covers format/parse
  round-trip for ATOM + PUB + PROMOTE + ATROPHY + DELETE, the top-level
  `_parse_line` classifier, HELLO token extraction (v1, v2 with and
  without token, malformed `token=` clause, empty token value), all four
  v1 malformed-line rejections (still), `_starts_with` prefix helper, the
  three new env helpers (`kgsync_subs_from_env`, `kgsync_token_from_env`
  default-anon), subscriber record init + set_ack + staleness threshold,
  the four `sync_apply_*` policies including the merge path that asserts
  local-id stability and the averaged belief, and the connection-state
  cursor accessors -- 169 assertions across 49 test functions (+116 over
  v1). `tests/integration/scenario_g2_kg_sync_multi.sh` (NEW; 24
  assertions) exercises all five features end-to-end: 3 subscribers fan
  out widget + gadget, sub1 piggybacks alpha-bird + beta-fish back to
  the publisher, a publisher with token rejects an anonymous client and
  accepts the token-bearing one, and a same-label collision (both ends
  teach `shared-label`) verifies the merge keeps the publisher's local
  KG at 1 atom. `tests/integration/scenario_g_kg_sync.sh` (v1 single-sub
  demo) keeps passing unchanged (13 assertions), and
  `tests/integration/failmode_kgsync_subscriber_drop.sh` (the pre-P1.3
  current-behavior pin) also still passes -- the publisher's surface
  hasn't regressed for an abrupt kill, the subscriber's reconnect path is
  the affirmative direction now.
  Sample manual smoke (verified):
  `CE_KGSYNC_SUBS=3 CE_KGSYNC_TOKEN=s3kret ./bin/crossengin-kg-publisher`
  with three `CE_KGSYNC_TOKEN=s3kret ./bin/crossengin-kg-subscriber`
  clients yields `send kg=language id=0 label=widget delivered=3`,
  with each sub printing `recv kg=language id=0 label=widget`.
- P1.1 + P1.6 -- meta-observer feedback into source_authority + atom-death
  attribution: **complete**. Closes the loop on ADR-0050: until this
  session the meta-observer only REPORTED per-source promotion / atrophy
  rates; now it ACTS on them and the atom-death monitor attributes deaths
  back to the observer.
  **P1.1 (feedback):** `src/parts/meta/meta_observer.nova` gains
  `mo_apply_feedback(mo, source_auth)` (mutates) and a paired
  `mo_feedback_dryrun(mo, source_auth)` (read-only). Both walk every
  tracked source: a cumulative promotion rate >= 700/1000 (70%) over a
  sample window of >= 10 attributed atoms promotes the source's host one
  tier (C -> B -> A); a cumulative atrophy rate >= 500/1000 (50%) over
  the same window demotes one tier (A -> B -> C). The window + threshold
  guard against thrash from a single-atom flip -- sustained signals only.
  When both thresholds cross, promotion wins. Source-tag bridge: today
  `source_authority` is host-keyed (URLs map via `sw_host` -> registry),
  while the P15 source tags (`src:topic:fever`) aren't host-keyed; the
  observer maps each tag to a synthetic host string
  (`src:<kind>:<tag>` -> `learned:<kind>:<tag>`; bare tags like `seed`
  and `user-teach` -> `learned:builtin:<tag>`) and calls a new
  `sa_host_set_tier(sa, host, tier)` accessor added to
  `src/learning/source_authority.nova` (plus the read companion
  `sa_tier_for_host`). The `learned:` prefix keeps synthetic hosts from
  colliding with real domains. The daemon
  (`examples/crossengin_daemon.nova`) wires the feedback into the idle
  loop: every `MO_FEEDBACK_EVERY` polls (default 20, override via env),
  it invokes `mo_apply_feedback` and prints a
  `(meta-feedback: '<tag>' -> host '<host>' promote tier C -> B)` line
  only when a tier ACTUALLY moves. The chat (`examples/crossengin_chat.nova`)
  gets two new admin commands: `/meta-feedback` is a dry-run that prints
  the per-source feedback table (tag / host / promo% / atrophy% / sample /
  current / proposed / action) and a "(N tier change(s) pending; run
  /meta-apply to commit)" footer, and `/meta-apply` actually invokes
  `mo_apply_feedback` on the process-shared `sauth` registry (built at
  boot from `sa_default()`). Tier hops are ONE step per call -- chained
  promotions / demotions require multiple feedback cycles. Sample smoke
  (after `/teach`-ing 12 words and `/pin`-ing them all to confidence 800):
  `/meta-feedback` shows `user-teach learned:builtin:user-teach 100.0 0.0
  12 C B promote`; `/meta-apply` reports
  `(user-teach -> host 'learned:builtin:user-teach' promote tier C -> B |
  promo=100.0% atrophy=0.0% sample=12)`; a second `/meta-feedback`
  shows the same source now at B and proposed for A.
  **P1.6 (atom-death attribution):** `src/learning/atom_death_monitor.nova`
  gains `adm_sweep_attributed(reg, kg, mo)` (the legacy `adm_sweep(reg, kg)`
  is now a wrapper that passes `mo=0`, preserving the existing test +
  caller surface). At the tombstone -> dead transition, the new entry
  calls `mo_record_death(mo, atom_id(a))` when `mo != 0` so a
  source-attributed atom that dies outright (durable atom GC'd by the GC
  before the next poll would have classified it as "vanished") bumps the
  observer's per-source atrophy counter immediately. The hook is a
  function-pointer-shaped thing in NOVA -- practically just an import +
  one extra call gated on `mo != 0`. Acceptance:
  `tests/unit/test_meta_observer_feedback.nova` covers the synthetic-host
  mapping for both `src:*` and bare tags, the sustained-signal guard
  (sample below window -> NONE), promote dryrun-then-apply moving tier
  C -> B, demote dryrun-then-apply moving a pre-seeded tier-A source to
  tier B, promote / demote tier-edge clamps, the "promotion wins when
  both cross" branch, a 3-source split (PROMOTE / DEMOTE / NONE),
  chained two-apply promotion from C to A, the `mo_fb_action_name` /
  `mo_tier_name` helpers, and the empty-observer no-op -- 54 assertions
  across 13 test functions. `tests/unit/test_atom_death_attribution.nova`
  covers `mo_record_death` direct (tagged atom -> +1, untagged -> no-op),
  the legacy `adm_sweep` back-compat, `adm_sweep_attributed(reg, kg, 0)`
  null-mo behaviour, the headline "attributed durable atom dies ->
  observer atrophy counter +1", idempotency under repeated sweeps (the
  dead-flag guard prevents double-attribution), multi-attribution in one
  sweep, mixed tagged + untagged, an empty-observer guard, and the
  protected-atom case (never collected, never attributed) -- 28
  assertions across 10 test functions. Tier transitions observed under
  these tests: tier-C synthetic host -> tier-B after one apply for a
  source whose 10 attributed atoms had 8 promotions (80%); tier-A host
  -> tier-B after one apply for a source whose 10 atoms had 6 atrophies
  (60%); chained C -> B -> A across two apply calls for a 20-atom source
  with 18 promotions (90%); both promotion and demotion saturate at the
  A / C edges (no underflow / overflow).
- Phase 14 Tier-2 item #2 -- structural-neighborhood activation: **complete**.
  The reader now has a substrate-native similarity surface for indirect input.
  A new `src/reader/neighborhood.nova` exposes `find_neighbors(kg_reg, handle,
  max_hops, max_results)` that mines TWO substrate sources -- reasoning
  operator edges (ADR-0031) and cross-KG xref edges (ADR-0017) -- plus a small
  word-sense co-occurrence pass (ADR-0015), and aggregates evidence by summing
  strengths and clamping to 0..1000. One-hop wins; two-hop is decayed by
  NEIGH_HOP_DECAY (0.5, same constant as ADR-0012 stage 3).
  `spreading_activation` now seeds neighborhood hits ADDITIONALLY on every
  exact-match anchor's chosen sense (exact match still gets full SPREAD_SEED
  so it dominates) and falls back to `lexical_fallback_candidates` on
  unmatched tokens -- a substrate-native miss recovery that surfaces concept
  handles named by lexically-similar known words. Sample:
  `find_neighbors(fever, 2, 5)` over a fever -> infection -> treat seed
  returns `infection -> 1000` (one-hop direct, operator + xref both fire),
  `treat -> 600` (two-hop, decayed), `headache -> 500` (one-hop operator
  only). NO embeddings, NO transformer; pure substrate. Acceptance:
  `tests/unit/test_neighborhood_activation.nova` covers all four scenarios in
  the brief (basic find_neighbors, sorted/capped output, hop-depth, round-trip
  via spreading_activation, cross-KG ref case, paraphrase via lexical
  fallback, exact-match dominance) with 30 assertions across 10 test
  functions.
- P2.1 + P2.2 -- cofire and syntactic-slot similarity sources: **complete**.
  Two more substrate-native similarity sources for `find_neighbors`, both
  deferred from the original Phase 14 / Tier-2 #2 work because they needed
  side-indices. Now closed.
  **P2.1 (co-fire from moment_stream):** `src/reader/cofire_index.nova` is
  a side-table keyed by canonicalized atom-id-pair, counting how many
  distinct moments their activations co-appeared. `ci_strength(ci, a, b)
  -> milli` normalizes by the GLOBAL maximum co-fire count -- a rare pair
  that fires as often as the most-frequent pair still scores 1000; a pair
  that appeared in only 1 of 10 max moments scores 100. Storage is a list
  of `[kg_label_a, atom_a, kg_label_b, atom_b, count]` rows; lookup is a
  linear scan (N small in practice; deferred hash index per NEXT_SESSION
  blocker #1). Wired at the PERCEIVED -> SETTLED transition: the daemon
  calls `ms_settle_old_with_cofire(stream, now, ci, kg_label)` at every
  idle tick, which fires `ci_record_moment(ci, kg_label, moment_trace(m))`
  exactly once per moment as it crosses the settle boundary. Empty traces
  and singleton traces are no-ops.
  **P2.2 (syntactic-slot from output_generation):** `src/reader/
  slot_index.nova` is a side-table keyed by (pattern_atom_id, role_name)
  with a histogram of atom-ids that have filled the slot. `si_strength(si,
  a, b) -> milli` sums each slot's contribution and clamps to 1000; the
  per-slot contribution is `min(count_a, count_b) * 1000 / slot_max`, so
  the rarer filler bounds the strength. Wired at the output-generation
  callsite: the daemon's `gen_from_intent_with_slot(lang, cands, intent,
  moment, si)` records each `[role, word_atom]` filler after the chosen
  pattern is selected. Different roles return 0; different patterns share
  no slot; two atoms that have co-filled the same (pattern, role) cell
  surface as role-neighbors.
  **`find_neighbors_full(kg_reg, source, ci, si, max_hops, max_results)`**
  takes both indices, walks all five sources (operator, xref, sense,
  cofire, slot) into one accumulator, and clamps at 1000 per-neighbor. The
  3-arg `find_neighbors(...)` stays as a wrapper that passes `ci=0, si=0`
  so legacy callers and all pre-P2.1/P2.2 tests are bit-identical.
  Sample (paraphrase demo, fever+infection seeded chat history of 10
  co-occurring moments): `ci_strength(fever, infection) = 1000`,
  `ci_strength(fever, treat) = 300` (3 of max 10), `si_strength` between
  two TOPIC-role co-fillers = 1000; baseline `find_neighbors(fever)` gave
  `infection=1000, treat=600` (2-hop xref decayed), but
  `find_neighbors_full(fever, ci, 0)` lifts `treat` to 900 via the cofire
  evidence the moment-stream collected. Acceptance:
  `tests/unit/test_cofire_index.nova` (35 assertions across 10 functions),
  `tests/unit/test_slot_index.nova` (23 assertions across 10 functions),
  plus 4 new tests added to `tests/unit/test_neighborhood_activation.nova`
  (cofire-only neighbor, slot-only neighbor, combined-clamped, 3-arg
  wrapper bit-identity) bringing that suite from 30 to 45 assertions. The
  daemon + chat now allocate `ci_new()` / `si_new()` at boot and pass them
  into the settle and gen calls; no new admin commands. The indices are
  NOT yet persisted across sessions -- next-session indices start fresh; a
  Phase-10 follow-up will lift them into the snapshot.
- Phase 19 Tier-4 item #1 -- audio modality bridge: **complete**.
  Two new modules under `src/io/effectors/` realize the minimum-viable
  audio leg of ADR-0014 -- the modality bridge that until now was a
  documented deferred runtime seam. `audio_synth.nova` is the always-on
  Mode 1 floor: a 256-entry quarter-wave sine table built at startup via
  Bhaskara's degree-domain approximation (full-period samples via 4-fold
  symmetry), a Bresenham-style integer phase generator (all loop-body
  intermediates < 16k so the NOVA loop-multiply pointer threshold,
  blocker #11, is never crossed), per-phoneme synthesis at 8 kHz / 16 bit
  PCM mono (150 ms = 1200 samples per atom, triangular envelope to keep
  edges click-free), a hard-coded formant table for ~30 common ARPABET-ish
  phonemes (vowels 270-730 Hz, fricatives 2.5-3.8 kHz, plosives 180-240 Hz,
  unknown -> 440 Hz A4 fallback), word-level concatenation that prefers
  recorded phonemes from `word_atoms.nova`'s `word_phonemes()` xref when
  available and otherwise falls back to one tone per character at a
  word-length-derived carrier, and a single-shot WAV writer that allocates
  the full byte buffer + writes through `sys_open/sys_write/sys_fsync/
  sys_close` so the file is durable before any aplay reader opens it
  (same contract as `snapshot_disk.nova`). `audio_speak.nova` layers
  Modes 2 + 3 on top: `_try_espeak` uses `fork_process`+`exec_program`+
  `waitpid` to detect `espeak` on PATH via `command -v`, then shells
  out `espeak -w PATH 'TEXT'` for a much higher-quality voice; `_try_aplay`
  best-effort plays via `aplay -q` or `paplay`. Both gracefully fall back
  to the next mode -- the seam returns success as long as the WAV reached
  disk, so playback failure does NOT fail the speak call. The chat gets a
  new `/speak [TEXT]` admin command (default path `/tmp/ce_speech.wav`,
  override via `CE_SPEECH_PATH`); with no TEXT it speaks the agent's last
  reply, captured via a `_last_reply` global the main loop updates on each
  drained event. Acceptance: `tests/unit/test_audio_synth.nova` covers the
  44-byte RIFF header bytes (incl. canonical PCM marker at offset 36-39
  and little-endian sample-rate + data-size fields), 8000-sample sine
  generation (first/last near zero at 1 Hz, peak ~+16000 / min ~-16000),
  zero-sample edge case, 1200-sample phoneme invariant including the
  unknown-label fallback and a 3500 Hz fricative, multi-word + empty-text
  + lang-KG-overrides-fallback paths for `synth_text`, and the on-disk
  WAV round-trip (write `[0,0,0]` to /tmp/ce_test_audio.wav, sys_read the
  first 4 bytes back, assert `R,I,F,F`; 10-sample run is exactly 64 bytes
  on disk = 44 header + 20 PCM) -- 52 assertions across 16 test functions.
  Verified end-to-end in chat:
  `printf '/speak hello world\n/quit\n' | ./bin/crossengin-chat` produces
  `(spoke 'hello world' [synth-only]; wrote /tmp/ce_speech.wav)`, and
  `file /tmp/ce_speech.wav` reports
  `RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 8000 Hz`
  (24044 bytes). In this sandbox neither `espeak` nor `aplay`/`paplay`
  is installed, so Mode 1 carries the seam end-to-end; Modes 2 and 3 are
  exercised by their detection code at runtime and skipped silently.
- Phase 20 Tier-4 item #2 -- distributed-substrate seam: **complete**
  (upgraded to v2 by P1.3 -- see entry above for the multi-subscriber +
  bidirectional + reconnect + auth + conflict-merge details).
  New `src/io/transducers/kg_sync.nova` defines a one-op-per-line text
  wire protocol for atom-birth events plus the publisher + subscriber
  socket halves. v1 operations (still recognised by the v2 server):
  `HELLO ce-kg-sync v1` / `OK v1 protocol accepted` (handshake), `SUB *`
  (subscribe to all atoms), `ATOM <kg_label> <id> <kind> <alpha> <beta>
  <label>` (one atom birth), `ACK <id>` (per-atom ack), `BYE` (graceful
  close), `ERR <reason>` (handshake refusal). Defaults match the rest of
  the repo's safe-bind pattern: 127.0.0.1 (override `CE_KGSYNC_BIND=0.0.0.0`),
  port 8766 (override `CE_KGSYNC_PORT`), subscriber host `127.0.0.1`
  (override `CE_KGSYNC_HOST`). v2 adds three event kinds (PROMOTE,
  ATROPHY, DELETE), bidirectional PUB-from-subscriber, an optional
  `token=<TOK>` HELLO clause + `CE_KGSYNC_TOKEN` env gate, `SUB FROM
  <id>` cursor-based resume, and N-subscriber fan-out gated by
  `CE_KGSYNC_SUBS` (default 1 for v1 backwards compat). Two artifacts
  compose it: `bin/crossengin-kg-publisher` (binds + accepts N
  subscribers + reads labels from stdin + emits atom-births / PROMOTE /
  ATROPHY / DELETE) and `bin/crossengin-kg-subscriber` (dials in +
  handshake + applies received events to its own KG + may teach back via
  stdin -> PUB). The main `bin/crossengin` daemon is intentionally
  untouched -- this is the seam, not the multi-process refactor.
  Acceptance: `tests/unit/test_kg_sync.nova` covers format/parse round-
  trip for ATOM + PUB + PROMOTE + ATROPHY + DELETE, the top-level
  `_parse_line` classifier, HELLO token extraction, all four v1
  malformed-line rejections, the three new env helpers, subscriber
  record init + set_ack + staleness threshold, the four `sync_apply_*`
  policies (including the merge path that asserts local-id stability
  and the averaged belief), and the connection-state cursor accessors
  -- 169 assertions across 49 test functions (+116 over v1).
  `tests/integration/scenario_g_kg_sync.sh` (v1, 13 assertions) and
  `tests/integration/scenario_g2_kg_sync_multi.sh` (v2, 24 assertions)
  exercise both protocols end-to-end against per-run high ports; both
  print SKIP if `socket(2,1,0)` itself fails so a denying sandbox
  doesn't break CI. Sample manual smoke (verified):
  `./bin/crossengin-kg-subscriber > /tmp/sub.out &` then `printf 'widget\n'
  | ./bin/crossengin-kg-publisher` produces `recv kg=language id=0
  label=widget` in /tmp/sub.out.
- Phase 18 Tier-3 item #3 -- multi-tenant session foundation: **complete**.
  New `src/session/session.nova` (ADR-0051) defines a Session struct -- a
  flat 15-slot bundle (id, name, created_at, last_active, soul, kgreg, kg,
  lang, ikg, refl_kg, ctx, log, engine, mo, hs) -- plus a linear
  SessionRegistry keyed by id. The module is dependency-free: every
  subsystem state object is stored OPAQUELY (Session never reads past the
  top-level slot), so the daemon's existing boot sequence builds each
  handle as before and then wraps them with one `session_make(...)` call.
  API: `session_make(id, name, now, sl, kgreg, kg, lang, ikg, refl_kg, ctx,
  log, engine, mo, hs)`, per-slot accessors `session_id/name/created_at/
  last_active/soul/kgreg/kg/lang/ikg/refl_kg/ctx/log/engine/mo/hs`,
  `session_touch(s, now)`; registry `sreg_new`, `sreg_create(reg, id, name,
  now)`, `sreg_register(reg, sess)`, `sreg_lookup(reg, id)`,
  `sreg_destroy(reg, id)`, `sreg_count(reg)`, `sreg_ids(reg)` (ascending),
  `sreg_active(reg, max_idle, now)` (inclusive cutoff). The scheduler is
  per-session by design (clean tenant isolation, each tenant has its own
  tick clock / idle counter); revisit if N >> 1.
  Acceptance: `tests/unit/test_session.nova` covers session_make field
  storage + accessors, session_touch, zero-slot tolerance, registry empty
  state, create + lookup, duplicate-id rejection, pre-built register,
  destroy + no-op destroy, ids sorted ascending, active() inclusive idle
  filter, soul-mutation isolation between sessions, and post-destroy
  survivor integrity -- 66 assertions across 12 test functions.
- Phase 18 Tier-3 item #3 SECOND HALF -- chat `/switch` + web.py per-cookie
  routing: **complete**.
  The chat's `main()` now drives every turn through the SessionRegistry:
  at boot, the default session (`"default"` / "Aurora") is built via a
  new `_new_session_for(reg, id, name, now)` helper and inserted into the
  top-level `sreg`; each iteration of the REPL loop looks up the active
  session by `active_id` and re-binds the cognitive locals
  (`sl, kgreg, kg, lang, ikg, refl_kg, ctx, log, engine, mo, hs`) so every
  admin / message handler operates on the live session's state. New
  `/switch [ID]` admin command: with no arg it lists each session as
  `*active id  "name"  N atoms  last Ss ago` (asterisk marks the active
  row); with an id it activates the existing session or creates a fresh
  one (default name "Default", full seed installed via the same path the
  default session uses at boot). The dispatch table grows by exactly one
  entry. Substrate-side state (part registry, gate router, learning
  trigger arbiter, moment stream, episodic memory) stays process-shared
  -- the Session struct holds only cognitive state. Vanilla
  `./bin/crossengin-chat` is bit-identical to before because no `/switch`
  is ever issued and the default session is the only registered tenant.
  `scripts/web.py` was restructured around a new `SessionStore` class
  that maps `cookie -> [ChatChild, created_ms, last_active_ms]` with an
  LRU cap (default 8, override `CE_WEB_MAX_SESSIONS`). Cookies follow
  the `ce_sid=<UUID>; Path=/; HttpOnly; SameSite=Strict` convention;
  absent or malformed cookies get a freshly-minted UUID via `uuid.uuid4()`
  and a Set-Cookie response header. The existing per-child `request_lock`
  still serializes the send-and-wait handshake; a new registry-level lock
  guards add/evict so two unknown cookies cannot race for the same slot.
  New diagnostic endpoint `GET /api/sessions` returns
  `{"sessions":[{id, last_active_ms, age_ms}, ...]}`. Shutdown walks
  every child and sends `/quit`. One incidental fix: `kg_section_apply`
  forcibly overwrites all `ATOM_LANG` atoms' `ltype` to `LWORD`, which
  corrupts the seed's syntax atoms (`"ack"`, `"see_topic"`) after `/load`;
  the chat now filters `0`s from the `gen_from_intent` candidates list
  when `syntax_find` returns 0 after a `/load`, falling back to
  `_gen_emit_intent`. Acceptance:
  `tests/integration/scenario_h_session_switch.sh` (16 assertions: teach
  in default, /switch alice, teach gadget, /switch back, verify
  per-session recognition both directions; the listing format with
  `* = active`; re-activate the same id; `/help` advertises `/switch`);
  `tests/integration/scenario_i_web_isolation.sh` (12 assertions: two
  distinct cookie jars get distinct ce_sid values; A's `/teach widget`
  is recognized by A but unknown to B; A's state survives B's
  intervening request; `/api/sessions` lists both with the diagnostic
  fields; SIGTERM cleans up). A 3-cookie concurrent stress run (3
  simultaneous `/teach` + query pairs) confirmed no race / interleave:
  each cookie received only its own taught word's response and
  cross-cookie isolation held at the read side too. An LRU stress at
  `CE_WEB_MAX_SESSIONS=3` with 5 sequential cookies evicts the oldest
  two as expected.
- Phase 15 Tier-2 item #3 -- multi-source `/learn`: **complete**.
  `scripts/learn.sh` now accepts a bare TOPIC (Wikipedia, unchanged), an
  http(s):// URL (fetched verbatim), or a local `/abs|./rel|../rel` file
  (read from disk). Each kind derives a sanitised `<tag>` and writes the
  same `/tmp/crossengin_learn_<tag>.txt` + `..._<tag>_triples.txt`. The chat's
  `/learn <ARG>` admin command re-derives the same tag via a NOVA
  `_learn_tag` helper (lock-step with the bash `case`+`sed` pipeline) and
  ingests both files. Every word / operator carries a `src:<kind>:<tag>`
  attribution so a future meta-loop / source-authority pass (ADR-0029)
  can corroborate / atrophy by source. Acceptance: `scripts/learn_smoke_multi.sh`
  exercises all three kinds; `tests/unit/test_learn_tag.nova` covers the
  tag-derivation contract with 22 assertions.
- P1.4 -- plain-HTTP in-process transport seam (NOVA enhancement #11 audit +
  minimum-viable lift off `curl` for `http://`): **complete**. Real TLS stays
  deferred (4-6 weeks; see [`TLS_AUDIT.md`](./TLS_AUDIT.md) for the roadmap).
  New `src/io/transducers/http_client.nova` is a pure-NOVA HTTP/1.1 client
  built on NOVA's existing socket builtins (same idioms as `kg_sync.nova`):
  `http_parse_url(url) -> [scheme, host, port, path]` parses
  `http(s)://host[:port][/path]` with default port 80/443 and "/" default
  path, returning `["", "", 0, ""]` on malformed input; `http_get(url,
  max_bytes) -> [status_code, headers_list, body, error_msg]` opens a TCP
  socket via `socket(2,1,0)` + `make_sockaddr_in` + `connect_socket`, sends
  `GET <path> HTTP/1.1\r\nHost: <host>\r\nUser-Agent: crossengin/0.1\r\n
  Accept: */*\r\nConnection: close\r\n\r\n`, loops `recv_data` until EOF or
  `max_bytes+8K` cap is reached, then splits on `\r\n\r\n` (with `\n\n`
  fallback), parses `HTTP/1.x NNN ...` status, accumulates `Name: value`
  headers; `http_header_get(headers, name)` is case-insensitive;
  `http_is_redirect(status_code)` classifies 3xx (callers re-issue with
  Location). DNS workaround for NOVA having no getaddrinfo: dotted-quad
  hosts (e.g. `127.0.0.1`) work directly; named hosts must be in the
  process-local cache populated from env
  `HTTP_DNS_HOST_TO_IP="host:ip,host:ip"` at first lookup. Unknown hosts
  return the canonical `HTTP_ERR_DNS` error and a deliberately loud
  pointer at `TLS_AUDIT.md`. Mode 3 wiring lives in `internet_fetch.nova`:
  new `if_dispatch_transport(url, max_bytes) -> [tag, status, body, err]`
  returns `IF_TRANSPORT_HTTP_OK` (1) for successful `http://`,
  `IF_TRANSPORT_HTTP_ERR` (2) for plain-HTTP transport failure,
  `IF_TRANSPORT_DEFERRED` (3) for `https://` (caller falls back to
  `scripts/learn.sh` curl, unchanged), `IF_TRANSPORT_BAD_URL` (4) on
  malformed URL. The whitelist + rate-limit + cache pipeline is UNCHANGED
  -- callers still `if_permit` before and `if_complete` + `if_ingest`
  after. Acceptance: `tests/unit/test_http_client.nova` covers the parser
  matrix (full URL, default ports for http/https, no-path -> "/",
  authority-only with port, ftp:// scheme rejection, malformed inputs),
  DNS register + lookup (case-insensitive on host, bad-IP rejection,
  dotted-quad bypass), case-insensitive header lookup, 3xx redirect
  classifier, status-line parser (200 / 404 / 301 / no-text / bad
  cases), and the dispatcher branches (https deferred, malformed bad-url,
  http unresolved DNS) -- 59 assertions across 15 test functions.
  `tests/integration/scenario_j_http_client.sh` spawns `python3 -m
  http.server` on a per-run port (31000+), writes a known marker file,
  builds an inline NOVA driver under `tests/integration/_scenario_j_drivers/`
  that calls `if_dispatch_transport("http://127.0.0.1:PORT/test_html.html",
  4096)`, and asserts: NOVA exits 0, tag=1 (HTTP_OK), status=200, body
  contains the marker, err empty, body_len >= 50, plus bonus drivers for
  the bad-URL and https-deferred branches -- 9 assertions; SKIPs cleanly
  if python3 isn't available or `socket(2,1,0)` returns -1 (sandbox denies
  AF_INET). Verified locally: scenario_j passes 9/9 with python3 present.
  Production blocker still loud: HTTP_DNS_HOST_TO_IP is a manual table,
  not real DNS; full resolution + TLS is the 4-6-week call documented in
  TLS_AUDIT.md.
- P1.5 -- composite `/learn` kinds (batch URLs, RSS feed, recursive
  directory): **complete**. Extends the P15 dispatcher with three new
  prefix-detected source kinds, all sharing the same `_learn_tag` /
  `_admin_learn` pipeline:
  - `@/path/urls.txt` -- one URL per line; the bash side iterates and
    recursively self-calls per URL, then concatenates per-URL caches into
    `/tmp/crossengin_learn_batch_<basename>.txt`. Tag = `batch_<basename>`.
    The chat ingests the combined cache then re-derives each per-URL tag
    and ingests the individual cache too so each URL keeps its own
    `src:url:<tag>` attribution for meta-observer scoring.
  - `rss:URL` -- fetches the feed, parses up to `LEARN_RSS_MAX` (default 5)
    `<link>...</link>` (RSS) or `<link href="...">` (Atom) entries, then
    batch-ingests them. Tag = `rss_<host>`. Lossy regex parser is fine --
    the chat-side filter is the ground truth for triples.
  - `dir:/path/` -- recursively walks for `*.txt` + `*.md` files (find -type
    f, NUL-delimited so spaces survive), recursively self-calls per file,
    concatenates per-file caches into the combined cache. Tag =
    `dir_<basename>`.
  All composite kinds prepend their prefix BEFORE path-shape detection
  (`_learn_kind` now checks `@`/`rss:`/`dir:` before the `/abs`/`./rel`
  branches), so a directory called `./foo` is never misclassified as FILE.
  NOVA-side helpers `_tag_sanitise`, `_learn_tag_batch`, `_learn_tag_rss`,
  `_learn_tag_dir`, `_basename`, and `_learn_ingest_one` /
  `_learn_ingest_batch_per_url` live alongside the existing P15 helpers
  in `examples/crossengin_chat.nova` (no new admin commands, no new
  dispatch lines -- the existing `/learn` line in `_try_admin` calls the
  same `_admin_learn`). Acceptance:
  `tests/unit/test_learn_tag.nova` is now 40 assertions (+18: 6 new kind
  classifications plus 4 batch + 4 rss + 4 dir tag derivations);
  `scripts/learn_smoke_multi.sh` is now 6 source-kind cases + 4 negative
  cases (was 3 + 1) and verifies BATCH @-prefix, RSS feed parsing, DIR
  walk, plus error-out on missing list / missing dir / empty rss URL.
  Network-dependent steps (TOPIC, URL, RSS, BATCH-of-URLs) skip cleanly
  if curl can't reach Wikipedia.
- Phase 11 Tier-1 item #1 -- full SOUL + KGS subsystem blob serialization:
  **complete**. `snapshot_disk.nova` now round-trips every atom (label, kind,
  alpha/beta belief, owning KG label) and the full SOUL state (name, purpose,
  identity, mood valence/arousal, OCEAN, constitution rule list); old-format
  snapshots still parse but install zero atoms (legacy `kgs.atoms` is treated
  as a metadata-only hint). The chat's `/load` is now a real rehydrate that
  replaces SOUL fields in place and merges KGS atoms by label, including the
  LANG-atom lexical fixture (`ltype = LWORD`, char-vector embedding, sense
  xrefs to same-labeled concept atoms). Acceptance test passes: after
  `/teach widget` + `/save`, a re-launched chat with `/load` recognizes
  `widget` (`perceive(m=1,unk=0)`).
- Phase 11 P0.1 follow-up -- full EPISODIC + SYNAPSES + SELFMODEL section
  serialization: **complete**. The remaining three snapshot sections now carry
  their full payloads, closing the daemon-restart gap that previously lost
  every moment, synapse weight, and competence reading. EPISODIC persists per
  moment (timestamp, lifecycle PERCEIVED/SETTLED/CONSOLIDATED, valence/salience,
  the list of atom ids in the moment's trace) and per episode (id, tier
  RECENT/CONSOLIDATED/ARCHIVED, the moment id list); SYNAPSES persists
  (src, dst, weight, eligibility) for every live synapse with |weight| >=
  100 milli (default cut, auto-raised in 100-milli increments if the
  above-threshold count exceeds 50K to keep snapshots under ~2MB); SELFMODEL
  persists per-domain competence records (label, kind, reliability, evidence,
  derived tier). Restore policy is REPLACE on all three (the snapshot is the
  new ground truth on /load, not a merge target). Backwards compatibility:
  a snapshot with only `<section>.present 1` and no sub-fields parses cleanly
  as an empty section (same legacy-hint convention as `kgs.atoms`). New
  restore helpers added (kept small, additive, documented): `ms_clear` +
  `ms_restore` in `moment_stream.nova`, `em_clear` + `em_restore` in
  `episode_storage.nova`, `syn_set_eligibility` + `syn_restore` in
  `synapse_graph.nova`, `self_model_clear` + `self_model_restore` in
  `competence_tracker.nova`. The chat's `_build_snapshot`, `_admin_save`,
  and `_admin_load` thread the moment stream, episodic memory, the reasoning
  part's synapse graph, and a self-model through the new section helpers;
  the daemon's `_checkpoint` does the same. `/status` gains three new lines
  (`moments`, `synapses`, `selfmodel`) so a post-restart `/load` is
  immediately verifiable. Acceptance test passes: `printf
  '/teach widget\nwidget\nwidget gadget\nwidget gadget fever\n/save\n/quit\n'
  | ./bin/crossengin-chat` followed by `printf '/load\n/status\n/quit\n' |
  ./bin/crossengin-chat` reports `moments : 3 moment(s), 3 episode(s)` plus
  `knowledge: 574 atoms` and the right `audit: K decision-log entries`.
  Acceptance: `tests/unit/test_snapshot_episodic.nova` (51 assertions),
  `tests/unit/test_snapshot_synapses.nova` (43 assertions including the
  threshold-cut behavior + the inhibitory-weight case + idempotent re-apply),
  `tests/unit/test_snapshot_selfmodel.nova` (38 assertions covering the
  three competence kinds, derived-tier survival, REPLACE policy, legacy
  presence-only stub) -- 132 new assertions across the three suites;
  `tests/integration/scenario_a2_full_state.sh` extends scenario A with 16
  assertions for SIGKILL durability of the new sections.

Top-level [`MANUAL.md`](./MANUAL.md) walks through running and testing locally
end-to-end (build, all three artifacts, the test suite, writing a new test).
The daemon boots from [`src/seed/first_atoms.nova`](./src/seed/first_atoms.nova),
which installs the foundational concepts the agent knows about itself (self,
user, query, response, help, ok), the operators that connect them, the two
output syntax patterns, and a tiny medical demo chain (fever -> infection =>
treat). Everything else is learned at runtime via the learning loops.

## Completed modules — Phase 1 (substrate kernel)

All under `src/substrate/`. Each compiles with `nova build` and has a matching
`tests/unit/test_<module>.nova` suite (happy path + edge + failure cases).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| node_pool_manager.nova | 0006, 0002, 0010 | 40 | done |
| signal_dispatch.nova | 0008, 0002 | 49 | done |
| synapse_graph.nova | 0007, 0002 | 55 | done |
| first_nodes.nova | 0010, 0006 | 29 | done |
| part_registry.nova | 0001, 0002 | 26 | done |
| part_lifecycle.nova | 0001 | 21 | done |
| gate_router.nova | 0009, 0045 | 24 | done |
| resonance_engine.nova | 0001, 0007, 0008 | 20 | done |
| tick_driver.nova | 0006, 0001 | 20 | done |

Also delivered:
- `tests/ce_test.nova` — shared assertion harness (lives outside `tests/unit/`
  so the runner does not treat it as a test).
- `examples/kernel_selfcheck.nova` — the runnable v0.1 artifact (`make run` /
  `make install`); boots all 9 modules end-to-end and asserts liveness.
- `tests/benchmark/bench_tick_rate.nova`, `tests/benchmark/bench_node_throughput.nova`.
- `make benchmark` target added to the Makefile.
- Docs: `docs/runbook/{build,test,run,troubleshooting}.md`,
  `docs/design/{overview,data_flow}.md`.

## Completed modules — Phase 3 (knowledge representation)

All under `src/kg/`, each compiling with a matching unit-test suite. Built on
the substrate's milli-fixed-point convention; belief and vector cosine are
implemented in-house (see NOVA blockers).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| atom_store.nova (P2.4 added `label_hash` + `LABEL_BUCKETS` for the hash index) | 0016, 0023 | 42 | done |
| multi_kg_manager.nova (P2.4: hash + kind indexes, `kg_remove_atom`, `kg_rebuild_index`, `kg_atoms_by_kind`) | 0004, 0016 | 23 | done |
| atom_store_index (P2.4 hash + kind indexes: separate test suite) | 0016, 0049 | 61 | done |
| cross_kg_references.nova | 0017, 0004 | 20 | done |
| schemas.nova | 0018 | 13 | done |
| concept_layer.nova | 0018 | 28 | done |
| skills_kg.nova | 0019 | 26 | done |
| competence_tracker.nova | 0020 | 27 | done |

Also delivered: `tests/benchmark/bench_kg_query.nova` (insertion, id/label
lookup, observation throughput).

## Completed modules — Phase 2 (reader and language)

Language atoms under `src/language/`; the five-stage reader under `src/reader/`.
Each compiles with a matching unit-test suite. No LLM is touched (ADR-0014); the
reader operates purely over the language KG, concept layer, and substrate
signals.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| language/word_atoms.nova | 0015 | 20 | done |
| language/phoneme_atoms.nova | 0015 | 12 | done |
| language/syntax_atoms.nova | 0015, 0013 | 14 | done |
| reader/lexical_anchor.nova | 0012 (stage 1), 0011 | 19 | done |
| reader/context_bias.nova | 0012 (stage 2) | 9 | done |
| reader/spreading_activation.nova | 0012 (stage 3), 0017 | 9 | done |
| reader/neighborhood.nova (Phase 14 Tier-2 #2: structural-neighborhood; P2.1+P2.2 follow-up adds find_neighbors_full with cofire + slot side-indices) | 0012, 0017, 0031, 0015, 0021 | 45 | done |
| reader/cofire_index.nova (P2.1: co-fire side-index, atom-pair counts from settled moments) | 0021, 0012 | 35 | done |
| reader/slot_index.nova (P2.2: syntactic-slot side-index, (pattern, role) filler histogram from output generation) | 0015, 0013, 0012 | 23 | done |
| reader/coherence_check.nova | 0012 (stage 4) | 11 | done |
| reader/fetch_route_learn.nova | 0012 (stage 5) | 11 | done |
| reader/reader.nova | 0011, 0012 | 13 | done |

README updated to v0.3.

## Completed modules — Phase 4 (memory and learning)

Episodic modules under `src/parts/episodic/`; learning fabric under
`src/learning/`. Each compiles with a matching unit-test suite. Kept in the
kg / self-contained layer (no direct substrate-node imports) to respect NOVA
blocker #10; node-level values (novelty, activation, error, modulator) are
passed as parameters.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| episodic/moment_stream.nova | 0021 | 29 | done |
| episodic/episode_storage.nova | 0022 | 19 | done |
| episodic/consolidation.nova | 0022, 0025 | 10 | done |
| learning/bayesian_updates.nova | 0023, 0029 | 20 | done |
| learning/predictive_coding_runtime.nova | 0024 | 18 | done |
| learning/atom_birth_monitor.nova | 0025 | 15 | done |
| learning/atom_death_monitor.nova | 0025 | 18 | done |
| learning/plasticity_modulation.nova | 0035, 0007 | 10 | done |

README updated to v0.4.

## Completed modules — Phase 5 (self-directed learning)

All under `src/learning/`, each compiling with a matching unit-test suite. Kept
self-contained or kg-layer-only (NOVA blocker #10). The internet fetch transport
(TLS byte retrieval) is a deferred seam -- NOVA enhancement #11; the pipeline
(whitelist, rate limit, cache, validation, ingestion) is complete and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| confidence_thresholds.nova | 0030 | 23 | done |
| source_whitelist.nova | 0028 | 14 | done |
| source_authority.nova | 0029 | 22 | done |
| self_learning_triggers.nova | 0026 | 27 | done |
| ask_user_to_teach.nova | 0027 | 19 | done |
| internet_fetch.nova | 0028, 0029 | 20 | done |

README updated to v0.5.

## Completed modules — Phase 6 (cognitive subsystems)

Five subsystems under `src/parts/`, each module compiling with a matching
unit-test suite. Goals/soul/emotion are self-contained; reasoning/imagination
import the kg layer on a single prefix (NOVA blocker #10).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| goals/goal_engine.nova | 0033 | 20 | done |
| goals/drive_generators.nova | 0033 | 15 | done |
| goals/goal_persistence.nova | 0033 | 11 | done |
| soul/identity.nova | 0034 | 13 | done |
| soul/state.nova | 0034 | 11 | done |
| soul/values.nova | 0034 | 8 | done |
| soul/constitution.nova | 0034, 0045 | 11 | done |
| soul/themes.nova | 0034 | 7 | done |
| soul/loyalty.nova | 0034 | 9 | done |
| soul/goals_in_soul.nova | 0034 | 7 | done |
| emotion/appraisal.nova | 0035 | 14 | done |
| emotion/ocean_conditioning.nova | 0035 | 8 | done |
| emotion/plasticity_mod.nova | 0035, 0007 | 7 | done |
| reasoning/reasoning_atoms.nova | 0031 | 13 | done |
| reasoning/reasoning_module.nova | 0031 | 12 | done |
| imagination/imagination_engine.nova | 0032 | 14 | done |
| imagination/forward_sim.nova | 0032 | 7 | done |
| imagination/counterfactual.nova | 0032 | 8 | done |
| imagination/dream_recombination.nova | 0032 | 6 | done |
| imagination/scenario_planner.nova | 0032 | 6 | done |

README updated to v0.6.

## Completed modules — Phase 7 (agent architecture)

Scheduler under `src/scheduler/`, loops under `src/agent/`, meta under
`src/parts/meta/`. Each module compiles with a matching unit-test suite. Design
that respects NOVA blocker #10: each loop is a self-contained unit over the
shared `loop_coordination` blackboard (one subsystem import, one node_pool
path); the scheduler is substrate-subtree only. Wiring all loops + the scheduler
into one program is the Phase 10 `main` (needs a `nova_packages/` shim).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| scheduler/event_dispatch.nova | 0037 | 10 | done |
| scheduler/tick_loop.nova | 0037 | 8 | done |
| scheduler/hybrid_scheduler.nova | 0037, 0036 | 11 | done |
| agent/loop_coordination.nova | 0036 | 16 | done |
| agent/loop_perception.nova | 0036 | 4 | done |
| agent/loop_memory.nova | 0036 | 4 | done |
| agent/loop_reasoning.nova | 0036 | 3 | done |
| agent/loop_emotion.nova | 0036, 0035 | 3 | done |
| agent/loop_goals.nova | 0036, 0033 | 3 | done |
| agent/loop_action.nova | 0036, 0013 | 4 | done |
| agent/loop_imagination_idle.nova | 0036, 0032 | 2 | done |
| parts/meta/self_model_query.nova | 0038 | 9 | done |
| parts/meta/theory_of_mind.nova | 0039, 0044 | 13 | done |
| parts/meta/long_horizon_goals.nova | 0040 | 9 | done |
| parts/meta/reflection_loop.nova | 0032, 0023 | 16 | done |
| parts/meta/meta_observer.nova (Phase 13 Tier-2 #1: per-source promotion/atrophy observer) | 0050 | 39 | done |

README updated to v0.7.

## Completed modules — Phase 8 (safety and audit)

Safety stack under `src/safety/`, the audit/decision log under `src/audit/`.
Each module compiles with a matching unit-test suite. The whole safety stack is
a single clean dependency chain (no blocker #10): `reversibility_classifier`
(also home to the shared `ACT_*` constants) <- `permission_tiers` <-
`constitutional_filter`; the audit log layers `decision_log` <- `audit_writer`/
`audit_reader`; `override_mechanism` composes the kg-belief, goal-engine, and
audit subtrees (three disjoint subtrees, so they coexist). The gate chain is
`safety_gate` (constitutional veto -> hard stop -> permission tier, which folds
the reversibility floor); the audit log is append-only and hash-chained
(tamper-evident: mutation, reorder, and tail-truncation all fail `dl_verify`).
Pure substrate, NO LLM (ADR-0014). The fsync-backed durable store (ADR-0043
write path) and the process-exit/snapshot syscalls (ADR-0044 kill) are the
documented runtime seams (NOVA enhancements #9/#10); all decision logic is real
and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| safety/reversibility_classifier.nova | 0042, 0041 | 21 | done |
| safety/permission_tiers.nova | 0041, 0042 | 24 | done |
| audit/decision_log.nova | 0043 | 25 | done |
| audit/audit_writer.nova | 0043 | 25 | done |
| audit/audit_reader.nova | 0043, 0038 | 14 | done |
| safety/override_mechanism.nova | 0044, 0043, 0023 | 27 | done |
| safety/constitutional_filter.nova | 0045, 0041, 0042 | 22 | done |

README updated to v0.8.

## Completed modules — Phase 9 (IO and effectors)

Output generation and effectors under `src/io/effectors/`, the input transducer
under `src/io/transducers/`. Each module compiles with a matching unit-test
suite. Layering for NOVA blocker #10: `output_generation` is the language
subtree only (it reaches words/syntax via a single import prefix);
`effector_gate` composes the safety subtree (`constitutional_filter`) with the
standalone `decision_log` — two disjoint trees, so no double-include (it
deliberately does NOT also import `audit_writer`, whose `permission_tiers` path
would collide, and rebuilds the descriptor/append locally); `input_transducer`
is standalone.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| io/effectors/output_generation.nova | 0013, 0015, 0007 | 10 | done |
| io/effectors/effector_gate.nova | 0041..0045, 0043, 0013 | 23 | done |
| io/effectors/audio_synth.nova (Phase 19 Tier-4 #1: audio modality bridge -- WAV + sine + phoneme synth) | 0014, 0015, 0013 | 52 | done |
| io/effectors/audio_speak.nova (Phase 19 Tier-4 #1: audio modality bridge -- espeak/aplay escalation) | 0014 | 0 | done |
| io/transducers/input_transducer.nova | 0014, 0011, 0012, 0021 | 19 | done |
| io/transducers/kg_sync.nova (Phase 20 Tier-4 #2: distributed-substrate seam; P1.3 v2 upgrade -- N-subs + bidir + reconnect + auth + conflict) | 0014, 0016 | 169 | done |
| io/transducers/http_client.nova (P1.4: plain-HTTP/1.1 in-process client + dispatcher seam; HTTPS deferred -- see TLS_AUDIT.md) | 0028, 0014 | 59 | done |

Pure substrate, NO LLM (ADR-0014): `output_generation` produces text by the
reverse of comprehension (intent -> real word atoms -> learned syntax ordering),
`effector_gate` is the chokepoint that runs the Phase 8 `safety_gate` and writes
intent-before/outcome-after decision-log entries (the SPEAK effector is fully
implemented; governed speak vetoes forbidden output by its text). File/network/
message transport and audio STT/TTS are the documented runtime seams (NOVA
enhancements #11/#14); all gate/log/generation logic is real and tested.

Phase 20 / Tier 4 item #2 -- distributed-substrate seam: **complete**.
P1.3 upgraded the protocol to v2 (N-subscriber fan-out, bidirectional
PUB-from-subscriber, three new event kinds PROMOTE / ATROPHY / DELETE,
auth handshake via `CE_KGSYNC_TOKEN`, reconnect-on-disconnect with
`SUB FROM <id>` cursor resume, and conflict-resolution merge by averaged
belief; v1 HELLO/OK strings are still recognised). The original artifact
shape is preserved: `src/io/transducers/kg_sync.nova` defines a text
wire protocol (one op per line, `\n` terminated) with the publisher +
subscriber socket halves; two artifacts compose it end-to-end:
`examples/crossengin_kg_publisher.nova` -> `bin/crossengin-kg-publisher`
(binds 127.0.0.1:8766 by default, accepts `CE_KGSYNC_SUBS` subscribers --
default 1 for backwards compat -- reads labels from stdin, births an
atom + fans it out to every live sub in a round-robin send loop, prunes
subs whose `last_active` is older than 30s) and
`examples/crossengin_kg_subscriber.nova` -> `bin/crossengin-kg-subscriber`
(dials the publisher, sends `HELLO ce-kg-sync v2[ token=<TOK>]` +
`SUB *` or `SUB FROM <id>`, reads + applies events, transparently
reconnects on EOF, and may teach back via stdin -> PUB). Wire ops:
`HELLO ce-kg-sync v{1|2}[ token=<TOK>]`, `OK v{1|2} protocol accepted`,
`SUB *`, `SUB FROM <id>`, `ATOM kg id kind alpha beta label`, `PUB
kg id kind alpha beta label`, `PROMOTE kg id alpha beta`, `ATROPHY
kg id`, `DELETE kg id`, `ACK <id>`, `BYE`, `ERR <reason>`, `ERR auth`.
Defaults: bind `127.0.0.1` (opt in to broader via `CE_KGSYNC_BIND=0.0.0.0`,
mirroring web.py); port 8766 (override via `CE_KGSYNC_PORT`);
subscriber host `127.0.0.1` (override via `CE_KGSYNC_HOST`);
expected-subs `1` (override via `CE_KGSYNC_SUBS`); token unset
(override via `CE_KGSYNC_TOKEN` -- if unset, anonymous). The main
`bin/crossengin` daemon is intentionally NOT modified -- rolling
kg_sync into its idle path is a future enhancement.
Acceptance: `tests/unit/test_kg_sync.nova` covers format/parse round-trip
for ATOM + PUB + PROMOTE + ATROPHY + DELETE, malformed line rejection
(missing fields, wrong op, non-numeric numerics, illegal label chars,
empty fields), CRLF + LF eol handling, dash/underscore label preservation,
the IP-string -> packed-int helper, the top-level `_parse_line`
classifier, HELLO token extraction, env helpers, subscriber record + staleness,
the four `sync_apply_*` policies (including the merge), and connection-state
cursor accessors -- 169 assertions across 49 test functions;
`tests/integration/scenario_g_kg_sync.sh` exercises v1 single-sub
(13 assertions), `tests/integration/scenario_g2_kg_sync_multi.sh`
exercises v2 (24 assertions: 3 subs fan-out + bidir + reconnect-pin +
auth gate + conflict merge). Sandbox-quirk handling: both scripts
print a `SKIP` block if `socket(2,1,0)` returns -1 so a denying sandbox
keeps the suite green.
Sample manual smoke: `./bin/crossengin-kg-subscriber > /tmp/sub.out &`
then `printf 'widget\ngadget\nfever\n' | ./bin/crossengin-kg-publisher`
yields three `recv kg=language id=N label=...` lines in `/tmp/sub.out`,
verified locally; with `CE_KGSYNC_SUBS=3` the publisher fans the same
labels to three subscribers.

README updated to v0.9.

## Completed modules — Phase 10 (persistence + spine artifact)

Persistence under `src/persistence/`, plus the runnable companion-spine artifact.
Each module compiles with a matching unit-test suite. The snapshot writer/reader
are the generic ADR-0048 CONTAINER (tagged/versioned, fixed ordered sections,
each an opaque subsystem blob), so they stay standalone (no subsystem imports,
no blocker #10) and compose into any binary. The load-bearing part is enforced
in the reader: the mandatory rehydration order soul -> KGs -> episodic (refuse
KGs before soul, episodic before KGs), so the constitution is live before any
atom is admitted and no moment dangles. The decision log (ADR-0043) is
durable-but-separate and is not rolled back by a restore. Crash-safe disk write
(temp -> fsync -> atomic rename -> parent-dir fsync) is now realized in
`snapshot_disk.nova` against NOVA's sys_fsync (74) and sys_rename (82); the
chat `/save` and `/load` admin commands exercise the seam end-to-end. Subsystem
byte-serialization of the section blobs is still a deferred runtime seam --
the framed image round-trips today via a line-oriented text format (one
`key value` pair per line) that captures the well-known SOUL/KGS fields and the
presence flag for the other sections.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| persistence/snapshot_writer.nova | 0048 | 27 | done |
| persistence/snapshot_reader.nova | 0048 | 25 | done |
| persistence/snapshot_disk.nova | 0048 | 31 | done |
| persistence/snapshot_disk.nova (Phase 11: full SOUL + KGS blob serialize/apply) | 0048 | 72 | done |

Also delivered (runnable artifacts via `make install`):
- `examples/kernel_selfcheck.nova` -> `bin/crossengin-selfcheck` — the substrate
  kernel spine.
- `examples/companion_spine.nova` -> `bin/crossengin-spine` — the safety + IO +
  persistence spine.
- `examples/crossengin_daemon.nova` -> `bin/crossengin` — **the whole agent in
  one process**, driven by the ADR-0037 hybrid scheduler as a real event-driven
  loop (not a fixed script). Input arrives as EV_MESSAGE events; each scheduler
  step drains <=1 event and ticks the substrate. On an event the agent runs the
  full ADR-0036 six-loop cycle -- perception (five-stage reader) -> memory
  (episodic) -> reasoning (forward-chaining) -> emotion -> goals -> action (gated
  output) -- and AFFECT EMERGES FROM ITS OWN COMPREHENSION (how much it
  understood), not scripted numbers; that mood becomes the tick's plasticity
  modulator and a predictive-coding residual its error. A run of empty ticks
  throttles the scheduler 100Hz -> 10Hz idle, which gates imagination (over the
  lingering active set) and triggers a checkpoint; on shutdown the agent reboots
  by rehydrating in mandatory order (soul -> KGs). The reader, reasoning
  operators, and imagination patterns share ONE concept KG, so a read word is a
  valid reasoning seed and imagination state -- a coherent pipeline. Output now
  emerges from the substrate's reasoning: after the loops produce conclusions, a
  reverse concept->word lookup (`gen_word_for_concept`) finds the naming word and
  speaks it through the gated effector -- the agent SAYS WHAT IT CONCLUDED, not a
  hard-coded literal, no LLM picking the wording. Observed run: on "fever" the
  agent derives infection -> treat via the causal/imply operators and says "see
  treat"; on the "exfiltrate" message the constitutional gate vetoes; then
  idle@10Hz -> imagination 3 states + checkpoint. Prints `crossengin: OK`.
  Unblocked by the blocker #10 toolchain fix (below). Events are also routed
  through `gate_router` -- SENSORY on percept, CURIOSITY on unknown tokens, GOAL
  on successful action -- and the destination parts receive `part_inject`, so
  the substrate parts actually wake to stimuli rather than ticking idle
  (ADR-0009 wiring closed). The agent GROWS ITS KGs AT RUNTIME: each unknown
  surface form submits an SLT_UNKNOWN_QUERY trigger (ADR-0026); at idle the
  arbiter drains the queue and `au_ingest` (ADR-0027, Beta(4,1) user-taught
  prior) creates a new word atom + concept binding. A verification event posted
  with one of the freshly-taught words is then fully comprehended (matched=2 on
  "the keys" after teaching), closing the perceive -> learn -> perceive cycle
  end-to-end in one run.

  Composing every subsystem also surfaced the one genuine cross-module name
  collision in the codebase (blocker #7): `E_TAG` was defined in both
  `audit/decision_log.nova` (unused there) and `parts/episodic/episode_storage.nova`.
  Fixed by removing the dead constant from `decision_log` (offset 0 is documented
  as the `LOG_ENTRY` tag). A full-codebase scan confirms no other duplicate
  top-level symbol remains.

README updated to v1.0.

## Completed modules — Seed (boot state)

The cold-boot seed under `src/seed/`. Loaded by the daemon at startup to install
the foundational concepts, core English vocabulary, output syntax patterns,
reasoning operators, imagination patterns, and the medical-demo chain (fever ->
infection => treat). 572 atoms across self/pronoun/verb/noun/health/daily/etc.;
everything else is learned at runtime via the learning loops.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| seed/first_atoms.nova | 0010, 0015, 0016, 0017, 0031, 0032, 0034 | 18 | done |

## Completed modules — Phase 18 (multi-tenant session foundation)

Per-tenant `Session` value + linear registry under `src/session/`. The Session
struct is a flat 15-slot list bundling every piece of state today's
single-Aurora daemon initialises in `main()` (soul, KG registry, reasoning /
language / imagination / reflection KGs, blackboard ctx, decision log, goal
engine, meta-observer, hybrid scheduler) plus id / name / created_at /
last_active. The module is dependency-free -- every subsystem handle is stored
opaquely, so the caller (daemon, chat, future router) constructs the
subsystems exactly as before and just wraps them. The registry walks linearly
(N is small per ADR-0051 -- 1..100 tenants -- and the NOVA builtin map caps
at 16 keys per blocker #1). Scheduler is per-session by design (clean
isolation; each tenant has its own tick clock and idle counter).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| session/session.nova | 0051 | 66 | done |

The daemon and chat are NOT yet routed through the registry: this session is
the foundation pass. Both files carry a documentation-only comment block
above their boot sequence pointing at `session_make` / `sreg_register` for a
follow-up agent to wire.

## Partially completed modules

None. There are no stubs and no `TODO`s in committed code. Every Phase 1–10
module is fully implemented and tested. No `.pending` files were needed. The one
thing NOT yet built is the **unified single-process daemon** (all subtrees in one
binary) — this is an integration limitation of the current NOVA backend (blocker
#10), not a missing module; the verified unblock recipe is below.

## Modules not yet started (in plan order)

- None. All 50 ADRs across all 10 phases have an implemented, tested module.
  Remaining work is integration (the unified daemon) + landing the documented
  runtime seams; see the recommendation section.

## Tests status

- Total unit suites: 114 (114 PASS, +1 from P2.4 `test_atom_store_index.nova`, +2 from P2.1/P2.2 `test_cofire_index.nova` and `test_slot_index.nova`); **+82 assertions added by P1.1/P1.6** (54 in `test_meta_observer_feedback.nova`, 28 in `test_atom_death_attribution.nova`), **+59 assertions added by P1.4** (`test_http_client.nova`), **+61 assertions added by P2.4** (`test_atom_store_index.nova`), **+58 + 15 assertions added by P2.1/P2.2** (35 in `test_cofire_index.nova`, 23 in `test_slot_index.nova`, +15 in `test_neighborhood_activation.nova` going 30 -> 45).
- Runnable artifacts: 5 — `examples/kernel_selfcheck.nova` (substrate kernel), `examples/companion_spine.nova` (safety+IO+persistence spine), `examples/crossengin_daemon.nova` -> `bin/crossengin` (the whole agent in one process), `examples/crossengin_kg_publisher.nova` -> `bin/crossengin-kg-publisher` and `examples/crossengin_kg_subscriber.nova` -> `bin/crossengin-kg-subscriber` (Phase 20 / Tier 4 #2 distributed-substrate seam); all build via `make install` and run to a passing self-report.
- Toolchain change: a one-function fix to `amoufaq5/nova` `src/compiler/compiler.nova` (import-path canonicalization, blocker #10) on branch `claude/festive-franklin-PP7mW`; rebuild with `cd /home/user/NOVA && make`, verified by `make self-host` + `make test` and by re-running all 88 CrossEngin suites.
- Total integration tests: 18 scripts under `tests/integration/` covering 11 multi-step scenarios (durability across SIGKILL, decision-log durability across SIGKILL [P0.7], neighborhood paraphrase, multi-source `/learn`, `/meta` table, constitutional veto, web frontend smoke, distributed KG sync, session switch isolation, web cookie isolation, plain-HTTP client loopback [P1.4], Prometheus `/metrics` scrape endpoint [P2.9 -- 35 assertions]) and 5 admin-command edge-case scripts. Run with `make integration`.
- Total benchmarks: 3 (`bench_tick_rate`, `bench_node_throughput`, `bench_kg_query`).
- All passing: **yes**. Failures: none.
- Latest benchmark numbers (NOVA v0.x, single container, second-resolution
  clock): single-part ~60k ticks/sec; full 7-part substrate ~35k part-ticks/sec;
  node throughput ~768k integrations/sec; KG O(1) id-lookup ~300k/sec.
  **P2.4 (this revision):** KG label lookup is now O(1) amortized via a hash
  index inside each KG (`bench_kg_query`'s head-to-head section): 1M lookups
  over a 1000-atom KG -- **indexed ~170ms (~6M lookups/sec) vs scalar walk
  ~8700ms (~115k lookups/sec); ratio ~50x**. The legacy O(N) linear scan is
  preserved as a backwards-compat fallback for KGs rehydrated from snapshots
  predating P2.4. These bound the current scalar implementation.

## ADR ambiguities encountered

1. **resonance_engine has no dedicated ADR.** The master plan lists
   `resonance_engine.nova` in Phase 1, but ADRs 0001–0010 define no separate
   resonance primitive. Interpretation: implemented resonance as the
   bidirectional co-activation reinforcement of reciprocally connected nodes
   (the `<=>` dynamic), grounded in ADR-0001 (emergent dynamics), ADR-0007
   (synapse weights/eligibility), and ADR-0008 (XSIG_BIND assemblies). Revisit
   if a future ADR specifies different resonance semantics.
2. **Phase ordering vs. dependencies.** Phase 2 (reader) precedes Phase 3
   (atoms/KG) and Phase 4 (moments), yet the five-stage reader (ADR-0011/0012)
   anchors input to *word atoms* and spreads activation over a *KG* — both
   later-phase primitives. Recommendation below resolves this.
3. **Persistence: "day one" rule vs. Phase 10 ordering.** The master plan's
   rule 8 says every state-bearing module should implement save/load "from day
   one," but its own phase plan places persistence at Phase 10, and ADR-0048
   specifies a *single ordered* snapshot/rehydration scheme (soul → KGs →
   episodic) rather than ad-hoc per-module files. The Phase 1 substrate is
   therefore in-memory only; bolting on per-module save/load now would risk
   diverging from the ADR-0048 design. Decision: defer persistence to a coherent
   Phase 10 implementation against ADR-0048, but keep node/synapse/part state in
   plain integer arrays and stable first-node index ranges precisely so it
   snapshots cleanly. Flagged for human review.
4. **Scale targets are aspirational for v0.x NOVA.** ADRs target 1M nodes/part,
   ~1000 synapses/node, 100Hz wall-clock, true concurrency. Phase 1 implements
   the correct *semantics* at configurable capacity; the scale/throughput/
   concurrency aspects are the upstream NOVA enhancements in `nova-deps.toml`
   (#1–#14), cited per module header. No ADR was contradicted.
5. **Source-tier weights differ between ADRs.** The ADR-0023 narrative implies
   evidence weights A=1.0/B=0.6/C=0.3 (and user=1.5), while ADR-0029 (the
   authoritative source-authority ADR) specifies A=1.0/B=0.5/C=0.2 with alpha/
   beta increments 3x the weight. Resolution: `bayesian_updates` keeps the
   generic ADR-0023 `SRC_*` weights (it accepts any explicit weight), and
   `source_authority` implements the authoritative ADR-0029 numbers; fetched
   evidence is ingested with the ADR-0029 increment, user-taught with the
   ADR-0027 Beta(4,1) prior. Flagged for human review (align the two ADRs).

## NOVA blockers and footguns (important — read before continuing)

The CrossEngin spec assumes "NOVA v4.1 + N1–N29"; the actual toolchain is the
self-hosting NOVA in the sibling checkout (launcher reports v0.9.0, core
v0.2.0). It builds and runs CrossEngin fine, but these real toolchain behaviors
shaped the implementation and must be respected going forward:

1. **Builtin `map` caps at 16 keys — hard hang past that.** Inserting a 17th
   distinct key into a `map_new()` map linear-probes forever (no resize).
   Discovered when a synapse graph with >16 source nodes hung. **Workaround
   applied:** synapse adjacency, the part registry, and the gate table are now
   id/type-indexed *arrays*, not maps (this is also more ADR-faithful: CSR by
   source, O(1) typed dispatch). **Do not** use the builtin map for any set that
   can exceed 16 distinct keys. (Upstream: NOVA map needs auto-resize.)
2. **Undefined function calls segfault — no link error.** Calling a function
   that was never imported compiles silently and crashes at runtime. Import
   every module whose functions you call. (Cost me a debugging cycle on the
   self-check.)
3. **`map_has` treats a stored value of 0 as absent.** Avoid 0-valued map
   entries, or store `value+1`. (Now moot since we avoid maps, but true.)
4. **`float_*` builtins are IEEE-754 doubles, not the "scaled-by-1000"
   the language reference implies.** The substrate uses integer milli-fixed-point
   (`fp_mul`, scale 1000) exclusively and never touches `float_*`. Keep doing
   this for determinism.
5. **stdout is block-buffered; flushes on exit.** A hung program prints nothing,
   even past the hang point. Bisect hangs by making the suspect region exit.
6. **No sub-second clock.** Only `time()` (epoch seconds) exists; benchmarks run
   enough work to span ≥1s. A real 100Hz wall-clock pacer (ADR-0037) needs a
   finer timer — NOVA enhancement #5.
7. **Global names are one flat namespace across imports.** Two files defining
   the same top-level `let`/`fn` name collide at assembly time. Prefix module
   constants (we use `NS_`, `SG_`, `PART_`, `GATE_`, `XSIG_`, `TD_`, ...).
8. **Reserved word `asm`.** Cannot be used as an identifier.
9. **NOVA's knowledge modules do not std-import cleanly (v0.x).** `core/belief.nova`
   is not in the std-package registry (segfaults on use); `import "std/embed"`
   fails with duplicate-symbol link errors; `import "std/map"` segfaults the
   *compiler*. **Workaround applied (Phase 3):** CrossEngin implements its own
   minimal alpha/beta belief and integer cosine vectors in `atom_store.nova`
   (milli-fixed-point, same semantics as `core/belief.nova`), and uses id-indexed
   lists + linear-scan for name lookup. `contains()` does work for string lists.
10. **[FIXED in the toolchain]** Import dedup *was* by accumulated path string,
   not canonical path: a shared module reached via two different relative-path
   accumulations (e.g. `.../kg/../substrate/node_pool_manager.nova` via the kg
   subtree and `.../substrate/node_pool_manager.nova` via a substrate sibling)
   was included *twice* -> duplicate-symbol link errors, because NOVA did not
   normalize `..`. **Fix (this session, in the `amoufaq5/nova` repo on branch
   `claude/festive-franklin-PP7mW`):** added `normalize_path()` to
   `src/compiler/compiler.nova` and applied it to the relative-import dedup key
   (`imp_full`) in `_resolve_import_inner`, so `..`/`.` are collapsed before both
   the `already_imported` check and the propagated base_dir. Rebuilt the
   self-hosting compiler (`make bin/nova`), verified self-hosting (stage2 ==
   stage3) and NOVA's own tests, and confirmed all 88 CrossEngin suites still
   pass and the previously-colliding cross-subtree combos now link. This is what
   made the unified `bin/crossengin` daemon possible. The notes below preserve
   the original constraint for historical context.

   ORIGINAL CONSTRAINT (now resolved):
   **Consequence (Phase 2):** the reader stays within the kg + signal_dispatch
   layer (signal_dispatch is standalone, so it does not drag node_pool); it does
   NOT import the substrate part registry / gate router. Mapping the reader's
   symbolic route targets to gate-routed part signals is therefore deferred to
   the agent layer (Phase 7), which is the right layering anyway. When Phase 7
   must bridge subtrees, either route everything through one subtree's import
   prefix, or introduce a `nova_packages/` shim so shared modules resolve to one
   canonical string.
11. **Large-magnitude integer multiply inside a loop miscompiles (segfault).**
   Discovered (Phase 8) building the decision-log hash chain. A multiply whose
   product is large (empirically &gt;~1e12, and reliably so when a large literal/
   constant multiplier like 1000003 is used) crashes at runtime *when it is
   inside a `while` loop*; the identical multiply outside a loop, and small-
   multiplier multiplies (e.g. `*31`, `*131`) inside loops, are fine. Modulo with
   a large divisor is fine on its own. NOVA integers are 64-bit (1e10/1e12
   multiplies print correctly outside loops), so this is a loop-body codegen/
   register bug, not an overflow. **Workaround applied:** `decision_log`'s rolling
   hash uses multiplier 131 and modulus 1000003 (prime) and folds a pre-built
   flat field list with an *inlined* step (no helper call, no large product in
   the loop) — every intermediate stays &lt; ~1.3e8. Keep loop-body arithmetic
   small; precompute large constants outside loops.

None of these is a hard blocker. #10 is now **fixed in the toolchain** (see
above). The ones most likely to constrain further work are #1/#6 (scale + a
real sub-second clock) and #9/#11 (durable I/O, loop-body multiply codegen); all
have upstream-enhancement entries.

## Recommended next session start point

All 50 ADRs across all 10 phases have an implemented, tested module, AND they now
assemble into one unified process (`bin/crossengin`). What remains is depth, not
breadth — two areas.

### 1. Unified daemon: six loops + event/idle scheduler wired; remaining = grounding + real I/O source

The cross-subtree assembly is shipped (`examples/crossengin_daemon.nova` ->
`bin/crossengin`) and now runs the **full ADR-0036 six loops driven by the
ADR-0037 event/idle hybrid scheduler**: input as EV_MESSAGE events, 100Hz active
processing -> 10Hz idle throttle -> imagination + checkpoint, with affect emerging
from the agent's own comprehension and a boot(cold)/shutdown(checkpoint)/reboot
(rehydrate) lifecycle. Done across the last sessions. What genuinely remains:

- **A real input source + unbounded run**: the demo pre-queues 3 events and stops
  when quiescent (so the artifact terminates). A production daemon blocks on a
  real event source (stdin/socket/IPC) and loops until a shutdown signal,
  checkpointing periodically. That source is a runtime/syscall seam (below).
- **Cognitive wiring done.** All the deferred hooks I listed are now in
  `bin/crossengin`: output from reasoning via `gen_word_for_concept`, gate
  routing of percept/curiosity/goal signals into the substrate parts, and the
  full learning loop (`self_learning_triggers` -> `ask_user_to_teach`) growing
  the KGs at runtime so previously-unknown words are comprehended on the next
  encounter. The seed KG is still tiny, but the loop that GROWS it from input
  is wired and observed; in a long-running daemon it would just keep going.
  The remaining items below are I/O and performance, not cognition.
- This is the path to the ADR-0050 Step 10 v1 acceptance (multi-day companion
  test across real restarts, capability tests #6 long-horizon goals and #8
  NO-LLM-cognition) — which also needs the runtime seams below.

### 2. Land the runtime seams (NOVA enhancements)

Every deferred seam is a documented DI boundary with real logic behind it, not a
stub. To make the daemon production-real: #9/#10 fsync-durable decision log +
snapshot write (temp->fsync->atomic-rename); #11 the internet-fetch TLS
transport; #14 the STT/TTS modality bridge (isolated, no cognition path); #5 a
sub-second clock for the true 100Hz pacer; #4 SIMD/GPU batched propagation for
scale. These are tracked per-module in headers and in `nova-deps.toml`.

## Build/test commands verified working

`$HOME` in this environment is `/root`, but NOVA is at `/home/user/NOVA`, so
pass `NOVA_ROOT` explicitly (or set it in your shell):

```sh
# from the CrossEngin repo root, with NOVA built at /home/user/NOVA
make build      NOVA_ROOT=/home/user/NOVA   # compiles all 88 modules -> OK
make test       NOVA_ROOT=/home/user/NOVA   # 88/88 unit suites PASS
make benchmark  NOVA_ROOT=/home/user/NOVA   # prints tick-rate + throughput metrics
make install    NOVA_ROOT=/home/user/NOVA   # builds bin/{crossengin-selfcheck,crossengin-spine,crossengin}
bash scripts/run.sh                          # (honors $NOVA_ROOT env) prints "substrate self-check: OK"
$NOVA_ROOT/nova run examples/companion_spine.nova   # prints "companion spine: OK"
$NOVA_ROOT/nova run examples/crossengin_daemon.nova # the whole agent; prints "crossengin: OK"
```

To build the NOVA toolchain itself (one time): `cd /home/user/NOVA && make`
(produces `bin/nova` and the `nova` launcher; needs GNU `as`, `ld`).
