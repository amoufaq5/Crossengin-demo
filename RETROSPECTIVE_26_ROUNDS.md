# 26-Round Retrospective -- CrossEngin + NOVA Parallel-Agent Sprint

This document distills the institutional knowledge accumulated across 26
rounds and roughly 156 parallel-agent dispatches that built CrossEngin (a
non-LLM cognitive substrate written in NOVA) and grew the NOVA self-hosting
toolchain underneath it. It is intentionally unified across both repos:
nearly every CrossEngin capability lands on a NOVA primitive shipped in the
same or an earlier round, and the federation + perception stories cannot be
understood without the parser / codegen / IDE story they ride on.

The retrospective has eight sections, mirroring the brief:

1. Round-by-round headlines (R1..R26).
2. Cross-agent coordination patterns that worked.
3. Cross-agent failure modes (and their mitigations).
4. Honest engineering disclosures.
5. Realization-of-perf chains (primitive → wired → inlined → realized).
6. NOVA language evolution arc.
7. Federation layer evolution.
8. What is still open after 26 rounds.

All commit SHAs in section 1 were verified against `git log` in both
repos at the time of writing (`/home/user/Crossengin-demo` and
`/home/user/NOVA`, branch `claude/festive-franklin-PP7mW`).

---

## 1. Round-by-round headlines

### R1 -- substrate kernel (phase 1)

* CrossEngin: `2bfccb8 substrate(phase1): node pool, 18-signal dispatch,
  synapse graph` + `64b0650 substrate(phase1): complete the kernel`.
  The fabric of uniform computational units. Established the
  ADR-driven layout: substrate → kg → reader → reasoning → memory →
  imagination → agent → safety → io → persistence (the 10 phases).
* Key insight: phase ordering is the actual product spec. Every later
  round can be checked against "which phase / module does it sit in",
  which is what made parallel-agent file-ownership work later on.

### R2 -- knowledge graph + memory + language (phases 2-4)

* CrossEngin: `5356629 kg(phase3): atom store + multi-KG manager`,
  `89af65b kg(phase3): schemas + competence tracker`,
  `b0c0ce1` reader phase, `b0ce961 reader(phase2): five-stage hybrid`,
  `269023a phase4: confidence + source authority`,
  `2b1e81b phase4: moments + episodic + Bayesian belief`.
* Key insight: atom store + multi-KG is the spine the federation layer
  later attaches to (R7C, R18E, R20E, R20F, R21B, R23C, R23E, R26E).
  No federation round had to retrofit the atom-id space.

### R3 -- reasoning + emotion + imagination + safety + IO (phases 5-9)

* CrossEngin: `cc970dd phase5: self-learning triggers`,
  `ab2a114 phase6(soul): identity, state, values, constitution`,
  `1678f08 phase6(emotion): OCC + OCEAN`,
  `5228942 phase6(reasoning+imagination): 4 imagination modes`,
  `69dbd07 phase8: safety + audit`,
  `640cfcd phase9: IO + effectors`,
  `4a2a674 phase10: persistence (ordered snapshot)`.
* Key insight: shipping all ten phases as separate commits made the
  later parallel agents trivially scope-able to "phase N, module M".
  R12 and beyond never had a "where does this belong" merge conflict.

### R4 -- v1.0 single binary + Montgomery REDC

* CrossEngin: `671074f v1.0: unified single-process daemon`,
  `40c3932 safety: Montgomery REDC for bn2048_modpow_ct (R4D — ~10x
  speedup)`.
* Key insight: the v1.0 daemon being one binary is what makes
  /flow_pp, /reverb, /denoise, /gossip, /snap_replicas, ..., /melody,
  ..., all dispatch from a single chat process. Every R12..R26 module
  added one line to `examples/crossengin_chat.nova`; no module ever
  needed its own main loop.

### R5 -- SIFT detection + bignum 256

* CrossEngin: `b0b2f8c io: SIFT keypoint DETECTION (P3.3 cont.)`,
  `90aa664 safety: pure-NOVA 256-bit bignum library (P3.9 — DH
  prereq)`.
* Key insight: this is where the "primitive → wired → inlined →
  realized" cadence first showed up: R5A primitive bignum, R6B
  speedup, R7B production migration. The pattern became the SIMD
  story (R11D → R12A → R13A → R14B → R15A / R17C → R18A → R18A.2)
  later.

### R6 -- ORB + bignum mont + kg_sync v3 + ARPAbet Klatt + episodic consolidation

* CrossEngin: `4b24224 io: ORB feature detector + Hamming matcher
  (R6D)`, `edf265b safety: Montgomery REDC for bn256_modpow_ct (R6B
  — ~14x speedup mirror of R5A)`,
  `0e2700d io: Noise XK handshake for mutual auth (R6C, kg_sync v3)`,
  `1b97f7a audio: expand Klatt formant inventory 33 -> 53 (R6E)`,
  `25c05d0 kg+memory+persistence: episodic-memory consolidation cycle
  (R6F)`.
* Key insight: R6 was the first multi-agent round (six concurrent
  dispatches in different src/ subtrees). All six landed without
  conflict — proof that file-ownership scoping by src/ subtree was a
  sound coordination primitive.

### R7 -- stereo block matching, VAD, DH-256 production, DH-2048 upgrade

* CrossEngin: `c769f45 io: stereo depth via block-matching SAD
  disparity (R7E)`, `8af9f90 audio: VAD on capture + clean STT seam
  (R7F)`, `37cb8e1 safety: migrate DH-256 to bn256_modpow_ct (R7B;
  realize R6B's ~14x in production)`,
  `aa32046 io: Noise XK strength upgrade to RFC 7919 Group 14 DH
  (R7C)`.
* Key insight: R7B was the first formal "realize a primitive's perf in
  production" round. The pattern of having a separate round whose only
  job is to wire an already-shipped primitive into a hot path
  (Rsomething.2) became the standard cadence.

### R8 -- whisper.cpp STT, stereo LR-check + sub-pixel, KG migration,
       episodic recall

* CrossEngin: `0874516 audio: whisper.cpp STT backend wired (R8B)`,
  `b2d8c8f io: stereo LR-check + sub-pixel parabolic refinement on
  R7E (R8D)`, `10705d1 kg+chat: episodic memory retrieval API +
  /recall (R8F)`, `8e71cbb persistence: KG atom schema-evolution /
  migration framework (R8E)`.
* Key insight: the LR-check round (R8D) confirmed the
  "compose-on-prior-round" pattern: R8D could touch a single image
  module and trust R7E's primitives. No agent had to re-implement
  block-matching to do sub-pixel refinement.

### R9 -- SGM stereo, adaptive VAD, Byzantine-resilient aggregation

* CrossEngin: `68e8ec5 io: stereo Semi-Global Matching (R9A)`,
  `5dfd35c audio: adaptive VAD noise-floor (R9B)`,
  `3be2b4a fl: Byzantine-resilient aggregation -- trimmed mean +
  coord-wise median (R9F)`.
* Key insight: R9F's trimmed-mean choice over Krum / Bulyan was
  documented as a deliberate one (simpler, cheaper, sufficient for
  the federation threat model the substrate currently posits).
  Honest-disclosure habit started forming here.

### R10 -- LK dense flow, whisper confidence + Vosk, TF-IDF, autocorrelation
       pitch

* CrossEngin: `577797c io: Lucas-Kanade dense optical flow (R10D)`,
  `efbf346 audio: whisper per-utterance confidence + Vosk offline
  (R10B)`, `bf7529b kg+chat: TF-IDF semantic search (R10C)`,
  `2432505 audio: autocorrelation F0 pitch estimation (R10F)`.
* Key insight: R10F's pure autocorrelation is what later (R22F.2)
  competes head-to-head with R11B's YIN under an actual harmonicity
  signal -- and frequently wins on broadband content. The
  "later-round-picks-from-earlier-round-portfolio" pattern.

### R11 -- pyramidal LK, YIN, k-means seg, label-propagation communities,
       i32x8 SIMD

* CrossEngin: `a33a0db io: pyramidal Lucas-Kanade optical flow (R11A)`,
  `14ae091 audio: YIN-class F0 estimator (R11B)`,
  `d028e78 io: spatial k-means image segmentation (R11E)`,
  `80f4741 kg+chat: label-propagation community detection (R11F)`.
* NOVA: `844d54b codegen: SIMD i32x8 intrinsics (AVX2 / NEON / scalar)
  for inner loops (R11D)`.
* Key insight: R11D shipped SIMD i32x8 codegen as a primitive with no
  user. The next round (R12A) had to actually wire it -- and produced
  a regression. The realization chain genuinely had to be paid in
  multiple agents over multiple rounds (see section 5).

### R12 -- SIMD into production, SLIC, TD-PSOLA, DP UI, Louvain, AST const-fold

* CrossEngin: `b402762 + dbd0121 + 3a99e00 io: SIMD-accelerated stereo
  SAD + LK accumulators (R12A core/parts)`, `9fb82cb tests: SIMD
  production verification (R12A)`, `ea67c28 scripts: SIMD production
  benchmark (R12A)`, `ebccd92 docs: R12A SIMD wiring -- bit-identical
  with honest perf observation`, `40f9a3a + 06f878a + 09d5a3d + 81dd67f
  io: SLIC superpixel + dispatch + tests (R12B)`, `d474222 audio:
  TD-PSOLA (R12D)`, `Louvain (R12C)`, `92f6a11 chat: wire /dp + status
  pane (R12F)`.
* NOVA: `022586d codegen: AST-level constant folding + DCE passes`,
  `2b58d5a nova-dap: evaluate request + conditional breakpoints`.
* Key insight: R12A is the *honest negative perf result* round. The
  i32x8 wrapper at production granularity was slower than scalar. The
  agent shipped the wiring anyway (bit-identical) plus a benchmark
  script and an honest writeup. That document became the template
  for R17C and R21D later. Engineering culture > optimistic claims.

### R13 -- pyramidal LK propagation, voice cloning, PageRank, incremental
       deltas, call-site inlining

* CrossEngin: `6d05d01 io: full per-pixel pyramidal LK propagation
  (R13B)`, `942a1cd audio: voice cloning via Klatt formant transfer
  (R13D)`, `0ee706b kg: PageRank centrality (R13E)`,
  `b1b662e persistence: incremental delta-snapshot writes (R13F)`.
* NOVA: `11ae0d0 codegen: inline SIMD + int_* builtins at call site
  (R13A)`, `85fe64a nova-lsp: semantic tokens`, `a852a39 nova-lsp:
  hover surfaces /// doc-comments`.
* Key insight: R13A's call-site inlining is what made R12A's wiring
  *finally* speed up stereo SAD (1.93x). The substrate-codegen
  ping-pong (one round adds the primitive, the next round adds the
  wiring, a *third* round adds the inlining that makes it actually
  fast) became the dominant cadence.

### R14 -- HOG descriptor, DSP effects, Ed25519, simd_sad_u8

* CrossEngin: `2bb1533 io: HOG dense descriptor (R14D)`,
  `70408d6 audio: Schroeder reverb + noise gate (R14E)`,
  `9f1eb27 safety: Ed25519 (RFC 8032) + inline SHA-512 (R14F)`.
* NOVA: `698f8e9 codegen: simd_sad_u8 raw-byte SAD primitive via AVX2
  vpsadbw (R14B)`, `3691954 nova-dap: function breakpoints by name`.
* Key insight: R14B shipped the right primitive (single-byte AVX2
  vpsadbw) that the R11D / R13A i32 path couldn't deliver. The lesson:
  sometimes the right SIMD answer is "build a different primitive",
  not "tune the wrapper around the existing one". Width and
  semantics matter, not just lane count.

### R15 -- u8 SIMD realized (stereo + LK), HOG detector, mini-SPARQL,
       Merkle, WASM SIMD

* CrossEngin: `d224e9d io: wire R14B simd_sad_u8 into stereo SAD --
  5.5x absolute speedup (R15A)`, `a5005d6 kg: mini-SPARQL declarative
  query (R15D)`, `5c9af37 io: HOG sliding-window object detector
  (R15C)`, `994fc0b persistence: Merkle-tree tamper-evident snapshot
  (R15E)`.
* NOVA: `7e50f26 codegen: WASM v128 SIMD lowering — close R11D's last
  gap (R15B)`, `5a57beb nova-lsp: call hierarchy`.
* Key insight: R15A is the first big realization payoff (5.5x absolute
  on stereo SAD). The key load-bearing component turned out to be
  `memcpy_raw` -- without a fast raw memcpy in NOVA, the staging cost
  would have eaten the SIMD win. That observation drove the R17C +
  R18A discussions about "where else is memcpy/staging on the hot
  path".

### R16 -- Ed25519 sign+verify of snapshots, mini-SPARQL extensions, Haar
       face detect, STFT/FFT, match-as-expr

* CrossEngin: `64bb243 persistence: Ed25519 sign + verify of Merkle
  snapshot root (R16A)`, `95e83f4 kg: mini-SPARQL OPTIONAL + UNION +
  ORDER BY (R16F)`, `c895138 io: Viola-Jones Haar cascade face detector
  STRUCTURAL (R16D)`, `ae6dc50 audio: STFT / Cooley-Tukey FFT (R16E)`.
* NOVA: `047ace1 codegen: match-as-expression block-body locals + frame
  allocation`, `c530629 nova-lsp: inlay hints`.
* Key insight: R16D is honest about being "structural" -- it ships
  the Haar cascade infrastructure without a trained model. Substrate-
  first: get the wire/AST/algorithm right; train later. Same approach
  as R10B (whisper as a backend, not a baked weight).

### R17 -- u8 SIMD into LK (honest), LBP, mini-SPARQL aggregates, MFCC,
       sum types + match exhaustiveness

* CrossEngin: `8002120 io: wire R14B simd_sad_u8 into optical-flow LK
  -- HONEST 0.80x full LK / 5.09x vs i32 / 58.2x image-SAD (R17C)`,
  `2f08de3 io: LBP texture descriptor (R17D)`,
  `42d3953 kg: mini-SPARQL aggregates COUNT/SUM/AVG/MIN/MAX (R17E)`,
  `43be1bd audio: MFCC front-end (R17B)`.
* NOVA: `41f0332 codegen: NOVA sum types with payloads + match
  exhaustiveness (R17A)`, `38619aa nova-dap: instruction-level stepping`.
* Key insight: R17C is the canonical honest-disclosure round. The
  agent could have buried the 0.80x and shipped only the 58.2x
  image-SAD headline. Instead it shipped all three numbers in the
  commit message (`HONEST 0.80x full LK / 5.09x vs i32 / 58x
  image-SAD`) plus a calibration-by-component breakdown. That set the
  bar for R12A, R21D, R22F, R26F.

### R18 -- LK with mul-acc (3.69x), link prediction, wake-word, face
       recognition, SWIM gossip, mul-acc SIMD primitive

* CrossEngin: `ee0f6fb io: wire R18A byte mul-acc SIMD into LK -- 3.69x
  absolute (R18A.2)`, `9484073 kg: link prediction over the KG xref
  graph (R18B)`, `31e8ee3 audio: wake-word detection via DTW on MFCC
  (R18C)`, `1b53a2a io: LBP-gallery face RECOGNITION (R18D)`,
  `79e8ed2 federation: SWIM-style gossip protocol -- peer discovery +
  KG delta sync (R18E)`.
* NOVA: `db34532 codegen: byte mul-acc SIMD primitives close R17C LK
  ceiling (R18A)`, `3a6e217 nova-lsp: code lens`.
* Key insight: R18A is the chase-down of R17C's 0.80x ceiling. R17C
  exposed the structural mismatch ("byte-SAD doesn't fit u8 * u8
  accumulators"). R18A added the missing primitive (byte mul-acc),
  R18A.2 wired it and finally got 3.69x. End-to-end perf chain spans
  four rounds (R14B → R17C → R18A → R18A.2). See section 5 for the
  full chain layout.

### R19 -- Allen temporal reasoning, speaker ID, Bully leader election

* CrossEngin: `29bb8ce kg: temporal reasoning -- Allen's 13-relation
  interval algebra (R19C)`, `e8172f1 audio: speaker ID via MFCC
  gallery + DTW NN classifier (R19D)`, `3d04a6a federation: Bully-
  algorithm leader election over R18E gossip mesh (R19E)`.
* NOVA: `618635d codegen: cross-target enum codegen — R17A.2
  follow-up (R19B)`, `a32e95c nova-lsp: type hierarchy navigation`.
* Key insight: R19E is the first round where two federation features
  shared the same gossip wire (R18E PING / MEMBER + Bully ELECTION /
  COORDINATOR), without each other knowing. The gossip state-slot
  reservation pattern (each agent gets an exclusive contiguous range)
  was first formalized here in code review.

### R20 -- Result/?, mini-Datalog inference, cross-modal fusion, distributed
       SPARQL, signed attestation, quickfix LSP

* CrossEngin: `5e63288 kg: forward-chaining mini-Datalog rule inference
  (R20B)`, `dafb7e5 perception: cross-modal sensor fusion (R20C)`,
  `74170d0 federation: distributed SPARQL via gossip mesh fan-out
  (R20E)`, `1ec5280 federation: gossip-relayed signed snapshot
  attestation (R20F)`.
* NOVA: `c49ebf8 codegen: Result + postfix ? propagation operator
  (R20A)`, `04f1378 nova-lsp: quickfix — auto-add missing match arms
  (R20D)`.
* Key insight: R20A's `?` operator was the first "syntax round" that
  didn't change runtime behaviour at all -- pure parser-and-codegen
  surface refinement. Established the "parser-only zero-cost" pattern
  that R21A, R22B, R23A, R25A, R26A all rode on.

### R21 -- distributed rules, TTS pipeline, HOG integral (0.25x honest),
       Noise-XK transport, generic enums, LSP extract-fn

* CrossEngin: `d752b9b federation: distributed rule inference --
  mini-Datalog over gossip mesh (R21B)`, `46af6ff audio: end-to-end TTS
  pipeline (R21C)`, `34dd2e7 image: HOG accelerated via integral
  histogram of gradients (R21D)`, `b6d559a federation: Noise-XK
  transport for R18E gossip mesh (R21E)`.
* NOVA: `c7b6b33 codegen: NOVA generic enum payload types -- Result<T,
  E> truly parametric (R21A)`, `ce4f878 nova-lsp: extract-function
  refactor`.
* Key insight: R21D shipped HOG integral histogram with an honest
  0.25x amortization play -- single-call slower, but the structure
  (the integral histogram) is what made R22A's 2.15x wrapper achievable
  three rounds later. R21A made generics syntax-only -- the dynamic
  runtime simply ignores type parameters at the IR level.

### R22 -- HOG detector 2.15x, generic fns, LSP folding, panorama stitch,
       provenance proof trees, melody, harmonicity auto-switch

* CrossEngin: `a300c95 image: wire R21D HOG integral histogram into
  R15C sliding-window detector -- ~2.15x absolute (R22A)`,
  `02be52e image: panorama stitching -- R5C SIFT + R6D ORB + RANSAC +
  homography + warp + blend (R22D)`, `205000a kg: recursive provenance
  walks -- proof trees for derived atoms (R22E)`, `33b6e05 audio:
  melody extraction -- F0 contour to MIDI note sequence (R22F)`.
* NOVA: `3fd1a6a parser: NOVA generic function signatures — extend
  R21A from enums to fns (R22B)`, `47769af nova-lsp: folding ranges +
  document symbols (R22C)`.
* Key insight: R22A is the realization of R21D's amortization promise.
  Whole-detector wrapping (one integral image, N window queries) is
  what reaped the 2.15x. R22D is the first round that fully reuses
  *four* prior rounds (SIFT R5C, ORB R6D, RANSAC built in R22D itself,
  warp+blend built in R22D) -- proof that the early-round investment
  in feature primitives keeps paying off rounds later.

### R23 -- lip sync, generic structs, snapshot replication, image tracker,
       NAT traversal, LSP workspace diag

* CrossEngin: `43a00f5 perception: audio-vision lip sync detection
  (R23B)`, `b5cbb9b federation: gossip SNAP_FETCH/SNAP_DATA/SNAP_END
  wire (R23C)`, `388e3a0 image: tracker tests + chat wiring (R23D)`,
  `c203dfb federation: NAT traversal -- STUN-like external addr
  discovery (R23E)`.
* NOVA: `ef159ec parser: NOVA generic structs + lightweight type-check
  pass (R23A)`, `bb61c6f nova-lsp: workspace diagnostics aggregation
  (R23F)`.
* Key insight: R23C + R23E are both federation-extension rounds
  occupying *different* gossip state-slot ranges (R23C took
  SR_STATE=29, R23E took NAT_STATE=32). The state-slot reservation
  block in `src/federation/gossip.nova` is what made this safe; the
  human-visible artifact is one block of `let GOSSIP_S_* = N` lines
  that grows by 2-4 slots per round with explicit labelled comments
  pointing at the owning agent.

### R24 -- image OCR, type-check pass, video temporal smoothing, tree-sitter
       refresh, LSP type-aware completion

* CrossEngin: `4e42dd6 image: OCR via character template matching
  (R24C)`, `3ef2d12 image: video temporal smoothing -- Kalman over
  R23D tracker outputs (R24F)`.
* NOVA: `fda288c parser: NOVA fn-call + struct-ctor type-check —
  R23A.2 followup (R24A)`, `72db976 tree-sitter-nova: R17A-R23A syntax
  refresh (R24B)`, `940c4f6 nova-lsp: type-aware completion (R24E)`.
* Key insight: R24F is the first "compose-on-previous-round" video
  module -- it takes the R23D tracker outputs as input and adds the
  Kalman temporal smoothing. R24A is the formal "type-check pass"
  follow-up to the parser-only generic structs of R23A: the
  parser-zero-cost pattern hardened.

### R25 -- struct brace-init, voice conversation, RSS ingestion, arch docs,
       bench harness, LSP inline-var

* CrossEngin: `8c1c978 demo: end-to-end voice conversation pipeline
  (STT -> KG -> TTS) (R25B)`, `ad55968 io: RSS / Atom feed ingestion
  into the KG (R25C)`, `1bc3d6c docs: ARCHITECTURE.md system layout +
  module catalog (R25D)`, `a9ff3a8 bench: unified harness + JSON
  baseline + regression diff (R25E)`.
* NOVA: `7b74e7e parser: NOVA struct brace-init + destructure pattern
  (R25A)`, `a39ba6a docs: ARCHITECTURE.md compiler + runtime layout
  + module catalog (R25D)`, `e2a87a9 nova-lsp: inline-variable
  refactor (R25F)`.
* Key insight: R25B is the first "end-to-end demo round" that consumes
  multiple prior rounds (R10B whisper, R10F pitch, R11B YIN, R17B
  MFCC, R21C TTS) and stitches them into a usable voice pipeline.
  R25E shipped the bench harness + baseline.json that R26F then used
  to verify zero regressions across the entire R26 sprint.

### R26 -- spectral-subtraction Wiener, struct update-syntax, regression hunt,
       LSP brace-init completion, gossip relay

* CrossEngin: `a4f3563 audio: spectral-subtraction Wiener noise
  reduction (R26C)`, `f2b4fd4 federation: gossip relay -- route via
  intermediary when direct dial fails (R26E)`, `7b17ad0 bench: R26F
  regression-hunt sweep -- zero regressions, three FASTER`.
* NOVA: `1f398a8 parser: NOVA struct update-syntax Point { x: 10,
  ..p } (R26A)`, `916df6b tree-sitter-nova: R25A brace-init +
  destructure refresh (R26B)`, `7932060 nova-lsp: brace-init field
  completion (R26D)`.
* Key insight: R26C closes the *frequency-domain* denoising gap that
  R14E (noise gate) and R7F (VAD) only partially addressed. R26E
  closes the *peer reachability* gap that R23E NAT traversal opened
  but couldn't fully solve without UDP hole-punching. R26F is the
  Regression-Hunt round whose job was *to fail to find regressions*
  -- and it did. Three speedups were discovered as side effects of
  the NOVA toolchain rebuild between baseline capture and the hunt.
  Honest scoping has become the load-bearing engineering discipline of
  the sprint.

---

## 2. Cross-agent coordination patterns that worked

### 2.1 File-ownership scoping by src/ subtree

Every agent in every round was assigned an exclusive write set, almost
always a single src/ subtree:

* R6's six agents: `src/io/` (R6D ORB), `src/safety/` (R6B Montgomery),
  `src/io/transducers/` (R6E ARPAbet), `src/io/transports/` (R6C kg_sync
  v3), `src/kg/` (R6F episodic), and the parser changes (R6A).
* R20's six agents: `src/codegen/` (R20A), `src/kg/` (R20B), `src/io/`
  (R20C), `src/nova-lsp/` (R20D), `src/federation/` (R20E + R20F).
  The two federation agents collaborated through gossip.nova state-slot
  reservations rather than file separation.

Result: across 26 rounds and ~156 agent dispatches, the number of
cross-agent file-write conflicts that actually clobbered work was
*small* (the brief mentions "stale stashes" -- usually from work-tree
resets, not direct conflict). The dominant pattern was clean.

### 2.2 Labeled coordination blocks in shared files

Two files necessarily had multiple agents touching them across rounds:
`src/federation/gossip.nova` and `examples/crossengin_chat.nova`.

For `gossip.nova` the state-slot reservation block (see the
GOSSIP_S_* constants at the head of the module) is the coordination
artifact:

```
let GOSSIP_S_ATT_STORE      = 14   // R20F: signed attestation
let GOSSIP_S_ATT_PUBKEYS    = 15   //  "
let GOSSIP_S_STATS_ATT_RX   = 16   //  "
let GOSSIP_S_STATS_ATT_BAD  = 17   //  "
let GOSSIP_S_DR_STATE       = 18   // R21B: distributed rules
let GOSSIP_S_STATS_DR_RULES = 19   //  "
...                                // R21B 18-21
let GOSSIP_S_NOISE_PRIV     = 22   // R21E 22-28
...
let GOSSIP_S_SR_STATE       = 29   // R23C 29-31
let GOSSIP_S_NAT_STATE      = 32   // R23E 32-34
let GOSSIP_S_RELAY_STATE    = 35   // R26E 35-37
```

The brief notes "R20E 18-21, R20F 22-25, R21B/E 22-34, R23C/E 29-34,
R26E". In the current code the actual layout is slightly different
(R20F took 14-17, R20E never reserved slots because it routed via
DQUERY without persistent state, R21B took 18-21, R21E took 22-28, R23C
took 29-31, R23E took 32-34, R26E took 35-37). The principle held:
every new agent picked an unused contiguous range, labelled it with a
round-id comment, and never reused another round's slots.

For `examples/crossengin_chat.nova` the coordination artifact is the
dispatch-table + help-line append-only pattern: each new module is one
import + one help line + one dispatch arm. R12F added /dp, R12B added
/slic, R15D added /sparql, R20E added /dquery, R20F added /attest,
R21B added /drules, R21C added /tts, R22D added /pano, R22E added
/why_deep, R22F added /melody, R23C added /snap_replicas, R23E added
/nat, R24C added /ocr, R24F added /tracksmooth, R25B added /voice_chat,
R25C added /rss, R26C added /denoise, R26E added the relay
diagnostics. No round ever touched a different round's dispatch arm.

### 2.3 WIP-commit-immediately pattern

In R23 (specifically R23C and R23D) the agents discovered that the
work-tree gets reset between bash invocations in this harness, and
that a parallel agent's stash operation could wipe their in-progress
work. The mitigation that worked:

* Commit the module WIP immediately with a `(R23X wip)` suffix in the
  commit subject.
* Once verification is done, follow up with the tests + chat-wiring
  commit `(R23X)` and the docs commit.

The git log shows the pattern in action:

```
c3aec20 image: tracker WIP module to protect from agent wipe (R23D)
388e3a0 image: tracker tests + chat wiring (R23D)
3c21995 federation: snapshot replication module (R23C wip)
a914dd9 tests: unit tests for snapshot_replication (R23C, 73 assertions)
b5cbb9b federation: gossip SNAP_FETCH/SNAP_DATA/SNAP_END wire (R23C)
```

After R23 every long-running agent (anything over ~10 minutes wall) WIP-
committed first. R24A (the heavy parser type-check) followed this
pattern. R26C (~580 lines of frequency-domain Wiener) followed it.

### 2.4 Stash-cleanly hand-off pattern

When an earlier agent left a stash on the branch (because *its* harness
reset the work-tree mid-write), later agents picked up the stash with
an explicit label and either re-applied it or marked it stale:

```
188cbef On claude/festive-franklin-PP7mW: R27B stash: stale
        _scenario_vvvv_drivers deletions
fa6a65e index on claude/festive-franklin-PP7mW: e2657e3 test: R26E
        gossip-relay scenario -- skip PING during warmup
```

The labels (`R27B stash: stale ...`) made it possible for the next
agent to read the stash list and know what was junk vs. what to
re-apply. Without labels, stashes accumulate as opaque "WIP on ..."
entries and become permanent confusion.

### 2.5 Append-only dispatch + import-order discipline

The single chat binary has hundreds of dispatches. The discipline that
held across 26 rounds:

* Imports stay alphabetically grouped by subdirectory (no module
  reordered another's imports).
* Dispatch arms appended at the bottom of the help text; help text
  itself is a single multiline string; no rebalancing.
* New module-introduction commits add exactly one line per group (one
  import, one help line, one dispatch arm).

Result: chat-side merge conflicts across 26 rounds were close to zero
even though dozens of agents touched the file.

### 2.6 BENCH harness + baseline as a coordination artifact

R25E shipped `scripts/bench.sh` + `bench/baseline.json` with the
explicit purpose of being the cross-round coordination artifact.
After R25E, every subsequent perf-sensitive round can call the same
harness and compare against the same baseline. R26F is the first round
that used it for a true regression hunt; it found three FASTER results
and zero regressions, demonstrating the artifact works.

---

## 3. Cross-agent failure modes (and their mitigations)

### 3.1 Work-tree reset clobbering

The single highest-impact failure mode. Two ways it manifested:

* Agent A starts editing `src/foo/bar.nova`; agent B's harness resets
  the work tree mid-edit; A's bash invocation returns "nothing to
  commit" because the file is back to HEAD. A has no signal that the
  reset happened other than the missing diff.
* Agent A writes a new module; agent B stashes the index; A's next
  Edit fails because the file isn't in the work tree.

Mitigation (adopted from R23 onward): immediate WIP commit on first
clean compile of a new module. Subsequent edits commit on every
verified test pass.

### 3.2 Stale stashes causing confusion

When the harness silently stashes mid-round, the stash entries
accumulate. By round 27 the CrossEngin repo had:

```
188cbef On claude/festive-franklin-PP7mW: R27B stash: stale
        _scenario_vvvv_drivers deletions
fa6a65e index on claude/festive-franklin-PP7mW: e2657e3 ...
```

Mitigation: every stash gets a labelled message `R<round><agent>
stash: <one-line summary>`. Bare `WIP on ...` is the bad shape; the
labelled stash is the good shape. Future agents (including R27F at
the time of writing) inspect `git stash list` and either drop stale
entries or re-apply them deliberately.

### 3.3 Module count drift

During parallel rounds the on-disk module count fluctuated. Agent A
counts 142 .nova files in src/ at the start of its round; agent B
finishes a round mid-flight and lands 143. Agent A's writeup quotes
142; agent B's writeup quotes 144 (its new module plus A's). README
disagrees with NEXT_SESSION until a sync round.

Mitigation: count modules *at commit time* with the actual file glob,
include the count only in NEXT_SESSION (not in module-introducing
commits), and accept that README's count is a snapshot. The R25D
architecture doc decided to publish module *catalogues* (lists by
phase) rather than running totals, which is regression-proof.

### 3.4 Documentation race

Multiple agents updating NEXT_SESSION.md or README.md in parallel
create merge headaches. The pattern that mitigated it:

* Every round prepends its writeup to NEXT_SESSION.md (so later rounds
  push the older entries down without conflict).
* README's `> Status:` quote block is append-mostly: each round's
  paragraph appends to the previous, separated by `>`. The R26C +
  R26E + R26F additions are each their own `>` block; rare merge
  conflict.
* `*_AUDIT.md` files are scoped: AUDIO_AUDIT for audio rounds,
  IMAGE_AUDIT for image, FEDERATED_AUDIT for federation, etc. No
  cross-domain audit pollution.

### 3.5 Toolchain breakage from in-flight parser changes

R25C (the agent that landed the RSS feed ingestion) noted that R25A's
in-flight parser change (struct brace-init) temporarily broke `nova
build` until both stages re-bootstrapped. The mitigation that worked:

* R25A's commit was order-sensitive: parser change first, codegen
  acceptance second, stage2/stage3 verification third. The agent kept
  the commits split so that any in-between agent doing `make
  self-host` could see a clean failure rather than a silent
  miscompile.
* R25C avoided new syntactic forms in its writes (no brace-init in
  the RSS module) until R25A had landed on origin. The R25C agent
  explicitly held its commit until R25A was upstream.

The corollary: cross-repo (NOVA + CrossEngin) sprints need a strict
dependency direction. NOVA syntax features must land on origin
*before* CrossEngin modules use them. R26F's success at finding zero
regressions is partly because R26A → R26B → R26D were strictly
serialized parser-syntax updates that completed before R26C/R26E
ran their full bench/integration sweeps.

### 3.6 Honest-disclosure pressure

A latent failure mode: an agent that produces a worse-than-baseline
perf number is tempted to bury it and ship only the favourable
sub-measurement. The mitigation has been social: R12A, R17C, R21D,
R22F, R26F all *led* their writeups with the honest negative or
qualified number. The pattern in the commit subject is the load-
bearing artifact:

* `io: SIMD-accelerated stereo SAD block-matching (R12A part 1)` ->
  later `docs: R12A SIMD wiring -- bit-identical with honest perf
  observation`.
* `io: wire R14B simd_sad_u8 into optical-flow LK -- HONEST 0.80x
  full LK / 5.09x vs i32 / 58x image-SAD (R17C)`.
* `audio: harmonicity auto-switch between R10F autocorrelation and
  R11B YIN (R22F.2)`.

The HONEST and bit-identical markers in the subject line are the
honest-disclosure flags. Any reviewer or future agent reading git log
can immediately spot a qualified result.

---

## 4. Honest engineering disclosures noted

This sprint has more honest engineering disclosure than is typical of
multi-agent code generation. The mature instances:

### 4.1 R12A -- SIMD wrapper slower than scalar at production granularity

R12A wired R11D's i32x8 SIMD into both stereo SAD and LK accumulators.
The bit-identity test passed. The benchmark showed the wrapper *slower*
than scalar at production block sizes -- per-call dispatch overhead
exceeded the AVX2 throughput win for the 8-element vectors that the
stereo SAD inner loop wanted. The writeup
`ebccd92 docs: R12A SIMD wiring -- bit-identical with honest perf
observation` shipped the regression as a documented observation, *not*
as a hidden detail.

Downstream consequence: R13A added call-site inlining of SIMD and int_*
builtins. R14B shipped a different primitive (raw-byte vpsadbw at the
right width). R15A finally got the absolute 5.5x. The honest disclosure
in R12A was what made the chase-down legible across rounds.

### 4.2 R17C -- 58.2x on image-residual but 0.80x on full LK

The writeup decomposed the perf signal across three layers:

* Image-residual SAD primitive (the inner-inner loop): 58.2x. The
  vpsadbw direct hit.
* SIMD vs the prior i32 wrapper: 5.09x. Comparing apples to apples
  on the inner-inner loop.
* Full LK pyramidal solver: 0.80x. The wrapper sits inside an
  accumulator loop that needs *signed* products, not unsigned absolute
  differences. The vpsadbw output had to be re-widened and signed-
  promoted on every iteration. Net regression.

The fix path was clear: build a *byte mul-accumulator* primitive.
That landed as R18A and R18A.2 closed the loop with a 3.69x absolute
speedup on full LK.

### 4.3 R21D -- 0.25x single-call HOG amortization

R21D shipped the integral-histogram HOG accelerator. Single-call
benchmark: 0.25x (i.e., the wrapper is 4x slower than the original
scalar at one call). The writeup explicitly said: the structure pays
for itself only at high window-count, where each window only costs an
O(1) histogram subtraction instead of an O(N) recomputation. R22A then
shipped the actual amortization play -- the sliding-window detector
calling the integral histogram thousands of times per frame -- and
got the 2.15x absolute win.

Lesson: an amortization-shaped primitive can ship as 0.25x and *still
be the right design*, provided the writeup names the amortization and
sketches the wrapper that realizes it.

### 4.4 R22F -- autocorrelation vs YIN choice for melody

R22F shipped melody extraction (F0 contour -> MIDI). The choice between
R10F autocorrelation and R11B YIN was non-obvious. The writeup picked
R10F for melody, citing:

* YIN's octave-down anti-snap collapses on pure sines.
* Music content (the actual signal of interest for melody) has
  broadband harmonic structure that autocorrelation handles cleanly.

R22F.2 then auto-switched: a spectral peakiness gate decides per frame
whether to call YIN or autocorrelation. Pure 200 Hz sine -> AC. Klatt
/ae/ formants -> YIN. Honest choice based on actual signal
characteristics, not "the most cited paper".

### 4.5 R26F -- zero-regression hunt that found three speedups

R26F's job was to find regressions. It found none. It found three
speedups (`hog_detector_integral` -65.8%, `hog_detector_scalar`
-40.0%, `nova_dot_simd` -19.9%). The writeup:

* Attributed the speedups to a NOVA `bin/nova` rebuild between R25E
  baseline capture and the hunt.
* Documented the baseline-refresh policy decision: do *not* refresh,
  because refreshing turns the FASTER readings into NOMINAL and
  weakens future regression detection.
* Verified that all R25E headline numbers (R15A 5.5x, R18A.2 3.36x,
  R17C 110x image-SAD, R11D 137x NOVA SAD) still hold.

This is honest engineering disclosure as cultural artifact: even a
*positive* finding (three speedups) is published with full causal
attribution and a careful decision about whether to lock it in.

---

## 5. Realization-of-perf chains: primitive → wired → inlined → realized

The dominant cadence of perf work in this sprint is a multi-round
chain. Three canonical chains:

### 5.1 SIMD i32x8 → scalar → byte mul-acc → 3.69x LK

```
 R11D (NOVA codegen)       SIMD i32x8 intrinsics primitive shipped,
                           no user yet.
 R12A (CE io)              Wire i32x8 into stereo SAD + LK. Bit-
                           identical, *honest* perf regression: the
                           per-call dispatch eats the wrapper's win
                           at production block sizes. Shipped the
                           wiring + benchmark + honest writeup.
 R13A (NOVA codegen)       Inline SIMD + int_* builtins at call
                           site. Now the dispatch overhead is gone.
 R14B (NOVA codegen)       simd_sad_u8 raw-byte primitive via AVX2
                           vpsadbw. The semantically-correct
                           primitive for byte block matching.
 R15A (CE io)              Wire R14B into stereo SAD -> 5.5x
                           absolute speedup. Realization #1.
 R17C (CE io)              Wire R14B into LK -> 58.2x on image-SAD,
                           5.09x vs i32, but *0.80x* on full LK.
                           Honest disclosure of the structural
                           mismatch: byte-SAD doesn't fit u8 * u8
                           accumulators.
 R18A (NOVA codegen)       Byte mul-acc SIMD primitives -- the
                           semantically-correct primitive for LK
                           accumulators.
 R18A.2 (CE io)            Wire R18A into LK -> 3.69x absolute.
                           Realization #2.
 R19A                      (no perf round needed; chain closed)
```

The chain spans eight rounds and crosses repos four times. The
chain-completing artifact: a single benchmark, R25E, sweeps the
whole thing and reports baseline ratios that R26F still confirms.

### 5.2 Stereo SAD: R12A regression → R13A inline → R15A 5.5x

```
 R12A   wrap i32 SIMD into stereo SAD       (regression, bit-id)
 R13A   call-site inline                    (NOVA codegen fix)
 R14B   raw-byte vpsadbw primitive          (NOVA codegen)
 R15A   wire R14B into stereo SAD           (5.5x absolute)
```

Load-bearing in R15A: `memcpy_raw`. Without a fast raw memcpy in NOVA
the staging cost would have eaten the SIMD win. That observation has
shaped every subsequent perf round (R17C, R18A, R22A all check for
staging-dominance before claiming a speedup).

### 5.3 HOG: R14D primitive → R21D 0.25x → R22A 2.15x

```
 R14D   HOG dense descriptor primitive      (CE io, no user)
 R15C   HOG sliding-window detector built   (CE io, scalar)
 R21D   HOG integral histogram accelerator  (single-call 0.25x,
                                              honest writeup that
                                              names the amortization)
 R22A   wire R21D's integral histogram into
        R15C's sliding-window detector      (2.15x absolute)
```

The interesting structural point: the wrapper in R21D *had* to be
slower at single-call. The amortization is the entire point. R22A
delivered it.

---

## 6. NOVA language evolution arc

The NOVA language evolved over 11 rounds with a remarkably consistent
discipline: every new surface form is either *parser-only zero-cost*
(no runtime touch, the dynamic runtime simply doesn't care about types)
or a localized codegen lowering. The arc:

* **R17A** -- sum types with payloads + match exhaustiveness. The
  first "real type system" feature. Codegen emits tagged-union layouts
  at the call site.
* **R20A** -- Result + postfix `?` propagation operator. Pure parser
  + tiny codegen lowering. Sets the template for "syntax rounds".
* **R21A** -- generic enum payload types. Parser sees `<T, E>`,
  codegen treats T and E as `int` at runtime (NOVA's dynamic type
  system uses a single discriminator). Generics are entirely a
  parser-and-typechecker concern -- zero runtime cost.
* **R22B** -- generic function signatures, extending R21A from enums
  to functions. Same shape.
* **R23A** -- generic structs + lightweight type-check pass. Same
  shape, plus a real type-check pass that emits warnings on obvious
  mismatches.
* **R24A** -- fn-call + struct-ctor type-check, R23A.2 follow-up.
  The type-check pass got teeth.
* **R25A** -- struct brace-init + destructure pattern. Pure parser
  lowering: `Point { x: 1, y: 2 }` rewrites to the positional ctor.
* **R26A** -- struct update-syntax `Point { x: 10, ..p }`. Parser-
  emitted do-expr wrapper auto-caches the base in a fresh temp so it
  evaluates exactly once.

The "parser-only zero-cost" pattern means NOVA's dynamic runtime is
the foundation that lets the language grow rapidly without runtime
bloat. Tree-sitter / LSP / DAP tooling lag by exactly one round
(R24B refreshes tree-sitter to cover R17A..R23A; R26B refreshes for
R25A; R26D adds LSP brace-init completion for R25A). The tooling
serialization is the only hard sync point between language rounds.

The full IDE-side count after R26: 17 LSP capabilities, 21 DAP
capabilities (see NOVA NEXT_SESSION.md for the per-capability ledger).
The substrate-first invariant -- "ship the wire, ship the parser,
ship the codegen, ship the tooling, in that strict order" -- held
across every NOVA round.

---

## 7. Federation layer evolution

The federation layer is the longest single chain of work in the sprint.
It started as a TCP atom-birth pub/sub in early P2 and has grown into
a SWIM-style gossip mesh with signed attestations, distributed rules,
Noise-XK transport, snapshot replication, NAT traversal, and now relay
routing.

* **R7C** -- kg_sync v3 + Noise XK handshake. First real
  authentication on the wire. Noise XK gives mutual auth + transport
  encryption between known-peer pairs. This is the foundation. (DH-2048
  RFC 7919 Group 14 strength upgrade in the same round.)
* **R18E** -- SWIM-style gossip protocol. Peer discovery + KG delta
  sync. Establishes the GOSSIP_S_* state-slot layout that all later
  rounds reserve from.
* **R19E** -- Bully-algorithm leader election over R18E gossip mesh.
  Shares the wire but reserves no new state slots (election state is
  ephemeral). First multi-feature-on-one-wire round.
* **R20E** -- Distributed SPARQL via gossip mesh fan-out. Routes
  queries through R18E PING/MEMBER discovery; same wire.
* **R20F** -- Gossip-relayed signed snapshot attestation. Takes
  state slots 14-17 (ATT_STORE, ATT_PUBKEYS, STATS_ATT_RX,
  STATS_ATT_BAD). First "shared file with state-slot reservation
  block" pattern.
* **R21B** -- Distributed rule inference (mini-Datalog over gossip
  mesh). Takes state slots 18-21 (DR_STATE, STATS_DR_RULES_RX,
  STATS_DR_DERIVS_RX, STATS_DR_FETCHES_RX).
* **R21E** -- Noise-XK transport for R18E gossip mesh. Takes state
  slots 22-28 (NOISE_PRIV, NOISE_PUB, NOISE_PEERS, NOISE_STRICT,
  STATS_NOISE_HS, STATS_NOISE_HS_FAIL, STATS_NOISE_REFUSED). Wraps
  the *transport*, not the per-feature wires; all earlier features
  inherit the encryption.
* **R23C** -- Snapshot replication via gossip (SNAP_FETCH /
  SNAP_DATA / SNAP_END wire). Takes state slots 29-31 (SR_STATE,
  STATS_SR_FETCH_RX, STATS_SR_DATA_RX).
* **R23E** -- NAT traversal: STUN-like external-addr discovery +
  gossip advertise. Takes state slots 32-34 (NAT_STATE,
  STATS_NAT_EXTADDR_RX, STATS_NAT_EXTADDR_BAD). Stubs UDP hole-
  punching pending NOVA `sendto`/`recvfrom`.
* **R26E** -- Gossip relay: route via intermediary when direct dial
  fails. Takes state slots 35-37 (RELAY_STATE, STATS_RELAY_REQ_RX,
  STATS_RELAY_DATA_RX) plus several more. Closes the practical
  reachability gap that R23E couldn't fully close.

Total federation state slots reserved across 26 rounds: 38 (0-37).
Zero collisions, six separate agents writing concurrently into the
same file across nine rounds.

---

## 8. What is still open after 26 rounds (R*.2 follow-ups)

A non-exhaustive ledger of the explicitly-deferred follow-ups, by
round-of-origin:

### CrossEngin

* **R10B.2** -- model loading for offline whisper backend in the
  Vosk wiring (currently subprocess + bundled binary).
* **R12A.2** -- closed (R13A inlining + R14B/R15A realized the win).
* **R17C.2** -- closed (R18A mul-acc primitive + R18A.2 wiring
  realized the 3.69x).
* **R20E.2** -- distributed SPARQL with aggregates / GROUP BY across
  the fan-out (current R20E aggregates only on the originator;
  partial-aggregation push-down would reduce wire traffic).
* **R21D.2** -- closed (R22A wrapper realized the 2.15x).
* **R22F.2** -- closed (auto-switch landed in c665d53).
* **R22F.3 / R22F.4** -- multi-pitch tracking (chord transcription);
  expressive note-onset detection.
* **R23B.2** -- learned lip-sync correlator (current is heuristic
  mouth-open vs voicing).
* **R23C.2** -- snapshot-replication with delta-only (current ships
  full snapshots); resume-on-disconnect.
* **R23E.2** -- UDP hole-punching once NOVA sendto/recvfrom land;
  TURN-like relay protocol on top.
* **R24C.2** -- better OCR (current is template matching; would
  benefit from CC-based segmentation + per-glyph normalization).
* **R25B.2** -- streaming voice conversation (current is utterance-
  by-utterance); barge-in / interrupt support.
* **R25C.2** -- HTML entity decoding beyond the basic set; iCalendar
  ingestion.
* **R26C.2** -- multi-band Wiener; continuous noise re-estimation
  via R7F VAD; soft-decision Wiener / MMSE-STSA (Ephraim-Malah
  1984); DNN-based denoising.
* **R26E.2** -- full STUN-like relay discovery; UDP relay path; pre-
  flight reachability check; multi-hop chains with loop prevention;
  relay-side auth; Noise-XK wrap of the relay segments.

### NOVA

* **R20A.2** -- `?` for non-Result error types (option-like None);
  closed-arm exhaustiveness in match for nested patterns.
* **R23A.2** -- closed (R24A landed the type-check pass).
* **R25A.2** -- generic-typed brace-init `Box<int> { value: 42 }`
  needs an external tree-sitter scanner; LSP code-action that
  rewrites positional ctor to brace-init.
* **R26A.2** -- highlight `..base` source identifier as `@variable`
  reference in tree-sitter (currently falls under generic identifier
  capture).
* **R26B.2** -- closed-on-tree-sitter side; R26D landed LSP
  completion.

### Sprint-wide

* **Round-by-round bench regression sweep cadence.** R26F was a
  one-off; the question is whether to schedule it every 4-6 rounds
  going forward. The bench harness from R25E plus a `bench/baseline.
  json` floor + the FASTER positive-signal convention is a working
  recipe.
* **Cross-repo dependency graph documentation.** The arc in section
  6 is implicit in commit graphs but not formally documented. A
  graph that names every NOVA syntax feature and the CrossEngin
  rounds that consume it would help future agents schedule.

---

## Appendix A -- commit SHAs at a glance

CrossEngin major commits referenced in section 1 (verified against
`git log` on branch `claude/festive-franklin-PP7mW`):

```
a4f3563  R26C  audio_noise_reduce.nova (Wiener)
f2b4fd4  R26E  gossip_relay.nova
7b17ad0  R26F  regression-hunt sweep
8c1c978  R25B  voice_conversation pipeline
ad55968  R25C  RSS / Atom ingestion
1bc3d6c  R25D  ARCHITECTURE.md refresh
a9ff3a8  R25E  unified bench harness + baseline.json
4e42dd6  R24C  image OCR via template matching
3ef2d12  R24F  video temporal smoothing (Kalman)
c665d53  R22F.2 harmonicity auto-switch (autocorr vs YIN)
c203dfb  R23E  NAT traversal
b5cbb9b  R23C  SNAP_FETCH/DATA/END wire
388e3a0  R23D  tracker tests + chat wiring
43a00f5  R23B  lip-sync detection
33b6e05  R22F  melody extraction
02be52e  R22D  panorama stitching
205000a  R22E  recursive provenance walks
a300c95  R22A  HOG detector amortization (2.15x)
b6d559a  R21E  Noise-XK transport
d752b9b  R21B  distributed rule inference
46af6ff  R21C  end-to-end TTS pipeline
34dd2e7  R21D  HOG integral histogram (0.25x single-call, honest)
1ec5280  R20F  gossip signed attestation
dafb7e5  R20C  cross-modal sensor fusion
5e63288  R20B  mini-Datalog inference
74170d0  R20E  distributed SPARQL
3d04a6a  R19E  Bully leader election
ee0f6fb  R18A.2 LK byte mul-acc wiring (3.69x)
e8172f1  R19D  speaker ID
29bb8ce  R19C  Allen interval algebra
79e8ed2  R18E  SWIM gossip
31e8ee3  R18C  wake-word DTW
1b53a2a  R18D  face recognition
9484073  R18B  link prediction
8002120  R17C  LK u8 SIMD honest disclosure (0.80x full LK)
2f08de3  R17D  LBP texture
42d3953  R17E  SPARQL aggregates
43be1bd  R17B  MFCC
ae6dc50  R16E  STFT / FFT
c895138  R16D  Haar cascade (structural)
95e83f4  R16F  SPARQL OPTIONAL/UNION/ORDER BY
64bb243  R16A  Ed25519 sign+verify snapshot root
994fc0b  R15E  Merkle snapshot chain
5c9af37  R15C  HOG sliding-window detector
a5005d6  R15D  mini-SPARQL
d224e9d  R15A  stereo SAD 5.5x (memcpy_raw load-bearing)
70408d6  R14E  Schroeder reverb + noise gate
2bb1533  R14D  HOG dense descriptor
9f1eb27  R14F  Ed25519 (RFC 8032)
6d05d01  R13B  full per-pixel pyramidal LK
942a1cd  R13D  voice cloning (Klatt formant transfer)
b1b662e  R13F  incremental delta-snapshots
0ee706b  R13E  PageRank
d474222  R12D  TD-PSOLA
ebccd92  R12A  honest perf observation doc
40f9a3a  R12B  SLIC superpixels (core)
b402762  R12A  stereo SAD SIMD (part 1)
dbd0121  R12A  LK accumulators SIMD (part 2)
14ae091  R11B  YIN F0 estimator
80f4741  R11F  label-propagation communities
a33a0db  R11A  pyramidal Lucas-Kanade
d028e78  R11E  k-means image segmentation
2432505  R10F  autocorrelation F0
bf7529b  R10C  TF-IDF semantic search
efbf346  R10B  whisper confidence + Vosk
577797c  R10D  Lucas-Kanade dense flow
68e8ec5  R9A   SGM stereo
5dfd35c  R9B   adaptive VAD
3be2b4a  R9F   Byzantine-resilient aggregation
0874516  R8B   whisper.cpp STT
b2d8c8f  R8D   stereo LR-check + sub-pixel
10705d1  R8F   episodic recall
8e71cbb  R8E   KG migration framework
c769f45  R7E   stereo block-matching
8af9f90  R7F   VAD on capture
aa32046  R7C   Noise XK 2048-bit DH
37cb8e1  R7B   DH-256 production migration
0e2700d  R6C   Noise XK handshake (kg_sync v3)
25c05d0  R6F   episodic consolidation
edf265b  R6B   Montgomery REDC (256-bit)
4b24224  R6D   ORB feature detector
1b97f7a  R6E   ARPAbet Klatt synthesis
40c3932  R4D   Montgomery REDC (2048-bit)
b0b2f8c  R5xx  SIFT detection (keypoint)
c798353  R5xx  SIFT 128-D descriptor + Lowe matcher
1cceec9  R5xx  Canny edge detection
90aa664  R5xx  pure-NOVA 256-bit bignum (P3.9)
671074f  R4    v1.0 unified single-process daemon
640cfcd  R3    phase9 IO + effectors
69dbd07  R3    phase8 safety + audit
4a2a674  R4    phase10 persistence
91139d3  R3    phase7 agent architecture
5228942  R3    phase6 reasoning + imagination
1678f08  R3    phase6 emotion
ab2a114  R3    phase6 soul
269023a  R2    phase5 confidence thresholds
0b2179e  R2    phase2 reader
b0ce961  R2    phase2 reader (rotated tag)
89af65b  R2    phase3 kg schemas
5356629  R2    phase3 atom store
64b0650  R1    phase1 kernel complete
2bfccb8  R1    phase1 node pool + dispatch
```

NOVA major commits referenced in section 6 (verified against
`git log` on the same branch):

```
1f398a8  R26A  struct update-syntax `Point { x: 10, ..p }`
916df6b  R26B  tree-sitter R25A brace-init + destructure
7932060  R26D  LSP brace-init field completion
7b74e7e  R25A  struct brace-init + destructure pattern
a39ba6a  R25D  ARCHITECTURE.md compiler + runtime
e2a87a9  R25F  LSP inline-variable refactor
72db976  R24B  tree-sitter R17A-R23A refresh
fda288c  R24A  fn-call + struct-ctor type-check
940c4f6  R24E  type-aware LSP completion
ef159ec  R23A  generic structs + type-check pass
bb61c6f  R23F  LSP workspace diagnostics
47769af  R22C  LSP folding ranges + document symbols
3fd1a6a  R22B  generic function signatures
ce4f878  R21F  LSP extract-function refactor
c7b6b33  R21A  generic enum payload types (Result<T, E>)
c49ebf8  R20A  Result + postfix ?
04f1378  R20D  LSP quickfix (auto-add match arms)
618635d  R19B  cross-target enum codegen
a32e95c  R19F  LSP type hierarchy
db34532  R18A  byte mul-acc SIMD
3a6e217  R18F  LSP code lens
41f0332  R17A  sum types + match exhaustiveness
38619aa  R17F  DAP instruction-level stepping
047ace1  R16B  match-as-expr block-body locals
c530629  R16C  LSP inlay hints
7e50f26  R15B  WASM v128 SIMD lowering
5a57beb  R15F  LSP call hierarchy
698f8e9  R14B  simd_sad_u8 raw-byte SAD primitive
3691954  R14A  DAP function breakpoints
11ae0d0  R13A  call-site inline SIMD + int_*
85fe64a  R13C  LSP semantic tokens
022586d  R12E  AST const-fold + DCE
2b58d5a  R10E  DAP evaluate + conditional breakpoints
844d54b  R11D  SIMD i32x8 intrinsics (AVX2 / NEON / scalar)
cf94264  R10A  packaging .deb + .pkg + .msi + Homebrew
16f029f         destructure / rest_pattern segfault fix
e52314f  R9C   LSP workspace rename
09d7299  R9C   tree-sitter folds + locals
7d9b3e6  R8A   WASI preopens / filesystem
c18a014  R8C   LSP workspace symbol
af94bd2  R7A   Windows ARM64 backend
17f176e  R7D   multi-thread DAP coordination
5362a37         PTR_THRESHOLD root fix
906fd14         secure_random CSPRNG (152nd builtin)
deac648         LSP textDocument/definition follows imports
```

---

## Appendix B -- pattern catalogue (the ten that paid off)

For the future-agent quickref, the ten engineering patterns that
have demonstrably paid off across this sprint:

1. **File-ownership scoping by src/ subtree** -- exclusive writes per
   agent per round; ~zero merge conflicts across 26 rounds.

2. **Labeled coordination blocks** in shared files
   (`src/federation/gossip.nova`'s GOSSIP_S_* slot reservations,
   `examples/crossengin_chat.nova`'s append-only dispatch table).

3. **WIP-commit-immediately** for long-running agents -- defends
   against harness work-tree resets.

4. **Stash labels** (`R<round><agent> stash: <reason>`) instead of
   bare `WIP on ...` for hand-offs.

5. **Honest perf disclosure in the commit subject** (HONEST,
   bit-identical, qualified-ratio markers) -- legible to all future
   reviewers and agents.

6. **Multi-round perf chains**: primitive → wired → inlined → realized
   spans 3-8 rounds; ship each link separately with a clear writeup
   of "what realized" or "what's left for the next round".

7. **Parser-only zero-cost** for language features -- NOVA's dynamic
   runtime absorbs new syntactic forms without runtime work, so
   R17A..R26A added 8 surface features with no perf regressions.

8. **Tooling-lags-by-one-round** rule -- tree-sitter / LSP / DAP
   updates serialize after the parser+codegen they refresh.

9. **Substrate-first** -- ship the wire / parser / codegen / tooling
   in strict order; never ship a wrapper before its primitive.

10. **Round-N.2 ledger** -- every honest disclosure ships a followup
    list that becomes the candidate set for a later round.

The combination is what made 156 parallel-agent dispatches across 26
rounds compose into a coherent, regression-free, perf-attributable
artifact.
