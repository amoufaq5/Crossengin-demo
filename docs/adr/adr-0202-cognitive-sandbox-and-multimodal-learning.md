# ADR-0202: Cognitive Sandbox and Multimodal Learning

## Status

Proposed. Names the COGNITIVE sandbox as a first-class runtime
concept, distinct from the ACCESS-CONTROL sandbox specified in
ADR-0105. Defines the unified perceptual-atom schema that binds
image, audio, and video ingest to the existing KG substrate, and
locks the review-gated ingest path so that no perceptual atom
bypasses `rq_submit` / `ingest.policy`. This ADR composes primitives
that already exist under `src/io/transducers/*` and `src/learning/*`;
it does not propose new inference algorithms.

## Date

2026-08-22

## Context

ADR-0105 uses the word "sandbox" for the ACCESS-CONTROL layer:
capability tokens, ownership overlay, signed skill install, TLS on
the wire. ADR-0200 uses the word "sandbox" for something different:
the internal cognitive surface where CrossEngin learns, where skills
run, where agents are produced, where answers are computed. Two
concepts are sharing a noun. This ADR fixes the terminology and
makes the cognitive sandbox its own first-class runtime concern.

The confusion has been tolerable while the cognitive surface has
been implicit — a scattering of learners under `src/learning/`, a
scattering of transducers under `src/io/transducers/`, a
scattering of belief-tracking under `src/parts/meta/`. But as the
factory shape crystallizes (ADR-0200) and the multimodal ingest
epic looms (ADR-0200 R120+), we need a concrete home for the
"mind's workspace" where perception normalizes into KG atoms and
where skills compose those atoms into agent outputs.

### Runtime shape: one sandbox or many?

Two viable shapes:

- One sandbox with multiple purposes. All learning, all skill
  execution, all agent production run in the same address space,
  sharing atom caches and HDC embeddings by construction.
- Many purpose-scoped sandboxes. Per-purpose isolation (learning is
  one process, skill execution another, agent production a third).
  Cheaper to reason about failure modes; harder to share caches.

Both shapes are defensible. The runtime supports either. The
BakeManifest (ADR-0203) picks which shape a given child ships with.
Most operators will pick one-sandbox for latency and simplicity;
regulated deployments may pick many-sandbox for stronger isolation
between learning and answering.

### The transducer inventory already in tree

`src/io/transducers/` contains approximately 39 modules covering the
non-text perception frontier: PNG and JPEG decode, SIFT / ORB / HOG
feature extraction, face and object detectors, OCR, MFCC and
spectrogram audio features, VAD (voice-activity), wake-word
detection, whisper and vosk STT bindings, Y4M video, motion vector
extraction, lip-sync detection, sensor-fusion. Every one of these
already exists as a NOVA source file. The ADR-0200 R120+ epic does
not need to build them; it needs to compose them.

### The learning inventory already in tree

`src/learning/` similarly contains the online-learning kernel:
`federated_aggregator`, `byzantine_aggregation`,
`predictive_coding_runtime`, `forward_forward`, `bayesian_updates`,
`belief_decay`, `plasticity_modulation`, `atom_birth_monitor`,
`atom_death_monitor`, plus the HDC embedding kernel and semantic
search under `src/kg/hdc_embed.nova` and
`src/kg/semantic_search.nova`. The cognitive sandbox is where these
run.

## Decision

### Terminology

- **Cognitive sandbox** — the runtime execution environment for
  learning, skill invocation, agent production, and answer
  computation. What ADR-0200 calls "the mind."
- **Access-control sandbox** — the capability + ownership + signed
  install layer specified by ADR-0105. Unrelated shape; same word,
  different concept.

Both terms remain valid within their scope. Cross-references
disambiguate by number: "sandbox (ADR-0105)" versus "sandbox
(ADR-0202)."

### Unified perceptual atom schema

Every perceptual observation, regardless of modality, lands in the
KG as a **perceptual atom** with the following shape:

- Base atom fields (kind, id, provenance, belief, ownership) — same
  as any KG atom.
- `perceptual_kind` — one of `IMAGE`, `AUDIO`, `VIDEO`, `SENSOR`,
  `MULTIMODAL_COMPOSITE`.
- `feature_slots` — a kind-typed dictionary of extracted feature
  vectors (HDC embedding, SIFT / ORB descriptors for images, MFCC
  frames for audio, motion vector summaries for video, ...). Slots
  are optional; a perceptual atom with only raw pixels and no
  features is a valid atom that has not yet been enriched.
- `text_projection` — optional OCR or STT text produced by a
  transducer. Text projections are themselves atoms with a
  `derived_from` edge to the perceptual atom.
- `provenance` — the transducer chain that produced the atom
  (`src:transducer:whisper_stt:v3`, `src:transducer:ocr_tesseract:v5`,
  etc.), so the review flow can weigh source authority per
  ADR-0029.

The schema is unified in the sense that a single KG walk can cross
modalities. A "photo of a page with a stamp" arrives as an IMAGE
atom, gets an OCR-derived text projection, gets a SIFT feature slot
for the stamp, and every downstream reasoning walk sees them as
peer atoms edge-linked to the same perceptual root.

### Review-gated ingest, always

Every learner-produced atom flows through `rq_submit` (the existing
review queue) and is gated by `ingest.policy` (the auto-approval
policy configured per source). No transducer bypasses this. No
learner shortcuts to a "trusted" write path. The R101 auto-approval
policy already covers per-source-authority auto-approvals; new
perceptual sources register their authority weight the same way
text sources do.

Consequence: a learner that finds a face in a photo does not add a
`FACE_OF_ALICE` atom to the KG. It adds a candidate atom with a
face-descriptor feature slot, and either a human reviewer or an
auto-approval policy elevates that candidate to an accepted atom.
The distinction is load-bearing: it is what prevents a compromised
transducer from silently poisoning the KG.

### Composition, not new inference

The cognitive sandbox is a composition layer. It does not introduce
new inference algorithms. Every transducer already ships. Every
learner already ships. The sandbox's job is to route perceptual
input through the transducer chain, land the atoms in the review
queue, and let the online-learning kernel (Bayesian updates, belief
decay, atom birth / death monitoring) operate on the accepted
atoms the same way it operates on text-derived atoms.

### One sandbox versus many — manifest picks

The BakeManifest (ADR-0203) carries a `sandbox_shape` field:

- `sandbox_shape: unified` — one address space, all purposes.
  Latency-optimized; sharing across learning / skill / agent is
  free.
- `sandbox_shape: partitioned` — per-purpose subprocess (learning,
  skill execution, agent composition). Fault-isolation-optimized;
  crash in one partition does not take down the others.

The runtime supports both by the same mechanism it already uses for
skill-supervisor sub-processes. The default for a new child bundle
is `unified`; regulated deployments (medical, security) can pick
`partitioned` at bake time.

### Runtime primitives already in tree

The composition draws on:

- `src/io/transducers/*` — all image / audio / video / sensor
  extractors (approximately 39 modules).
- `src/learning/federated_aggregator.nova` and
  `src/learning/byzantine_aggregation.nova` — federated model
  updates with Byzantine tolerance.
- `src/learning/predictive_coding_runtime.nova` and
  `src/learning/forward_forward.nova` — the two learning kernels
  the sandbox drives.
- `src/learning/bayesian_updates.nova` and
  `src/learning/belief_decay.nova` — belief maintenance over
  perceptual observations.
- `src/learning/plasticity_modulation.nova` — per-context learning
  rate control (attention analog).
- `src/learning/atom_birth_monitor.nova` and
  `src/learning/atom_death_monitor.nova` — lifecycle instrumentation
  for perceptual atoms.
- `src/kg/hdc_embed.nova` and `src/kg/semantic_search.nova` — the
  HDC embedding cache the sandbox shares across skills.

No new source files are proposed by this ADR. The composition wiring
is Phase B work; this ADR is design lock only.

## Consequences

### Positive

- Terminology unambiguous. The two sandboxes (access-control and
  cognitive) each have a name; cross-references say which one.
- The multimodal epic (ADR-0200 R120+) has a target design already.
  Each round of that epic is a small composition, not a fresh design.
- Perceptual atoms are inspectable. Every image, every audio clip,
  every video segment lands as a KG atom with typed feature slots
  and stamped provenance; a compliance audit can walk from the
  answer back to the raw observation and its transducer chain.
- No new trust bypass. Every perceptual atom is review-gated the
  same way text atoms are. A compromised transducer cannot silently
  poison the KG.
- Purpose-partitioning is optional. Operators who want fault
  isolation get it via `sandbox_shape: partitioned`; operators who
  want latency get `unified`. Neither shape is imposed.

### Negative

- The review queue will grow. Multimodal ingest can generate many
  candidate atoms per second (frames from video, features per
  frame). Auto-approval policy tuning becomes load-bearing; if it
  is too loose, the KG fills with noise; if too tight, human
  reviewers drown.
- Cross-modal reasoning is expensive. A KG walk that spans IMAGE,
  AUDIO, and VIDEO atoms is heavier than a text-only walk. The
  ADR-0208 latency budget must account for it.
- Learners are stateful. The federated / Byzantine / predictive-
  coding kernels carry per-run state. Snapshot fidelity (ADR-0203
  bake) has to serialize that state cleanly, or a bake produces a
  child whose learners restart cold.

### Neutral

- The transducer inventory (~39 modules) is complete for the
  targeted modalities. Additional transducers land in the same
  directory and register the same way; no shape change.
- Learner selection is per-domain. A child baked for medical imaging
  will register different transducers and different learning rates
  than a child baked for legal document review; the manifest
  captures both.

## Alternatives Considered

1. **Keep the cognitive layer implicit (rejected).** The current
   scattering of learners and transducers works but has no design
   anchor. As the multimodal epic lands, without an anchor each
   round has to re-argue the shape from scratch.

2. **Only one sandbox shape (either unified OR partitioned)
   (rejected).** Latency and fault isolation are both real
   requirements for different customer profiles. Committing to
   only one shape excludes one profile.

3. **Perceptual atoms as a separate KG (rejected).** Would isolate
   perception cleanly but break cross-modal walks. Text and
   perception must share KG identity space so an OCR-derived
   `person_name` atom can link to the same `person` atom a
   text-ingest turn created.

4. **Bypass review queue for high-confidence transducers
   (rejected).** Would speed ingest but break the ADR-0101 gate.
   Auto-approval already handles high-confidence sources without a
   trust-bypass path.

5. **Ship a new learning kernel dedicated to multimodal (rejected
   for near-term).** The existing kernels (Bayesian, predictive-
   coding, forward-forward) already handle multimodal input once
   features are extracted. A new kernel is not what unlocks the
   epic; composition is.

## See Also

- ADR-0105 — Access-control sandbox (different concept, same word).
- ADR-0200 — Mother/Child factory; names this as sub-decision 4.
- ADR-0203 — Bake pipeline; the `sandbox_shape` field on the
  manifest lives there.
- ADR-0204 — Slim runtime; child-mode disables sandbox mutation
  (no ingest, no bake).
- ADR-0206 — Beliefs and self-awareness; the introspective layer
  over the cognitive sandbox.
- ADR-0210 — Agent production; agents execute inside the cognitive
  sandbox.
- ADR-0101 — Data acquisition and review pipeline; every perceptual
  atom rides this pipeline.
- `src/io/transducers/*` — the transducer inventory.
- `src/learning/*` — the learning kernel inventory.
