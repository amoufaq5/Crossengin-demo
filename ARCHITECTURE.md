# CrossEngin Architecture

This document is the layout-and-orientation guide for `Crossengin-demo`.
It is intentionally complementary to:

- `README.md` — the dense per-round narrative of what changed
- `NEXT_SESSION.md` — cumulative session notes for parallel agents
- `MANUAL.md` — the hands-on prerequisites + build + run walkthrough
- `docs/adr/` — the 50 architectural decision records

Where those documents tell you what was done and why a particular
decision was made, this document tells you **what lives where** so a
newcomer can find any module in seconds. After ~25 rounds of parallel
sprint development, CrossEngin contains ~190 NOVA modules organized
into 20 top-level subsystems. The catalog at the end of this document
gives the round in which each module was introduced, cross-referenced
to commit SHAs.

> Companion document: see [`/home/user/NOVA/ARCHITECTURE.md`](../NOVA/ARCHITECTURE.md)
> (or your local NOVA checkout) for the matching layout of the
> self-hosting NOVA compiler that builds this repository.

---

## 1. The 30-second view

CrossEngin is a **non-LLM cognitive substrate**. Its hypothesis is that
AGI-relevant capability — continuous learning, theory of mind,
counterfactual reasoning, long-horizon goals, self-awareness of identity
and state — emerges from a fabric of uniform computational units
(atoms, signals, synapses, KGs) rather than from sampling an LLM. The
substrate is implemented entirely in NOVA, a self-hosting compiled
language. Everything compiles to native x86-64 (and now arm64-linux,
macOS, win-x64, win-arm64, and WASM) with zero external runtime
dependencies.

```
                    ┌─────────────────────────────────────────────┐
                    │             Operator surfaces                │
                    │  scripts/web.py   bin/crossengin-chat REPL   │
                    │  scripts/learn.sh  /admin commands           │
                    └──────────────────┬──────────────────────────┘
                                       │
        ┌──────────────────────────────┴────────────────────────────┐
        │                       Unified daemon                       │
        │                  bin/crossengin (one process)              │
        │  drives the six-loop cycle: perception → reader → memory   │
        │  → reasoning → imagination → action  (ADR-0036/0037)       │
        └──────┬─────────┬──────────┬──────────┬──────────┬─────────┘
               │         │          │          │          │
               ▼         ▼          ▼          ▼          ▼
        ┌────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ ┌────────┐
        │PERCEPT │ │ READER  │ │   KGs   │ │REASONING│ │ ACTION │
        │ image  │ │ lexical │ │ atoms + │ │ proofs +│ │ output │
        │ audio  │ │ context │ │ synapses│ │ counter-│ │ + gate │
        │ video  │ │ neighb. │ │ episodic│ │ factual │ │ + TTS  │
        │ stream │ │ coherence│ │ semantic│ │ rule eng│ │        │
        └───┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────────┘
            │           │           │           │
            └───────────┴───────────┴───────────┘
                                │
                                ▼
                ┌──────────────────────────────┐
                │      Substrate kernel        │
                │ parts · gates · resonance ·  │
                │ signal_dispatch · synapse_   │
                │ graph · tick_driver          │
                └────────────┬─────────────────┘
                             │
                             ▼
                ┌──────────────────────────────┐
                │  Persistence + federation    │
                │  snapshot_disk · Merkle ·    │
                │  Ed25519 · gossip · SWIM ·   │
                │  Noise-XK · NAT traversal    │
                └──────────────────────────────┘
```

The shape is intentionally **not a pipeline**. Every box above is a
collection of NOVA modules that publishes signals into the same
substrate; the six-loop scheduler decides which subsystem ticks next
based on event arrival and idle-time triggers. There is no top-level
mediator deciding what to do — the loops are peers.

## 2. Top-level repository layout

```
Crossengin-demo/
├── ARCHITECTURE.md              ← this file
├── README.md                    ← dense per-round narrative
├── NEXT_SESSION.md              ← cumulative session notes (R1..R25)
├── MANUAL.md                    ← prerequisites + build + run walkthrough
├── Makefile                     ← `make build / test / chat / web / fed`
├── nova-deps.toml               ← NOVA enhancement assumptions
├── docs/
│   ├── adr/                     ← 50 architectural decision records
│   ├── design/                  ← longer-form design notes
│   └── runbook/                 ← build / test / run / ops runbooks
├── bin/                         ← compiled artifacts
│   ├── crossengin               ← unified single-process daemon (v1.0)
│   ├── crossengin-chat          ← stdin REPL with persistent state
│   ├── crossengin-spine         ← companion-spine demo
│   ├── crossengin-selfcheck     ← kernel selfcheck artifact
│   ├── crossengin-fed-*         ← federation coordinator/publisher/subscriber
│   ├── crossengin-kg-publisher  ← KG TCP pub/sub
│   └── crossengin-kg-subscriber
├── examples/                    ← entry-point NOVA programs (one per binary)
├── scripts/                     ← bash + python operator tools
├── src/                         ← all NOVA implementation
└── tests/
    ├── unit/                    ← per-module assertion tests
    ├── integration/             ← scenario_*.sh end-to-end flows
    └── benchmark/               ← perf benchmark fixtures
```

## 3. The `src/` tree

```
src/
├── substrate/      9 kernel modules (parts, gates, resonance, tick, ...)
├── parts/          subsystem bodies (action, emotion, episodic, goals, ...)
│   ├── action/
│   ├── emotion/        OCC appraisal, OCEAN personality conditioning
│   ├── episodic/       moments stream, episode storage, consolidation
│   ├── goals/          goal engine + drive generators + persistence
│   ├── imagination/    counterfactual, dream recombination, forward sim
│   ├── meta/           reflection, theory of mind, long-horizon goals
│   ├── perception/     part bodies (transducers live in src/io/)
│   ├── reasoning/      proof checker, reasoning atoms + module
│   └── soul/           identity, state, values, constitution, themes
├── reader/         lexical anchor + neighborhood + activation
├── kg/             19 KG modules — atoms, schemas, queries, analytics
├── safety/         crypto + DP + permission tiers + reversibility
├── persistence/    snapshot disk + Merkle + delta + compaction
├── learning/       federated, secure agg, byzantine-tolerant, fetch
├── federation/     SWIM gossip + leader + distributed query/rules + NAT
├── perception/     cross-modal fusion + lipsync
├── language/       phoneme / word / syntax atoms
├── seed/           first_atoms + 3 domain packs
├── session/        per-tenant state struct + registry
├── agent/          the eight loops (perception/reader/...)
├── audit/          decision log + audit writer/reader
├── scheduler/      hybrid event/idle pacer + tick loop
├── chat/           REPL helpers
├── io/
│   ├── transducers/   modality INPUT (image, audio, video, stream, http)
│   └── effectors/     modality OUTPUT (speak, synth, tts, voice clone)
└── gates/          (README-only; gate types live in substrate/)
```

## 4. Core substrate (`src/substrate/` + `src/parts/` + `src/scheduler/`)

The kernel is intentionally small. Nine modules in `src/substrate/`
define everything an atom is, everything a signal is, and the rules by
which signals propagate.

| Module | Role |
|---|---|
| `node_pool_manager.nova` | The atom-pool allocator. Hands out new atom IDs from a flat fixed-size pool; reuses freed IDs. |
| `part_registry.nova` | Maps a part name (e.g. `"emotion"`) to its body so the scheduler can wake it. |
| `part_lifecycle.nova` | Tick body driver — when a part is woken it runs its body once. |
| `first_nodes.nova` | The seed nodes the kernel always brings up at boot. |
| `signal_dispatch.nova` | The 18-signal taxonomy + the dispatch table that routes a signal to subscribed parts. |
| `synapse_graph.nova` | Sparse signed-weight graph between atoms. Reads cofire pairs; writes plasticity edits. |
| `gate_router.nova` | Decides which gate (perception, reasoning, action, ...) handles an inbound event. |
| `resonance_engine.nova` | Co-activation tracker; emits "atoms X and Y co-fire" events that drive plasticity. |
| `tick_driver.nova` | The wall-clock tick beat — drives `realtime_pacer` at the configured Hz. |

The **scheduler** is a hybrid: events arrive asynchronously (via
gossip, microphone capture, http webhook, etc.) and the
`hybrid_scheduler.nova` interleaves event-driven wakeups with the
`realtime_pacer.nova` 100Hz floor. The pacer also drives the idle
checkpoint that snapshots the substrate to disk (see persistence).

**Parts.** Each subsystem under `src/parts/` is a folder of body
modules that the kernel can wake. The folder structure was set by the
original 10-phase plan (Phase 1 substrate → Phase 10 persistence) and
has remained stable since. Inside a part folder the modules are roughly
"the thing it stores" (e.g. `episode_storage.nova`) plus "the thing it
does this tick" (e.g. `consolidation.nova`). The decision records under
`docs/adr/` map one-for-one onto these folders.

**Kernel-level decision records:**
- `docs/adr/0001-substrate-architecture.md` — the substrate hypothesis
- `docs/adr/0009-event-driven-substrate.md` — gate router rationale
- `docs/adr/0036-six-loop-cycle.md` — the six-loop architecture
- `docs/adr/0037-event-idle-scheduler.md` — the hybrid scheduler
- `docs/adr/0048-snapshot-format.md` — persistence on-disk layout

## 5. Knowledge graph and KG analytics (`src/kg/`)

The KG is the central long-term store. Every concept, fact, episodic
moment, source-authority record, drive, goal, and skill ends up as one
or more atoms in the KG with provenance, embedding, and confidence.

### 5.1 Foundational KG storage

| Module | Round | Role |
|---|---|---|
| `atom_store.nova` | Phase-3 | The atom CRUD primitives. Hash-indexed; O(1) lookup since P2.4. |
| `schemas.nova` | Phase-3 | Atom shape validation (CONCEPT vs FACT vs MOMENT vs ...). |
| `concept_layer.nova` | Phase-3 | Concept-hierarchy + property inheritance + multi-vector embed. |
| `cross_kg_references.nova` | Phase-3 | Cross-KG link primitive (`KG.atom_id -> KG.atom_id`). |
| `multi_kg_manager.nova` | Phase-3 | KG registry (one substrate can host many KGs). |
| `skills_kg.nova` | Phase-3 | Skill atoms — a specialized KG shape for competence tracking. |
| `competence_tracker.nova` | Phase-3 | Skill maturity over time (used by reasoning + goals). |
| `episodic.nova` | R6F | Episodic-memory consolidation cycle. The "moments → episodes" pipeline. |
| `ann_index.nova` | P3.4 | LSH approximate-nearest-neighbour index over atom embeddings. |

### 5.2 KG analytics modules

| Module | Round | Role |
|---|---|---|
| `query.nova` | R15D + R16F + R17E | Mini-SPARQL declarative query language (BGP, OPTIONAL, UNION, ORDER BY, COUNT/SUM/AVG/MIN/MAX, GROUP BY). |
| `semantic_search.nova` | R10C | TF-IDF semantic search across atom labels. |
| `graph_clustering.nova` | R11F | Label Propagation Algorithm (LPA) community detection. |
| `louvain.nova` | R12C | Louvain modularity-maximizing community detection. |
| `pagerank.nova` | R13E | PageRank centrality on the xref graph. |
| `link_prediction.nova` | R18B | Adamic-Adar + common-neighbours link prediction. |
| `temporal.nova` | R19C | Allen's 13-relation interval algebra for temporal reasoning. |
| `rule_inference.nova` | R20B | Forward-chaining mini-Datalog rule engine. |
| `rule_explain.nova` | R22E | Recursive proof-tree provenance walks over derived atoms. |

The analytics surface composes: `rule_inference` derives new atoms
from existing ones via rules; `rule_explain` then walks the proof tree
to surface *why* a derived atom exists; `query` can target the derived
set and aggregate over it; `pagerank` can rank the resulting atoms; and
`semantic_search` can soft-match a free-text query against the
resulting labels.

## 6. Perception subsystem

The substrate accepts five sensor modalities (image, audio, video,
text/stream, networked). All sensor adapters live in
`src/io/transducers/` (the INPUT half of the modality bridge). All
effectors live in `src/io/effectors/` (the OUTPUT half).

> Detailed module-by-module audits: see [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md)
> for the vision stack and [`AUDIO_AUDIT.md`](./AUDIO_AUDIT.md) for the
> audio stack. Each audit walks every public API, the constants, the
> implementation choice, and the unit-test coverage. This section is the
> index — the audits are the truth.

### 6.1 Vision (`image_*.nova`, `video_*.nova`, `visual_perception.nova`)

```
            ┌────────────────────────────────────────────┐
            │             image_pgm.nova                  │
            │       (raw bytes → grayscale pixels)        │
            └─────────────────┬──────────────────────────┘
                              │
            ┌─────────────────┴──────────────────────────┐
            │           Structural features              │
            │  sobel · harris · canny · motion vectors   │
            └─────────────────┬──────────────────────────┘
                              │
        ┌─────────────────────┼───────────────────────┐
        │                     │                       │
        ▼                     ▼                       ▼
   ┌─────────┐         ┌────────────┐          ┌──────────┐
   │ KEYPNT  │         │ TEXTURE +  │          │ MOTION   │
   │ SIFT    │         │ APPEARANCE │          │ optical  │
   │ ORB     │         │ LBP + HOG  │          │ flow LK  │
   └────┬────┘         └─────┬──────┘          │ stereo   │
        │                    │                 │ depth    │
        │                    │                 └────┬─────┘
        │                    │                      │
        └──────────┬─────────┴──────────────────────┘
                   │
                   ▼
        ┌────────────────────────────────┐
        │   visual_perception.nova        │
        │   (emit perception atoms)       │
        └──────────────┬──────────────────┘
                       │
                       ▼
        ┌────────────────────────────────┐
        │   KG / synapse / reader         │
        │   (the substrate sees)          │
        └────────────────────────────────┘
```

| Module | Round | Role |
|---|---|---|
| `image_pgm.nova` | P3.1 | Minimum-viable PGM decoder — the "give me grayscale pixels" leaf. |
| `png_decode.nova` | P3.1.PNG | PNG decoder + DEFLATE inflate (BTYPE=01/02; static + dynamic Huffman). |
| `jpeg_decode.nova` | P3.1.JPEG | JPEG entropy decode + 8×8 IDCT pipeline. |
| `deflate_decode.nova` | P3.1.PNG | Full DEFLATE — static + dynamic Huffman tables. |
| `video_y4m.nova` | P3.2 | Y4M decoder — the video modality input. |
| `video_perception.nova` | P3.2 | Frame-by-frame video perception seam (`/play`). |
| `video_motion_vectors.nova` | P3.3 | Motion-vector extraction. |
| `video_smooth.nova` | R24F | Kalman over R23D tracker outputs — temporal smoothing for jittery boxes. |
| `image_sobel.nova` | P3.3 | Sobel gradients (first structural feature). |
| `image_harris.nova` | P3.3 | Harris corner detection. |
| `image_canny.nova` | P3.3 | Canny edge detection. |
| `image_sift.nova` | P3.3 + R5C | SIFT scale-space + DoG extrema + 128-D descriptor + Lowe-ratio matcher. |
| `image_orb.nova` | P3.3 + R6D | ORB (Oriented FAST + Rotated BRIEF) + Hamming matcher. |
| `image_hog.nova` | R14D + R15C + R21D + R22A | HOG dense descriptor → sliding-window detector → integral-histogram accelerator (~2.15× absolute speedup vs naïve). |
| `image_lbp.nova` | R17D | Local Binary Patterns (Ojala 1996) texture descriptor. |
| `image_detector.nova` | R15C | Generic sliding-window object detector built on HOG. |
| `image_face_detect.nova` | R16D | Viola-Jones-style Haar cascade face detector. |
| `image_face_recognize.nova` | R18D | LBP-gallery face identity matching. |
| `image_stereo.nova` | R7E + R8D + R9A + R12A + R15A | Stereo depth — block-matching SAD → LR-check + sub-pixel parabolic → Semi-Global Matching 4-path → SIMD-accelerated (5.5× absolute). |
| `image_optical_flow.nova` | R10D + R11A + R13B + R12A + R17C + R18A.2 | Lucas-Kanade dense + pyramidal + full per-pixel + SIMD i32x8 + SIMD u8 SAD + byte mul-acc (3.69× absolute). |
| `image_segmentation.nova` | R11E | Spatial k-means image segmentation. |
| `image_superpixels.nova` | R12B | SLIC superpixel boundary-adherent segmentation. |
| `image_panorama.nova` | R22D | Panorama stitching — SIFT + ORB + RANSAC homography + warp + blend. |
| `image_tracker.nova` | R23D | Single-object online tracker (template match + median-flow). |
| `image_ocr.nova` | R24C | Character template matching OCR (per-glyph normalized cross-correlation). |
| `visual_perception.nova` | P3.1 | The perception seam — emits atoms from vision outputs. |

### 6.2 Audio (`audio_*.nova`)

```
                ┌────────────────────────────────────────┐
                │           audio_capture.nova            │
                │    (microphone → WAV → 16-bit PCM)      │
                └─────────────────┬──────────────────────┘
                                  │
                ┌─────────────────┴──────────────────────┐
                │             audio_vad.nova              │
                │  (voice activity detection, framing)    │
                └─────────────────┬──────────────────────┘
                                  │
        ┌─────────────────────────┼──────────────────────────┐
        │                         │                          │
        ▼                         ▼                          ▼
   ┌─────────┐             ┌────────────┐             ┌────────────┐
   │   STT   │             │  ANALYSIS  │             │  WAKEWORD  │
   │ Whisper │             │ pitch (AC, │             │   DTW on   │
   │  Vosk   │             │ YIN, auto) │             │   MFCC seq │
   └─────────┘             │ MFCC, STFT │             └────────────┘
                           │ DSP effects│
                           │ PSOLA      │
                           │ Speaker ID │
                           │ Melody     │
                           └────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────┐
                    │  audio_synth · audio_tts  │
                    │  audio_voice_clone        │
                    │  audio_speak (espeak +    │
                    │  ALSA/PA escalation)      │
                    └──────────────────────────┘
```

**Input (`src/io/transducers/audio_*.nova`):**

| Module | Round | Role |
|---|---|---|
| `audio_capture.nova` | P2.5 cont. | Microphone capture seam (fork/exec shell script, WAV-to-PCM parse). |
| `audio_vad.nova` | R7F + R9B | Voice activity detection + adaptive noise floor. |
| `stt_seam.nova` | P2.5 | Pluggable STT seam — backend resolves via `CE_STT_BACKEND`. |
| `whisper_backend.nova` | R8B + R10B | whisper.cpp backend wired into seam (per-utterance confidence). |
| `vosk_backend.nova` | R10B | Vosk offline backend with confidence. |
| `audio_pitch.nova` | R10F + R11B + R22F.2 | Autocorrelation F0 + YIN + harmonicity-driven auto-switch. |
| `audio_dsp.nova` | R14E | Classical DSP — Schroeder reverb + noise gate. |
| `audio_spectrogram.nova` | R16E | STFT / Cooley-Tukey FFT spectrogram. |
| `audio_mfcc.nova` | R17B | MFCC (Mel-Frequency Cepstral Coefficients) front-end. |
| `audio_wakeword.nova` | R18C | DTW on MFCC sequences. |
| `audio_psola.nova` | R12D | TD-PSOLA pitch shifting + time stretching. |
| `audio_speaker_id.nova` | R19D | MFCC gallery + DTW NN classifier. |
| `audio_melody.nova` | R22F | F0 contour → MIDI note sequence. |
| `stream_audio.nova` | P2.5 | Audio source streaming seam. |

**Output (`src/io/effectors/audio_*.nova`):**

| Module | Round | Role |
|---|---|---|
| `audio_synth.nova` | P19/P2.6 + R6E | Klatt-style two-formant phoneme synthesizer + 53-dispatch ARPAbet. |
| `audio_speak.nova` | P19 cont. | Three-mode escalation — pure-NOVA Klatt → espeak → ALSA/PA playback. |
| `audio_voice_clone.nova` | R13D | Voice cloning via Klatt formant transfer from a reference. |
| `audio_tts.nova` | R21C | End-to-end text-to-speech pipeline. |

> See [`AUDIO_AUDIT.md`](./AUDIO_AUDIT.md) for the full per-module
> audit. See [`STT_AUDIT.md`](./STT_AUDIT.md) for the STT seam.

### 6.3 Cross-modal (`src/perception/`)

| Module | Round | Role |
|---|---|---|
| `sensor_fusion.nova` | R20C | Image + audio coregistered observation primitive. The "what I saw AND what I heard at time T" atom. |
| `lipsync.nova` | R23B | Mouth-open (vision) ↔ voicing (audio) correlation. Detects mismatch (someone speaking off-screen, or moving lips silently). |

### 6.4 Other transducers (`src/io/transducers/`)

| Module | Round | Role |
|---|---|---|
| `input_transducer.nova` | Phase 9 | The generic input transducer seam. |
| `stream_stdin.nova` | P2.8 | Stdin pipe streaming source. |
| `stream_unix_socket.nova` | P2.8 | Unix-domain-socket streaming source. |
| `stream_http.nova` | P2.8 | HTTP webhook streaming source. |
| `http_client.nova` | P1.4 | Pure-NOVA HTTP/1.1 client + scheme-aware transport seam. |
| `secure_channel.nova` | P1.4 cont. | PSK secure channel via ChaCha20-Poly1305 over TCP. |
| `noise_xk.nova` | R6C + R7C + R21E | Noise XK mutual auth + transport encryption (2048-bit RFC 7919 DH; carrier for R18E gossip mesh). |
| `kg_sync.nova` | distributed + P1.3 | TCP atom-birth pub/sub between two daemons (v2: N-sub + bidir + reconnect + auth + conflict merge). |

### 6.5 Effectors (`src/io/effectors/`)

| Module | Round | Role |
|---|---|---|
| `output_generation.nova` | Phase 9 | The output-from-reasoning seam — reverse concept→word lookup so the daemon speaks what it concluded. |
| `effector_gate.nova` | Phase 9 | The safety check before any external side-effect (ADR-0040). |

## 7. Knowledge representation deeper dive (`src/reader/` + `src/language/`)

The reader is the five-stage hybrid pipeline that turns a raw input
phrase into KG activations:

```
  text ─► lexical_anchor ─► slot_index ─► neighborhood ─► coherence_check ─► reader
              │                │              │                  │              │
              ▼                ▼              ▼                  ▼              ▼
        word/phoneme/   syntax_atoms    co-fire index     belief floor    routed atoms
        syntax atom IDs                 (cofire_index)                    via gate_router
```

| Module | Round | Role |
|---|---|---|
| `lexical_anchor.nova` | Phase 2 | First-stage anchor — token → candidate atom IDs. |
| `slot_index.nova` | Phase 2 + R5B | Syntax-slot index — which atoms can occupy this grammatical slot. |
| `neighborhood.nova` | Phase 2 | Activation neighborhood — pull in atoms adjacent in the synapse graph. |
| `cofire_index.nova` | Phase 2 | Hebbian co-fire index — atoms that fired together recently. |
| `coherence_check.nova` | Phase 2 | Belief-floor coherence filter — drop atoms below the moment's confidence floor. |
| `context_bias.nova` | Phase 2 | Per-tenant context bias — soul personality + recency vector. |
| `spreading_activation.nova` | Phase 2 + R5C | Spreading-activation walk over the activation neighborhood. |
| `fetch_route_learn.nova` | Phase 2 | The reader → learning bridge (curiosity signal generation). |
| `reader.nova` | Phase 2 | The reader-pipeline entry point. |

**Language atoms (`src/language/`):** `phoneme_atoms.nova` +
`word_atoms.nova` + `syntax_atoms.nova` are the leaf bootstrap KGs
that the reader pulls from on first input.

## 8. Memory and learning

### 8.1 Episodic memory

| Module | Round | Role |
|---|---|---|
| `parts/episodic/moment_stream.nova` | Phase 4 | The append-only moment ring buffer. |
| `parts/episodic/episode_storage.nova` | Phase 4 | Episode-scale storage (a moment becomes an episode after consolidation). |
| `parts/episodic/consolidation.nova` | Phase 4 + R6F | The R6F consolidation cycle that promotes moments → episodes → KG atoms. |
| `parts/imagination/dream_recombination.nova` | Phase 6 | Dream-style recombination during idle periods. |

### 8.2 Federated + private learning (`src/learning/`)

| Module | Round | Role |
|---|---|---|
| `bayesian_updates.nova` | Phase 5 | Beta-distribution belief updates. |
| `plasticity_modulation.nova` | Phase 5 | Plasticity gain modulation (under emotion influence). |
| `predictive_coding_runtime.nova` | Phase 5 | Predictive-coding error signal generation. |
| `atom_birth_monitor.nova` | Phase 5 | Tracks newborn atoms (provenance metadata). |
| `atom_death_monitor.nova` | Phase 5 | Tracks atom decay/death (attribution by source). |
| `confidence_thresholds.nova` | Phase 5 | Floor thresholds for belief promotion. |
| `source_authority.nova` | Phase 5 | Per-source authority tracking (who told me this?). |
| `source_whitelist.nova` | Phase 5 | Whitelist of acceptable knowledge sources. |
| `self_learning_triggers.nova` | Phase 5 | The curiosity signal → learning loop trigger. |
| `ask_user_to_teach.nova` | Phase 5 | "Operator, please teach me X" loopback. |
| `internet_fetch.nova` | Phase 5 | Outbound URL/topic fetch (gated by source whitelist). |
| `federated_aggregator.nova` | P3.7 | Multi-soul federated aggregation framework. |
| `secure_aggregation.nova` | Implementation sprint R2 + P3.9 + P3.8r | SecAgg with 2048-bit DH + dropout resilience (`v2-sa-r`). |
| `byzantine_aggregation.nova` | R9F | Trimmed mean + coordinate-wise median for Byzantine resilience. |

> See [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md) and
> [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md) for the multi-soul federation
> and secure-aggregation deep-dives.

## 9. Federation (`src/federation/`)

```
                      ┌────────────────────────────────┐
                      │       SWIM gossip (R18E)         │
                      │   peer discovery + KG delta sync │
                      └──────────────┬─────────────────┘
                                     │
            ┌────────────────────────┼────────────────────────┐
            │                        │                        │
            ▼                        ▼                        ▼
  ┌──────────────────┐  ┌───────────────────────┐  ┌────────────────────┐
  │  leader_election │  │   distributed_query   │  │ distributed_rules  │
  │  Bully algo (R19E)│  │   SPARQL fan-out (R20E)│  │   Datalog (R21B)   │
  └──────────────────┘  └───────────────────────┘  └────────────────────┘
            │                        │                        │
            └────────────────────────┼────────────────────────┘
                                     │
                                     ▼
                      ┌────────────────────────────────┐
                      │ snapshot_attestation (R20F)    │
                      │ signed root → gossip relay     │
                      └──────────────┬─────────────────┘
                                     │
                                     ▼
                      ┌────────────────────────────────┐
                      │ snapshot_replication (R23C)    │
                      │ SNAP_FETCH / SNAP_DATA wire    │
                      └────────────────────────────────┘

                      ┌────────────────────────────────┐
                      │  nat_traversal (R23E)          │
                      │  STUN-like + gossip advertise  │
                      └────────────────────────────────┘
```

| Module | Round | Role |
|---|---|---|
| `gossip.nova` | R18E + R20F + R21E + R23C + R23E | SWIM-style gossip + signed-attestation relay + Noise-XK transport + SNAP_FETCH/DATA/END wire + NAT external-address advertise. |
| `leader_election.nova` | R19E | Bully-algorithm leader election over the gossip mesh. |
| `distributed_query.nova` | R20E | Distributed SPARQL via fan-out + scatter/gather over gossip. |
| `distributed_rules.nova` | R21B | Distributed mini-Datalog rule inference. |
| `snapshot_attestation.nova` | R20F | Gossip-relayed signed snapshot attestations ("at T I sealed root R"). |
| `snapshot_replication.nova` | R23C | The bytes-on-the-wire half — fetch + verify + serve replicas. |
| `nat_traversal.nova` | R23E | STUN-like external addr discovery + gossip-piggyback advertise. |

> The wire formats, scenario fixtures, and counter-examples are in
> [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md). Snapshot disk layout is in
> [`SNAPSHOT_FORMAT.md`](./SNAPSHOT_FORMAT.md).

## 10. Safety + crypto (`src/safety/`)

### 10.1 Crypto primitives

| Module | Round | Role |
|---|---|---|
| `bignum.nova` | P3.9 | 256-bit bignum library (add/sub/mul/mod-pow); the base of Curve25519/DH. |
| `bignum_256.nova` | R5A + R6B + R7B | 256-bit Montgomery REDC (~14× speedup over schoolbook); constant-time `bn256_modpow_ct`. |
| `bignum_2048.nova` | P3.9 cont. + R4D + R7C | 2048-bit bignum for RFC 7919 DH-Group-14; Montgomery REDC (~10× speedup). |
| `chacha20.nova` | P1.4 cont. | ChaCha20 stream cipher. |
| `poly1305.nova` | P1.4 cont. | Poly1305 MAC. |
| `ed25519.nova` | R14F | Ed25519 (RFC 8032) digital signatures + inline SHA-512. |
| `differential_privacy.nova` | P3.6 | Differential privacy at the KG-query surface. |
| `dp_budget_ui.nova` | R12F | `/dp` chat dispatch + status pane. |

> Per-primitive notes + test vectors are in [`TLS_AUDIT.md`](./TLS_AUDIT.md)
> (channel layer) and [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md) (DH).
> [`DP_AUDIT.md`](./DP_AUDIT.md) covers the differential-privacy surface.

### 10.2 Permission + reversibility

| Module | Role |
|---|---|
| `permission_tiers.nova` | Three tiers — observe, respond, full. Default deny. |
| `reversibility_classifier.nova` | Classifies a candidate effector action as reversible / irreversible. |
| `constitutional_filter.nova` | The constitution layer — applies the operator's encoded values before any irreversible action. |
| `override_mechanism.nova` | One-shot operator override (audit-trailed). |

## 11. Persistence (`src/persistence/`)

```
   in-RAM substrate
         │
         ▼
  snapshot_writer ──► snapshot_disk ──► write_tmp + fsync + rename (5355876)
         │                                  │
         │                                  ▼
         │                          v2 atomic file on disk
         │                                  ▲
         │                                  │
   snapshot_delta  ──────────────────────► incremental writes (R13F)
         │                                  │
         ▼                                  │
   merkle hash chain (R15E)                 │
         │                                  │
         ▼                                  │
   merkle_signing Ed25519 sign (R16A) ─────►│
                                            │
   schema_migration (R8E) ◄─────────────────┘
                                            │
                                            ▼
                                  snapshot_reader / snap_load
```

| Module | Round | Role |
|---|---|---|
| `snapshot_writer.nova` | Phase 10 | The top-level snapshot writer entrypoint. |
| `snapshot_reader.nova` | Phase 10 | The top-level snapshot reader / rehydrate entrypoint. |
| `snapshot_disk.nova` | settled disk seam | Realizes the `write_tmp → fsync → rename` atomic-replace on disk. |
| `snapshot_compaction.nova` | P2.10 | Snapshot compaction + `/compact` admin command. |
| `snapshot_delta.nova` | R13F | Incremental delta-snapshot writes. |
| `merkle.nova` | R15E | Merkle-tree tamper-evident atom-hash chain over snapshot bodies. |
| `merkle_signing.nova` | R16A | Ed25519 sign + verify of the Merkle root. |
| `schema_migration.nova` | R8E + P1.1 | KG atom schema-evolution / migration framework (v1 → v2 → ...). |

> The on-disk format, version tags, and migration history are documented
> in [`SNAPSHOT_FORMAT.md`](./SNAPSHOT_FORMAT.md).

## 12. The eight loops (`src/agent/`)

The R0 ten-phase plan posited six loops; the unified daemon (commit
`671074f`) wires eight:

| Loop | Module | Triggered by |
|---|---|---|
| Perception | `loop_perception.nova` | Inbound sensor signal |
| Reader | `loop_reasoning.nova` | (paired with reader stages) |
| Memory | `loop_memory.nova` | Idle window + consolidation tick |
| Coordination | `loop_coordination.nova` | Goal arbitration tick |
| Action | `loop_action.nova` | Outbound action proposal |
| Goals | `loop_goals.nova` | Drive generator tick |
| Imagination | `loop_imagination_idle.nova` | Idle-window trigger |
| Emotion | `loop_emotion.nova` | OCC appraisal trigger |

All eight publish into the same signal substrate and are scheduled by
the `hybrid_scheduler.nova` event/idle mix.

## 13. Soul, values, and constitution (`src/parts/soul/`)

The soul is first-class:

| Module | Role |
|---|---|
| `identity.nova` | Who this agent thinks it is. |
| `state.nova` | Current state vector — mood, drives, attention. |
| `values.nova` | Persistent value weights (used by goal arbitration). |
| `themes.nova` | Long-horizon themes the agent is working on. |
| `loyalty.nova` | Per-counterparty loyalty / trust vector. |
| `goals_in_soul.nova` | The soul's pinned long-horizon goals. |
| `constitution.nova` | The encoded behavioural constraint layer. |

## 14. Reasoning + imagination (`src/parts/reasoning/` + `src/parts/imagination/`)

| Module | Role |
|---|---|
| `parts/reasoning/reasoning_atoms.nova` | The reasoning operator vocabulary (`is_a`, `causal`, `has`, ...). |
| `parts/reasoning/reasoning_module.nova` | The reasoning loop body. |
| `parts/reasoning/proof_checker.nova` | A real proof checker (`/prove` admin command, P3.5). |
| `parts/imagination/imagination_engine.nova` | The imagination loop body. |
| `parts/imagination/forward_sim.nova` | Forward simulation — consequence prediction. |
| `parts/imagination/counterfactual.nova` | Counterfactual reasoning (what if X had happened?). |
| `parts/imagination/scenario_planner.nova` | Scenario planning over a goal. |
| `parts/imagination/dream_recombination.nova` | Idle-window dream recombination. |

## 15. Goals, drives, and meta-cognition (`src/parts/goals/` + `src/parts/meta/`)

| Module | Role |
|---|---|
| `parts/goals/goal_engine.nova` | Priority-sorted goal store; hierarchical subgoals. |
| `parts/goals/drive_generators.nova` | Curiosity / social / task / homeostasis drives. |
| `parts/goals/goal_persistence.nova` | Goal serialization in snapshots. |
| `parts/meta/meta_observer.nova` | The meta-observer — sees the system seeing. |
| `parts/meta/reflection_loop.nova` | The reflection loop body. |
| `parts/meta/long_horizon_goals.nova` | Long-horizon goal management. |
| `parts/meta/self_model_query.nova` | "What do I know about myself?" surface. |
| `parts/meta/theory_of_mind.nova` | Modelling the operator / other agents. |

## 16. Emotion (`src/parts/emotion/`)

| Module | Role |
|---|---|
| `parts/emotion/appraisal.nova` | OCC (Ortony-Clore-Collins) appraisal model. |
| `parts/emotion/ocean_conditioning.nova` | OCEAN personality conditioning of emotion weights. |
| `parts/emotion/plasticity_mod.nova` | Emotion → plasticity modulation pathway. |

## 17. Seed (`src/seed/`)

| Module | Role |
|---|---|
| `first_atoms.nova` | The 572-concept + ~40-operator + ~12-imagination-pattern + 6-syntax-pattern boot KG. |
| `pack_registry.nova` | The seed-pack registry — domain packs override defaults. |
| `packs/code_review_pack.nova` | Code-review-specific seed pack. |
| `packs/medical_pack.nova` | Medical-domain seed pack. |
| `packs/ops_runbook_pack.nova` | Ops-runbook-domain seed pack. |

## 18. Session, chat, audit, scheduler, gates

These are smaller subsystems that glue the substrate together.

| Module | Role |
|---|---|
| `session/session.nova` | Per-tenant state struct + registry. |
| `chat/helpers.nova` | REPL helpers shared between `crossengin-chat` and the web frontend. |
| `audit/decision_log.nova` | Durable decision log (Phase 8). |
| `audit/audit_reader.nova` | Replay-friendly audit reader. |
| `audit/audit_writer.nova` | Audit-writer side of the seam. |
| `scheduler/hybrid_scheduler.nova` | The hybrid event-idle scheduler. |
| `scheduler/realtime_pacer.nova` | The 100Hz wall-clock pacer. |
| `scheduler/tick_loop.nova` | The kernel tick loop. |
| `scheduler/event_dispatch.nova` | The event dispatch table. |
| `gates/` | (README-only directory — gate primitives live in substrate/) |

## 19. Operator surfaces and entry-point binaries

| Binary | Source | Role |
|---|---|---|
| `bin/crossengin` | `examples/crossengin_daemon.nova` | The unified single-process daemon (v1.0). |
| `bin/crossengin-chat` | `examples/crossengin_chat.nova` | Stdin REPL with persistent agent state across turns. |
| `bin/crossengin-spine` | `examples/companion_spine.nova` | Companion-spine demo (skeleton agent). |
| `bin/crossengin-selfcheck` | `examples/kernel_selfcheck.nova` | Kernel self-check (boot, 18-signal dispatch, ...). |
| `bin/crossengin-fed-coordinator` | `examples/crossengin_fed_coordinator.nova` | Federation coordinator entry point. |
| `bin/crossengin-kg-publisher` | `examples/crossengin_kg_publisher.nova` | TCP KG-atom publisher. |
| `bin/crossengin-kg-subscriber` | `examples/crossengin_kg_subscriber.nova` | TCP KG-atom subscriber. |
| `scripts/web.py` | n/a (Python) | Browser frontend — talks to a persistent `bin/crossengin-chat`. |
| `scripts/chat.sh` | n/a | Chat-mode daemon shim. |
| `scripts/learn.sh` | n/a | `/learn <topic>` autonomous-ingestion shim. |

## 20. Cross-reference: NOVA primitives that CrossEngin depends on

CrossEngin is the **first non-trivial NOVA consumer**. Every round
that adds a new CE capability often co-opts a NOVA feature shipped in
the same or a nearby NOVA round. See `nova-deps.toml` for the formal
list. A quick spot-check:

| CE module | NOVA feature it relies on | NOVA round |
|---|---|---|
| `safety/ed25519.nova` | NOVA's inline SHA-512 + bignum ops | R14F (NOVA side) |
| `io/transducers/image_optical_flow.nova` | SIMD i32x8 intrinsics | R11D, R14B, R18A |
| `io/transducers/image_stereo.nova` | SIMD u8 SAD primitive | R14B + R15A |
| `io/transducers/image_hog.nova` | Byte mul-acc SIMD | R18A + R22A |
| `kg/query.nova` | NOVA sum types + match exhaustiveness | R17A |
| `kg/rule_inference.nova` | Result + postfix `?` operator | R20A |
| `federation/gossip.nova` | NOVA generic enum payloads (`Result<T, E>`) | R21A |
| `learning/secure_aggregation.nova` | 2048-bit bignum + Montgomery REDC | R4D + R7B (NOVA side) |
| any module with rich types | Generic structs + lightweight type-check | R23A + R24A |

> The matching NOVA architecture document is
> [`/home/user/NOVA/ARCHITECTURE.md`](../NOVA/ARCHITECTURE.md).
> Cross-references between this document and NOVA's are intentional and
> two-way — a NOVA feature gap closes a CE roadmap item, and vice versa.

## 21. Audit documents (deep-dives)

This document is the **index**. The deep-dives are:

| Audit doc | Scope |
|---|---|
| [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md) | Every `image_*.nova` + `video_*.nova` — API, constants, test coverage. |
| [`AUDIO_AUDIT.md`](./AUDIO_AUDIT.md) | Every `audio_*.nova` — synth, capture, VAD, STT, pitch, MFCC, ... |
| [`STT_AUDIT.md`](./STT_AUDIT.md) | STT seam — whisper + Vosk backends. |
| [`JPEG_AUDIT.md`](./JPEG_AUDIT.md) | JPEG decoder internals (P3.1.JPEG). |
| [`VIDEO_AUDIT.md`](./VIDEO_AUDIT.md) | Video stack (Y4M decoder + perception seam). |
| [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md) | Gossip + leader + distributed query/rules + NAT + attestation + replication. |
| [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md) | Secure-aggregation protocol (DH + dropout resilience). |
| [`DP_AUDIT.md`](./DP_AUDIT.md) | Differential-privacy surface at the KG. |
| [`TLS_AUDIT.md`](./TLS_AUDIT.md) | PSK channel + Noise XK. |
| [`SNAPSHOT_FORMAT.md`](./SNAPSHOT_FORMAT.md) | On-disk snapshot format + version history. |

---

## 22. Full module catalog

> Path is relative to repository root.
> "Round" is the round (or P-phase) the module was first introduced.
> Commit SHA is the short hash of the introducing commit (verifiable via
> `git log --diff-filter=A -- <path>`).

### 22.1 Substrate kernel

| File | Round | SHA |
|---|---|---|
| `src/substrate/first_nodes.nova` | Phase 1 | 64b0650 |
| `src/substrate/gate_router.nova` | Phase 1 | 64b0650 |
| `src/substrate/node_pool_manager.nova` | Phase 1 | 2bbccb8 |
| `src/substrate/part_lifecycle.nova` | Phase 1 | 64b0650 |
| `src/substrate/part_registry.nova` | Phase 1 | 64b0650 |
| `src/substrate/resonance_engine.nova` | Phase 1 | 64b0650 |
| `src/substrate/signal_dispatch.nova` | Phase 1 | 2bbccb8 |
| `src/substrate/synapse_graph.nova` | Phase 1 + R6F | 2bbccb8 |
| `src/substrate/tick_driver.nova` | Phase 1 | 64b0650 |

### 22.2 Scheduler

| File | Round | SHA |
|---|---|---|
| `src/scheduler/event_dispatch.nova` | Phase 7 | 91139d3 |
| `src/scheduler/hybrid_scheduler.nova` | Phase 7 + R5B | 4220a1f |
| `src/scheduler/realtime_pacer.nova` | Phase 7 | bf7ffc7 |
| `src/scheduler/tick_loop.nova` | Phase 7 | 91139d3 |

### 22.3 Knowledge graph

| File | Round | SHA |
|---|---|---|
| `src/kg/atom_store.nova` | Phase 3 | 5356629 |
| `src/kg/multi_kg_manager.nova` | Phase 3 | 5356629 |
| `src/kg/cross_kg_references.nova` | Phase 3 | 5356629 |
| `src/kg/schemas.nova` | Phase 3 | b89af65b |
| `src/kg/concept_layer.nova` | Phase 3 | b89af65b |
| `src/kg/skills_kg.nova` | Phase 3 | 89af65b |
| `src/kg/competence_tracker.nova` | Phase 3 | 89af65b |
| `src/kg/episodic.nova` | R6F | 25c05d0 |
| `src/kg/ann_index.nova` | P3.4 | b6a4c8e |
| `src/kg/semantic_search.nova` | R10C | bf7529b |
| `src/kg/graph_clustering.nova` | R11F | 80f4741 |
| `src/kg/louvain.nova` | R12C | 09d5a3d |
| `src/kg/pagerank.nova` | R13E | 0ee706b |
| `src/kg/query.nova` | R15D + R16F + R17E | a5005d6 |
| `src/kg/link_prediction.nova` | R18B | 9484073 |
| `src/kg/temporal.nova` | R19C | 29bb8ce |
| `src/kg/rule_inference.nova` | R20B | 5e63288 |
| `src/kg/rule_explain.nova` | R22E | 205000a |

### 22.4 Vision transducers

| File | Round | SHA |
|---|---|---|
| `src/io/transducers/visual_perception.nova` | P3.1 | a9db6f4 |
| `src/io/transducers/image_pgm.nova` | P3.1 | a9db6f4 |
| `src/io/transducers/png_decode.nova` | P3.1.PNG | e88b9f4 |
| `src/io/transducers/deflate_decode.nova` | P3.1.PNG | e88b9f4 |
| `src/io/transducers/jpeg_decode.nova` | P3.1.JPEG | 688182e |
| `src/io/transducers/video_y4m.nova` | P3.2 | 2ed1e59 |
| `src/io/transducers/video_perception.nova` | P3.2 | 2ed1e59 |
| `src/io/transducers/video_motion_vectors.nova` | P3.3 | 7d7d4a4 |
| `src/io/transducers/video_smooth.nova` | R24F | 3ef2d12 |
| `src/io/transducers/image_sobel.nova` | P3.3 | 7d7d4a4 |
| `src/io/transducers/image_harris.nova` | P3.3 | 7d7d4a4 |
| `src/io/transducers/image_canny.nova` | P3.3 cont. | 1cceec9 |
| `src/io/transducers/image_sift.nova` | P3.3 + R5C | b0b2f8c |
| `src/io/transducers/image_orb.nova` | R6D | 4b24224 |
| `src/io/transducers/image_hog.nova` | R14D + R15C + R21D + R22A | 2bb1533 |
| `src/io/transducers/image_detector.nova` | R15C | 5c9af37 |
| `src/io/transducers/image_lbp.nova` | R17D | 2f08de3 |
| `src/io/transducers/image_face_detect.nova` | R16D | c895138 |
| `src/io/transducers/image_face_recognize.nova` | R18D | 1b53a2a |
| `src/io/transducers/image_optical_flow.nova` | R10D + R11A + R13B | 577797c |
| `src/io/transducers/image_stereo.nova` | R7E + R8D + R9A + R12A + R15A | c769f45 |
| `src/io/transducers/image_segmentation.nova` | R11E | d028e78 |
| `src/io/transducers/image_superpixels.nova` | R12B | 40f9a3a |
| `src/io/transducers/image_panorama.nova` | R22D | 02be52e |
| `src/io/transducers/image_tracker.nova` | R23D | c3aec20 |
| `src/io/transducers/image_ocr.nova` | R24C | 4e42dd6 |

### 22.5 Audio transducers

| File | Round | SHA |
|---|---|---|
| `src/io/transducers/stream_audio.nova` | P2.5 | 882a15c |
| `src/io/transducers/stt_seam.nova` | P2.5 | 882a15c |
| `src/io/transducers/audio_capture.nova` | P2.5 cont. | e7499f9 |
| `src/io/transducers/whisper_backend.nova` | R8B | 0874516 |
| `src/io/transducers/vosk_backend.nova` | R10B | efbf346 |
| `src/io/transducers/audio_vad.nova` | R7F + R9B | 8af9f90 |
| `src/io/transducers/audio_pitch.nova` | R10F + R11B + R22F.2 | 2432505 |
| `src/io/transducers/audio_psola.nova` | R12D | d474222 |
| `src/io/transducers/audio_dsp.nova` | R14E | 70408d6 |
| `src/io/transducers/audio_spectrogram.nova` | R16E | ae6dc50 |
| `src/io/transducers/audio_mfcc.nova` | R17B | 43be1bd |
| `src/io/transducers/audio_wakeword.nova` | R18C | 31e8ee3 |
| `src/io/transducers/audio_speaker_id.nova` | R19D | e8172f1 |
| `src/io/transducers/audio_melody.nova` | R22F | 33b6e05 |

### 22.6 Audio effectors

| File | Round | SHA |
|---|---|---|
| `src/io/effectors/audio_synth.nova` | P19/P2.6 + R6E | 4af5735 |
| `src/io/effectors/audio_speak.nova` | P19 cont. | 4af5735 |
| `src/io/effectors/audio_voice_clone.nova` | R13D | 942a1cd |
| `src/io/effectors/audio_tts.nova` | R21C | 46af6ff |
| `src/io/effectors/output_generation.nova` | Phase 9 | 640cfcd |
| `src/io/effectors/effector_gate.nova` | Phase 9 | 640cfcd |

### 22.7 Network and streaming

| File | Round | SHA |
|---|---|---|
| `src/io/transducers/input_transducer.nova` | Phase 9 | 640cfcd |
| `src/io/transducers/stream_stdin.nova` | P2.8 | 832151f |
| `src/io/transducers/stream_unix_socket.nova` | P2.8 | 832151f |
| `src/io/transducers/stream_http.nova` | P2.8 | 832151f |
| `src/io/transducers/http_client.nova` | P1.4 | 9fa279c |
| `src/io/transducers/secure_channel.nova` | P1.4 cont. | 0e6ba0d |
| `src/io/transducers/noise_xk.nova` | R6C + R7C + R21E | 0e2700d |
| `src/io/transducers/kg_sync.nova` | distributed + P1.3 | 0f22397 |

### 22.8 Cross-modal perception

| File | Round | SHA |
|---|---|---|
| `src/perception/sensor_fusion.nova` | R20C | dafb7e5 |
| `src/perception/lipsync.nova` | R23B | 43a00f5 |

### 22.9 Federation

| File | Round | SHA |
|---|---|---|
| `src/federation/gossip.nova` | R18E + R20F + R21E + R23C + R23E | 79e8ed2 |
| `src/federation/leader_election.nova` | R19E | 3d04a6a |
| `src/federation/distributed_query.nova` | R20E | 74170d0 |
| `src/federation/distributed_rules.nova` | R21B | d752b9b |
| `src/federation/snapshot_attestation.nova` | R20F | 1ec5280 |
| `src/federation/snapshot_replication.nova` | R23C | 3c21995 |
| `src/federation/nat_traversal.nova` | R23E | a914dd9 |

### 22.10 Safety + crypto

| File | Round | SHA |
|---|---|---|
| `src/safety/bignum.nova` | P3.9 | 90aa664 |
| `src/safety/bignum_256.nova` | R5A + R6B + R7B | edf265b |
| `src/safety/bignum_2048.nova` | P3.9 cont. + R4D | 224bef6 |
| `src/safety/chacha20.nova` | P1.4 cont. | 0e6ba0d |
| `src/safety/poly1305.nova` | P1.4 cont. | 0e6ba0d |
| `src/safety/ed25519.nova` | R14F | 9f1eb27 |
| `src/safety/differential_privacy.nova` | P3.6 | a0b69ee |
| `src/safety/dp_budget_ui.nova` | R12F | 81dd67f |
| `src/safety/permission_tiers.nova` | Phase 8 | 69dbd07 |
| `src/safety/reversibility_classifier.nova` | Phase 8 | 69dbd07 |
| `src/safety/constitutional_filter.nova` | Phase 8 | 69dbd07 |
| `src/safety/override_mechanism.nova` | Phase 8 | 69dbd07 |

### 22.11 Persistence

| File | Round | SHA |
|---|---|---|
| `src/persistence/snapshot_writer.nova` | Phase 10 | 4a2a674 |
| `src/persistence/snapshot_reader.nova` | Phase 10 | 4a2a674 |
| `src/persistence/snapshot_disk.nova` | settled | 5355876 |
| `src/persistence/snapshot_compaction.nova` | P2.10 | 3f3c8ea |
| `src/persistence/snapshot_delta.nova` | R13F | b1b662e |
| `src/persistence/merkle.nova` | R15E | 994fc0b |
| `src/persistence/merkle_signing.nova` | R16A | 64bb243 |
| `src/persistence/schema_migration.nova` | R8E + P1.1 | 8e71cbb |

### 22.12 Learning + federated learning

| File | Round | SHA |
|---|---|---|
| `src/learning/atom_birth_monitor.nova` | Phase 5 | cc970dd |
| `src/learning/atom_death_monitor.nova` | Phase 5 | cc970dd |
| `src/learning/bayesian_updates.nova` | Phase 5 | 23e9389 |
| `src/learning/plasticity_modulation.nova` | Phase 5 | cc970dd |
| `src/learning/predictive_coding_runtime.nova` | Phase 5 | cc970dd |
| `src/learning/confidence_thresholds.nova` | Phase 5 | 23e9389 |
| `src/learning/source_authority.nova` | Phase 5 | 23e9389 |
| `src/learning/source_whitelist.nova` | Phase 5 | 23e9389 |
| `src/learning/self_learning_triggers.nova` | Phase 5 | cc970dd |
| `src/learning/ask_user_to_teach.nova` | Phase 5 | cc970dd |
| `src/learning/internet_fetch.nova` | Phase 5 | cc970dd |
| `src/learning/federated_aggregator.nova` | P3.7 | 9f16f5a |
| `src/learning/secure_aggregation.nova` | implementation sprint R2 + P3.9 + P3.8r | e88b9f4 |
| `src/learning/byzantine_aggregation.nova` | R9F | 3be2b4a |

### 22.13 Reader + language atoms

| File | Round | SHA |
|---|---|---|
| `src/reader/reader.nova` | Phase 2 | 0b2179e |
| `src/reader/lexical_anchor.nova` | Phase 2 | 0b2179e |
| `src/reader/slot_index.nova` | Phase 2 | 0b2179e |
| `src/reader/neighborhood.nova` | Phase 2 | 0b2179e |
| `src/reader/coherence_check.nova` | Phase 2 | 0b2179e |
| `src/reader/context_bias.nova` | Phase 2 | 0b2179e |
| `src/reader/cofire_index.nova` | Phase 2 | 0b2179e |
| `src/reader/spreading_activation.nova` | Phase 2 | 0b2179e |
| `src/reader/fetch_route_learn.nova` | Phase 2 | 0b2179e |
| `src/language/phoneme_atoms.nova` | Phase 2 | b0ce961 |
| `src/language/syntax_atoms.nova` | Phase 2 | b0ce961 |
| `src/language/word_atoms.nova` | Phase 2 | b0ce961 |

### 22.14 Parts (subsystem bodies)

| File | Round | SHA |
|---|---|---|
| `src/parts/episodic/moment_stream.nova` | Phase 4 | 2b1e81b |
| `src/parts/episodic/episode_storage.nova` | Phase 4 | 2b1e81b |
| `src/parts/episodic/consolidation.nova` | Phase 4 | 269023a |
| `src/parts/goals/goal_engine.nova` | Phase 6 | 79c303f |
| `src/parts/goals/drive_generators.nova` | Phase 6 | 79c303f |
| `src/parts/goals/goal_persistence.nova` | Phase 6 | 79c303f |
| `src/parts/imagination/imagination_engine.nova` | Phase 6 | 5228942 |
| `src/parts/imagination/forward_sim.nova` | Phase 6 | 5228942 |
| `src/parts/imagination/counterfactual.nova` | Phase 6 | 5228942 |
| `src/parts/imagination/scenario_planner.nova` | Phase 6 | 5228942 |
| `src/parts/imagination/dream_recombination.nova` | Phase 6 | 5228942 |
| `src/parts/reasoning/reasoning_atoms.nova` | Phase 6 | 5228942 |
| `src/parts/reasoning/reasoning_module.nova` | Phase 6 | 5228942 |
| `src/parts/reasoning/proof_checker.nova` | P3.5 | ada3596 |
| `src/parts/emotion/appraisal.nova` | Phase 6 | 1678f08 |
| `src/parts/emotion/ocean_conditioning.nova` | Phase 6 | 1678f08 |
| `src/parts/emotion/plasticity_mod.nova` | Phase 6 | 1678f08 |
| `src/parts/soul/identity.nova` | Phase 6 | ab2a114 |
| `src/parts/soul/state.nova` | Phase 6 | ab2a114 |
| `src/parts/soul/values.nova` | Phase 6 | ab2a114 |
| `src/parts/soul/constitution.nova` | Phase 6 | ab2a114 |
| `src/parts/soul/themes.nova` | Phase 6 | ab2a114 |
| `src/parts/soul/loyalty.nova` | Phase 6 | ab2a114 |
| `src/parts/soul/goals_in_soul.nova` | Phase 6 | ab2a114 |
| `src/parts/meta/meta_observer.nova` | Phase 6 + da2dd84 | 91139d3 |
| `src/parts/meta/reflection_loop.nova` | reflection round | 9c897d5 |
| `src/parts/meta/long_horizon_goals.nova` | Phase 7 | 91139d3 |
| `src/parts/meta/self_model_query.nova` | Phase 7 | 91139d3 |
| `src/parts/meta/theory_of_mind.nova` | Phase 7 | 91139d3 |

### 22.15 Agent loops

| File | Round | SHA |
|---|---|---|
| `src/agent/loop_action.nova` | Phase 7 | 91139d3 |
| `src/agent/loop_coordination.nova` | Phase 7 | 91139d3 |
| `src/agent/loop_emotion.nova` | Phase 7 | 91139d3 |
| `src/agent/loop_goals.nova` | Phase 7 | 91139d3 |
| `src/agent/loop_imagination_idle.nova` | Phase 7 | 91139d3 |
| `src/agent/loop_memory.nova` | Phase 7 + R6F | 91139d3 |
| `src/agent/loop_perception.nova` | Phase 7 | 91139d3 |
| `src/agent/loop_reasoning.nova` | Phase 7 | 91139d3 |

### 22.16 Audit + session + chat

| File | Round | SHA |
|---|---|---|
| `src/audit/audit_reader.nova` | Phase 8 | 69dbd07 |
| `src/audit/audit_writer.nova` | Phase 8 | 69dbd07 |
| `src/audit/decision_log.nova` | Phase 8 + bf7ffc7 | 69dbd07 |
| `src/session/session.nova` | session round | 5191dcf |
| `src/chat/helpers.nova` | P1 round 2 | 92fc794 |

### 22.17 Seed

| File | Round | SHA |
|---|---|---|
| `src/seed/first_atoms.nova` | seed round | 816169d |
| `src/seed/pack_registry.nova` | P1 round 2 | 92fc794 |
| `src/seed/packs/code_review_pack.nova` | P1 round 2 | 92fc794 |
| `src/seed/packs/medical_pack.nova` | P1 round 2 | 92fc794 |
| `src/seed/packs/ops_runbook_pack.nova` | P1 round 2 | 92fc794 |

---

## 23. How to navigate this codebase

A few rules of thumb that have proven useful through 25 rounds:

1. **Start at the audit document, not the module.** Each `*_AUDIT.md`
   in this directory walks every public API for its subsystem with the
   "why" attached. Skipping straight to the `.nova` file is almost
   always slower than reading the matching audit first.
2. **A module's first round and its current round are different.**
   The catalog above pins the first round it appeared. Major
   capabilities like `image_optical_flow.nova` (R10D / R11A / R13B /
   R12A / R17C / R18A.2) have been extended across many rounds. The
   audit doc tracks the per-round delta.
3. **Test fixtures live in `tests/unit/` per module, and
   `tests/integration/scenario_*.sh` per end-to-end behaviour.** The
   integration scenarios are alphabetically named (`scenario_a.sh`
   through `scenario_mmmm.sh`); the README narrative for each round
   notes which scenario letter that round added.
4. **The README is the source of truth for "what is shipped right
   now".** ARCHITECTURE.md is the source of truth for "how are the
   pieces wired together".
5. **All persistence is one snapshot file.** When you read about a
   delta write, a Merkle root, a signed attestation, or a replicated
   fetch, they all converge on the same `snapshot.bin` on disk.
6. **The 18-signal dispatch table is the wire format between every
   subsystem.** See `src/substrate/signal_dispatch.nova` for the
   authoritative list.

## 24. Round-to-feature index (R1 ... R24)

Rough chronological summary of what each round shipped. Use this as a
"why does this commit exist" reference; the README is the verbose
version.

```
P0      ADRs + scaffold + 50 substrate ADRs + 10-phase plan
P1-10   The 10-phase build: substrate → language → KG → episodic →
        learning → reasoning/imagination/goals/emotion/soul → agent
        loops → safety/audit → IO/effectors → persistence
P1.x    Round 2: chat REPL, web frontend, learn shim, daemon
        unification (v1.0)
P2.x    Audio modality input/output, streaming sources, snapshot
        compaction, hash-indexed atom lookup, metrics, persistence-by-
        delta scaffolding
P3.x    Image modality (PGM/PNG/JPEG), video (Y4M), structural
        features (Sobel/Harris/Canny), STT framework, secure
        aggregation, differential privacy
R4-R6   First crypto wave (DH, bignums, Montgomery REDC, Noise XK,
        ChaCha20-Poly1305, ORB, SIFT descriptor)
R7-R10  Stereo depth, VAD, optical flow, autocorrelation pitch,
        whisper STT, episodic recall, semantic search, byzantine
        aggregation, FRDM enhancements
R11-R13 LK pyramidal flow, YIN pitch, SIMD wave (i32x8 + u8 SAD +
        byte mul-acc), Louvain clustering, PageRank, PSOLA, voice
        clone, snapshot delta, full per-pixel LK
R14-R16 HOG dense + sliding window, LK-SIMD wiring, DSP effects,
        Ed25519, mini-SPARQL, Merkle chain, signed Merkle root,
        STFT, Haar face detect
R17-R19 NOVA enums (R17A), MFCC, LBP, byte mul-acc SIMD, link
        prediction, gossip mesh, face recognize, wakeword,
        speaker ID, temporal Allen algebra, Bully leader
R20-R22 Sum types + ?-op, rule inference (Datalog), sensor fusion,
        distributed SPARQL/rules, attestation, Noise-XK for
        gossip, HOG accelerator, TTS, panorama, melody, rule
        explain, sliding-window detect
R23-R24 Generic structs (R23A), workspace diagnostics, snapshot
        replication, lipsync, NAT traversal, image tracker,
        fn-call type-check (R24A), OCR, video smooth
```

---

This document is intentionally a long index. The audits go deeper;
the README narrates per-round; the ADRs justify decisions. Together
they cover the whole substrate.
