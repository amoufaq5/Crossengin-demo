# NOVA Runtime Gaps — Canonical List

## Preface

CrossEngin is built on NOVA. Under our standing rule we never edit
`/home/user/NOVA/src/runtime/*`; every workaround for a missing NOVA
capability is a CrossEngin-side source file. This document is the
single canonical inventory of runtime capabilities CrossEngin needs
from NOVA that either do not exist today, are broken in the current
runtime, or are performant enough only in narrow cases. It replaces
the scattered call-outs in individual ADRs
(`docs/adr/0005-nova-language-and-enhancements.md` §21,
`docs/adr/r86-in-process-tls-scaffolding.md` §"Missing NOVA runtime
capabilities", the `NEXT_SESSION.md` "Deferred (upstream / off-limits)"
list, and the header comments in `src/util/str_safe.nova`,
`src/safety/field25519.nova`, `src/net/tls/der.nova`, and
`src/learning/secure_aggregation.nova`).

**Audience: NOVA maintainers.** Each gap below is written to be
actionable in the NOVA repo. Impact and priority are stated from the
CrossEngin side; priority is HIGH when a vision milestone
(ADR-0200..0211) is blocked and MEDIUM when a workaround exists but
carries a real cost (implementation surface, performance, security).
LOW is cosmetic.

There are two orthogonal lists that must not be conflated:

- The **fourteen enhancements program** from ADR-0005 (`#1..#14`) —
  strategic substrate additions that were planned before v1 and are
  tracked in `nova-deps.toml` with status `available` / `partial` /
  `required`. Those enhancements gate architectural milestones like
  1M-node arenas, batched propagation, and multi-KG namespacing.
- The **operational quirks list** — bugs and missing primitives
  CrossEngin has discovered while building on the current toolchain.
  These have per-file workarounds today.

This document folds both lists into one canonical view because from
a NOVA-maintainer perspective they are the same queue.

## Gap categories

The gap counts below match the per-gap entries in the next section:

| Category | Gaps |
|---|---|
| Randomness & time | 3 |
| Filesystem | 3 |
| Bytes vs strings | 4 |
| Arithmetic | 4 |
| Compute primitives | 4 |
| Networking | 3 |
| Process / subprocess | 2 |
| Diagnostic (crash/flakiness) | 3 |
| Language / stdlib | 3 |
| Vision-introduced gaps | 5 |
| **Total** | **34** |

## Per-gap entries

### Randomness & time

#### R-1. No usable CSPRNG in seccomp-restricted containers

- **Symptom.** NOVA's `secure_random` builtin wraps the Linux
  `getrandom` syscall; the container CrossEngin's CI runs in has a
  seccomp policy that blocks `getrandom`, so `secure_random` returns
  `-1`. There is no in-runtime fallback (no `/dev/urandom` file
  read via `sys_open`, no user-space DRBG seeded elsewhere).
- **Current workaround.** `src/safety/rng.nova` ships a three-backend
  pluggable RNG: (A) OS `secure_random`, (B) a TEST-ONLY
  deterministic ChaCha20-CTR (never for production), and (C) a
  caller-supplied callback that a launcher/sidecar can wire to a
  named-pipe drip. In the CrossEngin daemon the environment variable
  `CROSSENGIN_RNG_MODE=callback` selects (C) with the FIFO named by
  `CROSSENGIN_RNG_FIFO` (see R94 wire-hook code and
  `docs/SHIP_AS_APP.md` §7.44). `src/learning/secure_aggregation.nova`
  historically fell back to `nanotime()` + a 15-bit LCG for its DH
  private keys; that path is documented in the file's "WEAK RANDOM
  CAVEAT" block as broken against any adversary who can guess boot
  time to within a second.
- **Impact.** Without a CSPRNG the TLS 1.3 stack (`src/net/tls/*`)
  and every downstream signed-bundle path (ADR-0204 bake, R54.2
  signed skills) cannot generate ephemeral secrets safely on default
  container deployments. Federated learning private keys
  (`src/learning/secure_aggregation.nova`) are trivially breakable
  today.
- **Priority.** HIGH. Every production deployment mode
  (mother-daemon, per-user selective load, baked child, embedded)
  needs entropy without an external sidecar.
- **Referenced by.** R86 ADR §"Missing NOVA runtime capabilities"
  row 1, R91 caveat, `docs/SHIP_AS_APP.md` §12, ADR-0005 (implicit
  under the security-and-persistence cluster).

#### R-2. `nanotime()` segfaults / returns 0

- **Symptom.** Historically `nanotime()` on this NOVA toolchain has
  returned 0 for the whole process (R90/R91 findings) and in some
  interactions caused a segfault. Even when it returns a value, it
  is a coarse wall-clock reading and is not usable as a monotonic
  timing source (an operator changing system time makes deltas
  meaningless).
- **Current workaround.** Callers add cross-checks and only use
  `nanotime()` where "possibly zero" is acceptable —
  `src/io/transducers/kg_sync.nova:1376` uses it as an atom birth
  timestamp where zero is a benign sentinel;
  `src/learning/federated_aggregator.nova:883` documents that the
  coordinator does not add `nanotime()` to a deadline (NOVA bug #5)
  and instead uses subtraction against a freshly-read `nanotime()`
  each poll.
- **Impact.** Blocks any real latency measurement — ADR-0208's
  performance harness cannot express per-verb budgets without a
  monotonic nanosecond clock. Also blocks jitter-bounded scheduling
  (ADR-0037's 100Hz tick discipline, NOVA enhancement #5).
- **Priority.** HIGH. Latency parity with LLMs (ADR-0208) is a
  vision-level commitment and it is not measurable without this.
- **Referenced by.** `NEXT_SESSION.md` "R44 -- chat REPL" §1 and
  the R91 caveat block in R86 ADR, plus the header comments in
  `src/learning/secure_aggregation.nova`.

#### R-3. No monotonic clock primitive

- **Symptom.** Even if `nanotime()` were reliable it is wall-clock
  only. There is no `sys_clock_gettime(CLOCK_MONOTONIC)` seam.
- **Current workaround.** None; wall-clock is used everywhere a
  monotonic source would be preferred, and the code base tolerates
  the jitter.
- **Impact.** Timeout arithmetic (federated round deadlines, RPC
  request timeouts, ICE keepalives) is subtly wrong across clock
  slew. Also blocks the tick-driver drift compensation (ADR-0037).
- **Priority.** MEDIUM (workable today but permanently fragile).
- **Referenced by.** `src/learning/federated_aggregator.nova:883`
  and the R37 scheduler ADR.

### Filesystem

#### F-1. `sys_open` on `/tmp` aborts in-container

- **Symptom.** Under the CI container's seccomp policy, `sys_open`
  against a `/tmp` path aborts the process rather than returning an
  error code.
- **Current workaround.** CrossEngin never writes to `/tmp` from
  NOVA; snapshot output uses caller-configured paths only, and the
  ingest layer never buffers to `/tmp`. Test fixtures live in
  `tests/data/`.
- **Impact.** Anything the runtime does today that assumed `/tmp`
  (temp file for AtomicWrite, etc.) is silently unreachable in
  container mode.
- **Priority.** MEDIUM. Workable, but blocks any future runtime work
  that assumes a writable scratch directory (fsync-safe write-then-
  rename for ADR-0048 persistence, NOVA enhancement #10).
- **Referenced by.** Session Explore reports (see `NEXT_SESSION.md`
  discussion of "container sandbox limitations").

#### F-2. `sys_readdir` does not exist

- **Symptom.** NOVA has `sys_open` and file read/write but no
  directory-listing primitive.
- **Current workaround.** CrossEngin uses hard-coded file paths
  everywhere the runtime cares about names. The bake step
  (ADR-0204) will need this — child bundles include an allowlisted
  set of capsule and skill files and the operator will want to point
  at a directory, not enumerate the paths by hand.
- **Impact.** ADR-0204 bake, ADR-0203 update channel, and any
  filesystem-backed KG scan all need to iterate directory contents.
- **Priority.** HIGH once ADR-0204 lands; MEDIUM today.
- **Referenced by.** ADR-0200 R120+ epic, ADR-0204 sketch.

#### F-3. No fsync durability primitive verified

- **Symptom.** `runtime/io.nova` has buffered file writes but no
  `sys_fsync` verified in the current toolchain; ADR-0005 lists
  crash-safe append-only durability (enhancement #9) as `partial`.
- **Current workaround.** `src/audit/audit_writer.nova` and
  `src/persistence/snapshot_writer.nova` write and close but do not
  fsync; ADR-0048 acknowledges this as a known persistence
  limitation.
- **Impact.** Any crash mid-write can lose the audit tail
  (ADR-0043 decision-log invariant is violated) or corrupt a
  snapshot (ADR-0048 ordered rehydration relies on a fully-written
  file).
- **Priority.** HIGH before any regulated deployment.
- **Referenced by.** `nova-deps.toml` enhancement #9,
  ADR-0043, ADR-0048.

### Bytes vs strings

#### B-1. NOVA strings are C-style NUL-terminated

- **Symptom.** A string containing a `0x00` byte is silently
  truncated at the NUL when passed through most string builtins.
  Every byte-handling path in CrossEngin must use a `[buf, len]`
  pair (a byte list plus an integer count) to survive NUL bytes.
- **Current workaround.** The `(buf, buf_len, off, out_params)`
  convention is threaded through `src/net/tls/der.nova`,
  `src/net/tls/x509.nova`, `src/net/tls/tls_cert.nova`,
  `src/safety/chacha20_poly1305.nova`,
  `src/safety/hkdf_sha256.nova`, and every consumer of these. Every
  crypto and wire-parse callsite is `_buf` suffixed.
- **Impact.** Every new bytes-shaped API needs the same convention.
  This nearly doubles the surface area of every crypto module (a
  string API plus a byte-list API) and forbids using `char_at` /
  `substr` for anything that might contain a NUL.
- **Priority.** MEDIUM. Well-known and worked around, but a
  first-class byte type (or a NUL-safe string) would eliminate a
  large class of latent bugs.
- **Referenced by.** `src/net/tls/der.nova:60` "NOVA quirks" block,
  `src/net/tls/x509.nova:62`, `src/net/tls/tls_cert.nova:74`.

#### B-2. `str_eq` unreliable on short literals

- **Symptom.** `str_eq("op", "op")` empirically returns 0. Confirmed
  on "op", "num", "CONST", "INVALID" and other short literal pairs
  under the current runtime. See `src/util/str_safe.nova` docstring
  for the failure discovery.
- **Current workaround.** `str_eq_bytes(a, b)` in
  `src/util/str_safe.nova` does a length check plus a `char_at`
  byte loop. R44 migrated 185 slash-command sites in the chat REPL,
  23 sites in `test_session.nova`, and the entire `session.nova`
  lookup path.
- **Impact.** ~1465 `str_eq` call sites still exist across `src/`.
  The migration is incremental; every module touched by any round
  since R44 has been co-migrated. A working `str_eq` would let the
  migration stop and would fix any not-yet-migrated site silently.
- **Priority.** HIGH — the failure mode is silent (returns 0 for
  equal strings, so callers see "not found" instead of an error).
- **Referenced by.** `src/util/str_safe.nova:1..27`,
  `NEXT_SESSION.md` "R44 -- chat REPL" §1.

#### B-3. `split` builtin broken on multi-char strings and single-char delims

- **Symptom.** `split("abcdefghij klmnopqrst", " ")` returns
  `["abcde", "fghij"]` (half of each word), and
  `split("a b c d", " ")` returns four empty strings.
- **Current workaround.** `split_char(s, delim_char)` and
  `split_space(s)` in `src/util/str_safe.nova` walk bytes via
  `char_at`/`substr`.
- **Impact.** Every module that would like to use `split` must use
  the workaround. Adds surface area for every text-parse path.
- **Priority.** MEDIUM.
- **Referenced by.** `src/util/str_safe.nova:29..54`.

#### B-4. `str_find` gives wrong offsets in two shapes

- **Symptom.** (1) Single-character needle returns
  `FLOOR(position / 2)` instead of the actual position (e.g.
  `str_find("en.wikipedia.org/x", "/")` returns 8 instead of 16).
  (2) Multi-character needle at position 0 returns a "phantom zero"
  that compares as < 0 under `if idx < 0 { not_found }`. Discovered
  while migrating `pem_truststore` (2026-08).
- **Current workaround.** `find_char(hay, needle_char)` and
  `find_bytes(hay, needle)` in `src/util/str_safe.nova`.
- **Impact.** Every URL parse, PEM-banner search, and JSON key scan
  must use the workarounds. Any code still relying on
  `str_find(...) != -1` for "does it contain X" is safe; every
  position-consumer is not.
- **Priority.** HIGH — silently truncates URLs and PEM decoders.
- **Referenced by.** `src/util/str_safe.nova:57..99`.

### Arithmetic

#### A-1. Codegen bug #11: large-multiply smart-dispatch SIGSEGV

- **Symptom.** Multiplication or addition producing a value above a
  ~2^20 threshold selects the runtime's string/list dispatch path
  and segfaults. `a * b` where either operand or the accumulating
  sum exceeds ~0x100000 crashes; the same values under
  `int_mul(a, b)` and `int_add(a, b)` (the "int_* escape hatch")
  work correctly.
- **Current workaround.** The codebase-wide `int_*` escape hatch
  convention. Documented and used by `src/io/transducers/stream_http.nova:124`,
  `src/io/transducers/http_client.nova:434`,
  `src/learning/secure_aggregation.nova:394`,
  `src/learning/byzantine_aggregation.nova:181`,
  `src/learning/forward_forward.nova:45`,
  `src/kg/semantic_search.nova:137`,
  `src/kg/graph_clustering.nova:137`,
  `src/kg/ann_index.nova:47..90`,
  `src/kg/louvain.nova:143`,
  `src/federation/gossip.nova:562`,
  `src/federation/turn.nova:740`,
  `src/safety/differential_privacy.nova:22..170`.
- **Impact.** Every arithmetic path involving values > ~2^20 must
  either use `int_*` or precompute constants small enough to stay
  under the threshold. Any new code touching hashing, coordinate
  arithmetic, or serialization is a landmine.
- **Priority.** HIGH — the failure mode is a hard segfault.
- **Referenced by.** ADR-0063 (stream_http IP overflow fix),
  ADR-0069 (turn `!=` bug).

#### A-2. Constants near 2^62 misbehave in comparisons

- **Symptom.** Integers within a few orders of magnitude of 2^62
  (the observed ceiling of NOVA's 63-bit-positive integer range)
  do not compare reliably. Cross-referenced by the safe-multiply
  bounds analysis in `src/safety/field25519.nova:35..40`: the
  Bernstein 10-limb layout was chosen specifically to keep every
  `fe_mul` intermediate under 2^62 so NOVA's arithmetic stays sound.
- **Current workaround.** Every big-integer path (Curve25519 field,
  Ed25519 scalar, HKDF counters, bignum limbs) picks a limb size
  such that products fit safely under 2^62. `src/safety/bignum.nova`
  and `src/safety/bignum_2048.nova` use 32-bit limbs; `field25519`
  uses 26/25-bit limbs.
- **Impact.** No 63-bit unsigned math is possible; every wide
  arithmetic must be hand-decomposed into narrow limbs.
- **Priority.** MEDIUM. Well-known, but native 64-bit unsigned math
  would eliminate a large fraction of `src/safety/*` code.
- **Referenced by.** `src/safety/field25519.nova:35..48`,
  `docs/SHIP_AS_APP.md` §"63-bit-positive arithmetic safety"
  (bignum discussion).

#### A-3. No native bignum

- **Symptom.** No arbitrary-precision integer or GF(p) arithmetic
  in the runtime. Curve25519, Ed25519, HKDF counters, and the RSA /
  ECDSA / P-256 fallbacks are all implemented as NOVA-source limb
  arithmetic.
- **Current workaround.** `src/safety/bignum.nova`,
  `src/safety/bignum_256.nova`, `src/safety/bignum_2048.nova`,
  `src/safety/field25519.nova`, `src/safety/p256.nova`,
  `src/safety/rsa.nova`.
- **Impact.** Every crypto primitive costs many hundreds of NOVA
  lines. A native bignum (or `wide_mul` / `add_with_carry` /
  `sub_with_borrow` primitives) would collapse all of this to thin
  wrappers.
- **Priority.** MEDIUM — the code exists and passes RFC vectors,
  but performance is 10-100x slower than a native implementation
  would be, and every new curve (P-384, secp256k1, BLS12-381) is a
  full re-implementation.
- **Referenced by.** All of `src/safety/*` cryptographic modules.

#### A-4. `str_to_int` returns 0 for garbage input

- **Symptom.** `str_to_int("abc")` returns 0, indistinguishable from
  `str_to_int("0")`. There is no error return.
- **Current workaround.** Callers guard with an `_hc_all_digits`
  predicate before invoking `str_to_int`
  (`src/io/transducers/http_client.nova:422`), or use byte
  arithmetic instead (see `src/net/tls/der.nova:60..67` note that
  "DER length parsing uses byte arithmetic, never `str_to_int`").
- **Impact.** Silent data corruption unless every callsite guards.
- **Priority.** MEDIUM.
- **Referenced by.** `src/net/tls/der.nova:60..67`,
  `src/io/transducers/http_client.nova:422`.

### Compute primitives

#### C-1. No SIMD / CLMUL exposed

- **Symptom.** `runtime/simd.nova` exists but batched-propagation
  and constant-time-multiply-friendly kernels are not exposed.
  ADR-0005 marks enhancement #4 (SIMD/GPU batched signal
  propagation) as `partial`.
- **Current workaround.** Scalar loops everywhere. This is why R86
  chose ChaCha20 over AES-GCM: AES-GCM's GHASH mode needs CLMUL for
  performance, and a scalar CLMUL-emulation is too slow; ChaCha20's
  ARX design is cache-timing friendly at scalar speeds. See R86 ADR
  §"Cipher choice".
- **Impact.** Blocks:
  - substrate-scale batched signal propagation (ADR-0003, NOVA
    enhancement #4)
  - Hebbian / error-driven plasticity kernels (ADR-0031, NOVA
    enhancement #12)
  - HDC embedding kernel throughput (`src/kg/hdc_embed.nova`)
  - AES-GCM (if ever needed to interoperate with a peer that
    negotiates it)
  - matrix-mul kernels for the sandbox learners (ADR-0202)
- **Priority.** HIGH for the substrate-scale milestone and
  latency-parity (ADR-0208).
- **Referenced by.** `nova-deps.toml` enhancement #4,
  ADR-0003, ADR-0031, R86 ADR "Cipher choice".

#### C-2. No native BLAS / matrix multiplication

- **Symptom.** `runtime/blas.nova` and `runtime/tensor.nova` exist
  as modules but do not expose a native `sgemm`-shaped
  matrix-matrix kernel. Every dense-linear-algebra path in
  `src/kg/*` and `src/learning/*` uses hand-rolled scalar loops.
- **Current workaround.** Scalar loops in `src/kg/hdc_embed.nova`,
  `src/kg/semantic_search.nova`, and the HDC-adjacent learners.
- **Impact.** ADR-0202 cognitive sandbox needs fast matmul for the
  HDC-based reasoning kernels; ADR-0205 multimodal ingest
  (convolutions for image features, MFCC filterbank multiplies for
  audio) is throughput-bound on this today.
- **Priority.** HIGH for Phase G (multimodal, ADR-0205), MEDIUM
  until then.
- **Referenced by.** `nova-deps.toml` enhancement #4,
  ADR-0202, ADR-0205.

#### C-3. No GPU offload seam

- **Symptom.** `runtime/gpu.nova` is listed in `nova-deps.toml`
  but has no callable kernel offload API in the current toolchain.
- **Current workaround.** Everything runs on the CPU.
- **Impact.** Ceiling on the 1M-node substrate scale target
  (ADR-0003). Ceiling on any future in-process ML kernel
  (rejected near-term per ADR-0201, but a candidate for the
  post-Phase-J roadmap).
- **Priority.** MEDIUM long-term, LOW near-term (the vision
  explicitly deprioritizes in-process LLM inference per ADR-0201).
- **Referenced by.** `nova-deps.toml` enhancement #4.

#### C-4. No pre-allocated fixed-capacity node arenas at scale

- **Symptom.** `runtime/alloc.nova` has an arena API but 1M-node
  pools per part have not been proven at scale; ADR-0005
  enhancement #1 is `partial`.
- **Current workaround.** `src/substrate/part_registry.nova` and
  `src/substrate/synapse_graph.nova` use small in-memory pools
  suitable for the current demo scale.
- **Impact.** Blocks the ADR-0003 scale target (1M nodes per part,
  1B nodes across parts) and the ADR-0007 sparse-synapse CSR
  layout (enhancement #2).
- **Priority.** MEDIUM until a customer needs the scale;
  HIGH for the ADR-0003 milestone.
- **Referenced by.** `nova-deps.toml` enhancements #1 and #2,
  ADR-0003, ADR-0006, ADR-0007.

### Networking

#### N-1. HTTP client is basic

- **Symptom.** `src/io/transducers/http_client.nova` is a
  hand-rolled HTTP/1.1 client. No HTTP/2, no streaming (whole body
  read into memory), no connection reuse across requests, no
  content-encoding decoders.
- **Current workaround.** The client works for the ADR-0028
  internet-fetch and ADR-0053 multi-source research paths at the
  current scale.
- **Impact.** Ceiling on ingest throughput for the ADR-0202
  multimodal epic (fetching image or audio corpora) and on any
  future Wikidata or ConceptNet stream (see the R44 hash-index
  discussion in `NEXT_SESSION.md` — the "million-atom Wikidata
  subset" is scan-bound today but will become fetch-bound once the
  substrate scale lands).
- **Priority.** MEDIUM.
- **Referenced by.** `nova-deps.toml` enhancement #11.

#### N-2. No non-blocking accept / poll loop

- **Symptom.** The daemon's accept loop is serial: one connection
  at a time. TLS handshakes serialize behind it.
- **Current workaround.** R94 accepted this as a single-user
  ceiling (see R86 ADR row 6).
- **Impact.** Any multi-user deployment (Phase E per-user
  selective-load, or a mother handling many child bake-and-deploy
  operators) is throughput-limited.
- **Priority.** HIGH for Phase E, MEDIUM until then.
- **Referenced by.** R86 ADR post-scriptum "what a hardened
  deployment still wants", `nova-deps.toml` enhancement #3.

#### N-3. Socket API surface is thin

- **Symptom.** No UDP-optimized batching, no SO_REUSEPORT, no
  IPv6-mapped-IPv4 handling verified in-container. TURN/STUN paths
  (`src/federation/turn.nova`, `src/federation/stun_rfc8489.nova`)
  had to work around several of these.
- **Current workaround.** In-file coping code, plus the ADR-0069
  turn-flaky-segfault fix.
- **Impact.** WebRTC / federation performance ceiling.
- **Priority.** LOW today (federation is not on the near-term
  vision path); MEDIUM if the collaborative-federation milestone
  moves forward.
- **Referenced by.** `src/federation/turn.nova`, ADR-0069,
  ADR-0073.

### Process / subprocess

#### P-1. No spawn+pipe primitive; sidecars shell out

- **Symptom.** NOVA has no `sys_fork` + `sys_execve` + `sys_pipe`
  triple exposed as a first-class primitive. Sidecars (whisper,
  vosk, ImageMagick, ffmpeg, the ADR-0201 LLM parser) are invoked
  through a `run_shell`-style seam that fork/exec's the shell and
  captures stdout as a string.
- **Current workaround.** `scripts/nl_parse_llm.sh`,
  `scripts/llm_extract.sh`, `src/io/transducers/whisper_backend.nova`
  "subprocess shim" path, `src/io/transducers/vosk_backend.nova`
  same. Every sidecar call pays a full shell-launch cost per query.
- **Impact.** ADR-0201 acknowledges "per-query subprocess cost
  (tens of milliseconds on typical hardware, before the model
  runs)" as the primary Negative. This is the single largest
  contributor to the sidecar-LLM latency budget under Phase B and
  will remain so until either (a) a persistent-session sidecar
  lands (ADR-0201 "alternative 3") or (b) NOVA gains a fork/exec
  primitive that lets CrossEngin pool sidecar workers.
- **Priority.** HIGH for Phase B (latency parity with LLMs,
  ADR-0208).
- **Referenced by.** ADR-0201 "Negative" §, ADR-0208 anticipated.

#### P-2. No signal-handler / graceful-shutdown primitive

- **Symptom.** NOVA has no `sys_sigaction` seam. The daemon can only
  poll a flag; it cannot register a handler for `SIGTERM` /
  `SIGINT` / `SIGHUP` and complete an in-flight fsync before exit.
- **Current workaround.** The daemon exits on the next accept-loop
  iteration when it observes the flag; in-flight requests may be
  dropped mid-write.
- **Impact.** Corrupts the audit tail and snapshots on any orderly
  restart (see F-3 above).
- **Priority.** MEDIUM.
- **Referenced by.** ADR-0043, ADR-0048 implicit.

### Diagnostic (crash / flakiness)

#### D-1. `io_println` / `io_input` from `std/io` segfault

- **Symptom.** The `io_println` and `io_input` functions from
  `std/io` segfault on invocation under the current NOVA runtime.
- **Current workaround.** Use the builtin `println` / `read_line`
  instead. R44 migrated 626+4 sites in `crossengin_chat.nova`.
- **Impact.** Every REPL-shaped or human-output path must remember
  to route through the builtin rather than the stdlib.
- **Priority.** MEDIUM — worked-around but silent.
- **Referenced by.** `NEXT_SESSION.md` "R44 -- chat REPL" §1.

#### D-2. `len(0)` segfaults

- **Symptom.** Calling `len` on a raw `0` (integer) segfaults
  rather than returning 0 or raising an error. This means the
  common pattern "return 0 to signal 'no result'" is dangerous
  whenever any caller might reach for `len` on the result.
- **Current workaround.** Use `""` (empty string) as the OK / no-
  result signal wherever a downstream `len` is possible. Every
  crypto callsite is written with this in mind
  (`src/net/tls/der.nova:60..67` note "caller must never pass a raw
  0 as buf").
- **Impact.** Every new byte-shaped API must decide its
  no-result convention up front. Any accidental `0` return
  crashes the whole daemon.
- **Priority.** HIGH — hard segfault, easy to introduce.
- **Referenced by.** `src/net/tls/der.nova:60`, R44 chat-fix
  discussion.

#### D-3. Symbol-collision quirk across modules

- **Symptom.** Same-named identifiers across modules can collide
  in ways that are silently miscompiled rather than diagnosed.
  Documented by R86: every symbol under `src/net/tls/` uses a
  `tls_` / `tls_alert_` / `tls_state_` prefix specifically to
  avoid the collisions the NOVA runtime has historically had.
- **Current workaround.** Manual per-module prefixing convention.
- **Impact.** Every new module owner must pick and enforce a
  prefix; refactoring across modules is risky.
- **Priority.** MEDIUM.
- **Referenced by.** R86 ADR §"Module layout" note on prefixing.

### Language / stdlib

#### L-1. No pattern matching / algebraic sum types

- **Symptom.** NOVA has records and lists but no tagged-union /
  sum-type pattern-match. Every error-shape and every state-machine
  dispatch is expressed as `let ok = 1` / `if ok == 0` scattered
  through the code (see `src/net/tls/tls_state.nova`, the state
  machine transitions).
- **Current workaround.** By hand, per-file conventions.
- **Impact.** Reasoning about state-machine correctness is harder
  than it needs to be; ADR-0086 formal-verification path would be
  easier against a typed sum.
- **Priority.** LOW.
- **Referenced by.** `src/net/tls/tls_state.nova`, ADR-0086 §
  formal-verification-path.

#### L-2. No first-class error propagation

- **Symptom.** No `?`-style propagation; every function returns an
  `ok` flag through an out-parameter or a sentinel value. The
  `DER_OK` / `DER_ERR` sentinels in `src/net/tls/der.nova` are
  typical.
- **Current workaround.** Sentinel discipline.
- **Impact.** Callsite noise; easy to forget an ok-check.
- **Priority.** LOW.
- **Referenced by.** `src/net/tls/der.nova`, all crypto modules.

#### L-3. No module-hygiene / visibility control

- **Symptom.** All top-level symbols in a NOVA source file are
  effectively public. Modules cannot mark private helpers.
- **Current workaround.** `_leading_underscore` naming convention.
- **Impact.** Every module's public surface is larger than
  intended; refactoring breaks callers who reached into "private"
  helpers.
- **Priority.** LOW.
- **Referenced by.** Every source file.

## New gaps introduced by the vision

The Phase A..J plan surfaces gaps that today's code does not yet hit
but that the vision milestones will require.

### V-1. Latency parity (ADR-0208 / Phase H)

- SIMD + BLAS for HDC embedding and semantic-search matmul
  (C-1, C-2 above become HIGH once Phase H starts).
- Cache-aware KG index — the hash-indexed `mkgc_scan_conflicts`
  from R44 is a start, but ADR-0208's per-verb budgets will
  demand a cache-friendlier atom-store layout.
- Tuned scheduler — the ADR-0037 100Hz tick fused with event
  dispatch (NOVA enhancement #5) must actually be deterministic
  under load, which needs the monotonic clock (R-3) and the
  concurrent execution units (NOVA enhancement #3).
- Persistent sidecar sessions for the ADR-0201 fallback (P-1
  above), or per-worker warm-pool primitives from the runtime.

### V-2. Multimodal ingest (ADR-0202 / ADR-0205 / Phase G)

- Faster convolutions and dense matmul for the ImageMagick and
  ffmpeg replacement path (`src/io/transducers/png_decode.nova`
  and `visual_perception.nova` explicitly cite the intent to drop
  the subprocess shim).
- BLAS-tier matrix multiply for MFCC / spectrogram filterbanks.
- Fast image decoders (native PNG/JPEG decode) — the current
  `png_decode.nova` and `src/io/transducers/jpeg_decode.nova`
  are pure NOVA and slow for realistic corpus sizes.
- All of the above compound with C-1..C-3.

### V-3. Mobile deployment (ADR-0209 mode 4)

- Cross-compilation targets for iOS ARM64 and Android ARM64. The
  current NOVA toolchain (per `nova-deps.toml`) targets
  `x86-64-linux` only.
- Smaller memory footprint — the ADR-0003 substrate scale target
  assumes a workstation; a mobile child needs an order-of-magnitude
  smaller resident-set-size ceiling.

### V-4. Embedded (ADR-0210 mode 5)

- Cross-compilation to constrained targets (ARM Cortex-M class or
  RISC-V microcontroller).
- Deterministic memory allocation — the arena API needs a
  no-heap-allocation mode for hard-realtime deployments.
- Static binary output — the runtime must be linkable without a
  runtime loader.

### V-5. In-process LLM adapter (rejected near-term per ADR-0201)

- If ever revisited, needs either an FFI seam (C ABI call-out to
  llama.cpp) or the GPU offload from C-3.
- ADR-0201 explicitly documents why this is rejected today; the
  gap is listed here so that if the vision changes it is not
  re-discovered from scratch.

## Prioritized action list for NOVA maintainers

Ranked by unblock value across the current milestones and the
vision phases:

1. **R-1: usable CSPRNG in-container** — every production TLS,
   bake-signature, and federation path depends on this. Today the
   container path requires an external sidecar drip. HIGH.
2. **B-2: `str_eq` reliability on short literals** — 1465 latent
   call sites, silent failure mode, ongoing whole-codebase
   migration cost. HIGH.
3. **B-4: `str_find` correctness for single-char and at-offset-0
   needles** — silent URL-truncation and PEM-decode failures.
   HIGH.
4. **A-1: codegen bug #11 (large-multiply SIGSEGV)** — hard
   segfault, ~15 files affected, `int_*` escape hatch works but
   every new module owner must remember it. HIGH.
5. **D-2: `len(0)` segfault** — hard crash on a common
   no-result convention; documented and worked around, but a
   permanent bug-magnet. HIGH.
6. **R-2/R-3: monotonic nanotime** — blocks ADR-0208 latency
   parity measurement entirely. HIGH.
7. **P-1: spawn+pipe primitive for sidecar workers** — largest
   single contributor to Phase B (ADR-0201) tail latency.
   HIGH once Phase B starts.
8. **C-1/C-2: SIMD + BLAS exposed as callable kernels** — gates
   substrate-scale (ADR-0003), plasticity kernels (ADR-0031),
   HDC matmul, and multimodal (ADR-0202/0205). HIGH once Phase G
   or Phase H starts.
9. **F-3: verified fsync durability** — required before any
   regulated deployment; audit-log (ADR-0043) and snapshot
   (ADR-0048) both rely on it. HIGH.
10. **F-2: `sys_readdir`** — required for ADR-0204 bake and
    ADR-0203 update-channel filesystem walks. HIGH once Phase D
    starts.

Below the top 10, in rough order: N-2 non-blocking accept (Phase E),
A-3 native bignum (crypto surface reduction), A-2 near-2^62 arithmetic
(bignum simplification), C-4 arena scale (ADR-0003), B-1 NUL-safe
strings (large latent surface), B-3 `split` correctness, D-1
`io_println` fix, C-3 GPU offload, D-3 symbol-collision hygiene,
N-1 HTTP client, N-3 socket API, P-2 signal handlers, L-1..L-3
language ergonomics, A-4 `str_to_int` error return, F-1 `/tmp` open.

## Referenced files

Cross-reference of which CrossEngin file consumes which workaround,
so that when a NOVA runtime fix lands the corresponding CrossEngin
callsites can be simplified.

| CrossEngin file | Cope for gap |
|---|---|
| `src/util/str_safe.nova` | B-2 (str_eq), B-3 (split), B-4 (str_find) |
| `src/util/list_safe.nova` | list-shape helpers around D-2 (len(0)) |
| `src/safety/rng.nova` | R-1 (CSPRNG, three-backend switch) |
| `src/safety/field25519.nova` | A-2 (near-2^62), A-3 (bignum) — 26/25-bit limbs |
| `src/safety/bignum.nova`, `bignum_256.nova`, `bignum_2048.nova` | A-3 (bignum) |
| `src/safety/x25519.nova`, `ed25519.nova`, `p256.nova`, `rsa.nova`, `ecdsa.nova` | A-3 (bignum) — full hand-rolled curves |
| `src/safety/chacha20.nova`, `poly1305.nova`, `chacha20_poly1305.nova` | C-1 (no SIMD) — chose ARX to stay scalar-friendly |
| `src/safety/hkdf_sha256.nova`, `sha256.nova`, `sha1.nova`, `md5.nova` | A-1 (int_*), B-1 (buf,len) |
| `src/net/tls/der.nova` | B-1 (buf,len), A-4 (str_to_int), D-2 (len(0)) |
| `src/net/tls/x509.nova` | B-1, D-2 |
| `src/net/tls/tls_cert.nova`, `tls_session.nova`, `tls_transcript.nova`, `tls_keyshare.nova` | B-1, D-3 (tls_ prefix) |
| `src/net/tls/tls_wire_hook.nova` | R-1 wiring for `CROSSENGIN_RNG_MODE=callback` |
| `src/io/transducers/stream_http.nova`, `http_client.nova` | A-1 (int_*), A-4 (str_to_int guard) |
| `src/io/transducers/png_decode.nova`, `jpeg_decode.nova`, `visual_perception.nova`, `video_perception.nova` | C-2 (matmul), V-2 (multimodal) |
| `src/io/transducers/whisper_backend.nova`, `vosk_backend.nova` | P-1 (sidecar spawn cost) |
| `src/io/transducers/kg_sync.nova` | R-2 (nanotime — atom birth timestamp) |
| `src/learning/secure_aggregation.nova` | R-1 (CSPRNG, WEAK RANDOM CAVEAT), A-3 (bignum) |
| `src/learning/federated_aggregator.nova` | R-2 (nanotime deadline arithmetic) |
| `src/learning/byzantine_aggregation.nova`, `forward_forward.nova` | A-1 (int_*) |
| `src/safety/differential_privacy.nova` | A-1 (int_*) |
| `src/kg/semantic_search.nova`, `graph_clustering.nova`, `ann_index.nova`, `louvain.nova`, `hdc_embed.nova` | A-1 (int_*), C-1/C-2 (SIMD + BLAS ceiling) |
| `src/federation/gossip.nova`, `turn.nova`, `stun_rfc8489.nova`, `webrtc.nova` | A-1 (int_*), N-3 (socket API), D-3 (symbol prefix) |
| `src/nl/llm_parser.nova`, `rpc_verbs.nova`, `rpc_server.nova` | P-1 (sidecar via scripts/nl_parse_llm.sh) |
| `src/persistence/snapshot_writer.nova`, `chat_state.nova` | F-3 (no fsync) |
| `src/audit/audit_writer.nova`, `decision_log.nova` | F-3 (no fsync) |
| `src/substrate/part_registry.nova`, `synapse_graph.nova`, `first_nodes.nova`, `tick_driver.nova` | C-4 (arena scale ceiling), NOVA enhancement #1/#2 |
| `src/scheduler/tick_loop.nova`, `event_dispatch.nova` | R-3 (monotonic clock), NOVA enhancement #5 |
| `examples/crossengin_chat.nova` | B-2 (str_eq_bytes migration, 185+ sites), D-1 (io_println fix) |
| `tests/ce_test.nova` | B-2 (`_ce_str_eq_bytes`) |
| `nova-deps.toml` | Root inventory of NOVA enhancements #1..#14 |
| `docs/adr/r86-in-process-tls-scaffolding.md` | R-1, C-1, N-2 first documented here |
| `docs/adr/0005-nova-language-and-enhancements.md` | The strategic #1..#14 program |
| `NEXT_SESSION.md` | R-2, B-2, D-1 discovery narrative (R44) |

If a NOVA fix removes the workaround for any row above, the
corresponding file becomes a candidate for simplification in the
next round.
