# IP_AUDIT.md

Licensing / provenance audit of CrossEngin's transducers, learning, and safety
modules, plus a small set of spot-checked files from adjacent trees. This is a
Phase A doc-only pass; nothing in the source tree is modified by it.

## 1. Summary

A total of 112 NOVA source files were audited:

- `src/io/transducers/`  -- 51 files
- `src/learning/`        -- 28 files
- `src/safety/`          -- 29 files
- Spot checks            -- 4 files (`src/kg/hdc_embed.nova`,
  `src/kg/semantic_search.nova`, `src/persistence/merkle_signing.nova`,
  `src/sandbox/skill_signature.nova`)

Per-category classification counts:

| Category                                            | Count |
|-----------------------------------------------------|------:|
| A. Hand-rolled from public spec / paper             |   112 |
| B. Permissively licensed with attribution present   |     0 |
| C. Permissive but attribution MISSING               |     0 |
| D. Unknown provenance                               |     0 |
| E. Copyleft / restrictive                           |     0 |
| F. Patent concern (all RESOLVED)                    |     2 |

The two Category-F entries (`image_sift.nova`, `image_face_detect.nova`) are
counted alongside their Category-A classification -- both are cited here for
completeness because published patents once encumbered the underlying
algorithms, but each patent has expired and each file's header documents the
situation. No file needs a rewrite.

**Overall licensing risk: LOW.** Every file audited either (a) implements a
public RFC / FIPS / ITU-T / W3C standard, (b) implements a published academic
algorithm, or (c) is a wholly internal CrossEngin construct implementing an ADR.
No third-party source code has been ported into the tree, and no import
statement in the audited scope references an external package.

## 2. Methodology

For every file in the three primary directories plus the four spot-check files:

1. The file's header comment block (typically 20-100 lines) was read to
   identify the algorithm implemented and the citation the file names.
2. Every citation was cross-referenced against the "Known reference points"
   list carried at the top of this audit (RFC / FIPS / patent-expiration
   status / permissive-upstream summaries).
3. Every `import` statement across `src/io/transducers`, `src/learning`, and
   `src/safety` was grepped to confirm that no file reaches out to an external
   package. The only imports found are (a) repo-relative `.nova` files and
   (b) `std/io`, `std/syscall`, `std/string` -- the NOVA runtime standard
   library, which is part of the NOVA distribution and not third-party.
4. When a file's header explicitly named an upstream project (whisper.cpp,
   Vosk), the file's body was checked to confirm the file only shells out to
   the binary rather than porting its code -- in both cases confirmed.

Two categories that required special handling:

- **F. Patent concern.** SIFT (Lowe 2004, US Patent 6,711,293) and Viola-Jones
  (2001, US Patent 7,099,510) each carried a published patent. Both patents
  are expired (SIFT March 2020; Viola-Jones by 2021 counting the standard
  20-year term from the 2001 priority date). Both source files call this out
  in their header, and no cascade weights / patented tables ship with either
  module.
- **Vosk / whisper.cpp.** Both are permissively licensed (Apache 2.0 and MIT
  respectively) and the CrossEngin files that name them (`vosk_backend.nova`,
  `whisper_backend.nova`) are subprocess wrappers that fork/exec the upstream
  binary if it is installed; they do NOT contain ported code. That places them
  in Category A -- an internal integration shim citing the upstream in its
  header -- rather than B.

## 3. Findings by category

### 3.A. Hand-rolled from public spec

All 112 audited files fall into this category. Grouped by sub-tree for
compactness; the per-file table is folded under the group header when many
files share the same spec class.

#### 3.A.i. Safety -- cryptographic primitives (`src/safety/`)

Every safety module is a pure-NOVA implementation of a published standard.
Attribution is present in the file header in every case.

| File                              | Spec / paper referenced                                 | Attribution present |
|-----------------------------------|---------------------------------------------------------|--------------------:|
| `aes_gcm.nova`                    | FIPS 197 + NIST SP 800-38D                              | Y |
| `bignum.nova`                     | 256-bit multi-precision integer (textbook)              | Y |
| `bignum_2048.nova`                | RFC 7919 Group 14 sizing, Montgomery REDC (textbook)    | Y |
| `bignum_256.nova`                 | Montgomery CIOS reduction (textbook)                    | Y |
| `capability_gate.nova`            | CrossEngin ADR-0094 (internal)                          | Y |
| `chacha20.nova`                   | RFC 7539 / RFC 8439                                     | Y |
| `chacha20_poly1305.nova`          | RFC 8439 §2.8                                           | Y |
| `constitutional_filter.nova`      | CrossEngin ADR-0045 / ADR-0041 / ADR-0042               | Y |
| `differential_privacy.nova`       | Discrete-Laplace mechanism (Dwork; Ghosh-Roughgarden)   | Y |
| `dp_budget_ui.nova`               | Presentation layer over `differential_privacy.nova`     | Y |
| `ecdsa.nova`                      | FIPS 186-4 §6.4                                         | Y |
| `ed25519.nova`                    | RFC 8032 (PureEdDSA over Edwards25519)                  | Y |
| `field25519.nova`                 | RFC 7748 App. A + Bernstein 10-limb layout              | Y |
| `hkdf_sha256.nova`                | RFC 5869 + RFC 2104                                     | Y |
| `md5.nova`                        | RFC 1321                                                | Y |
| `override_mechanism.nova`         | CrossEngin ADR-0044                                     | Y |
| `p256.nova`                       | SEC 2 v2.0 / FIPS 186-4 / RFC 6090                      | Y |
| `pem_truststore.nova`             | PEM (RFC 7468) / RFC 5280                               | Y |
| `permission_tiers.nova`           | CrossEngin ADR-0041                                     | Y |
| `poly1305.nova`                   | RFC 7539 / RFC 8439 §2.5                                | Y |
| `reversibility_classifier.nova`   | CrossEngin ADR-0042                                     | Y |
| `rng.nova`                        | Linux getrandom + SHA-256 extractor (internal)          | Y |
| `rsa.nova`                        | PKCS #1 v1.5 + PSS (RFC 8017)                           | Y |
| `scram.nova`                      | RFC 5802 / RFC 7677 / RFC 7635 / RFC 8018 / RFC 4648    | Y |
| `sha1.nova`                       | FIPS 180-4 / RFC 3174 / RFC 2104                        | Y |
| `sha256.nova`                     | FIPS 180-4 / RFC 2104                                   | Y |
| `x25519.nova`                     | RFC 7748                                                | Y |
| `x509.nova`                       | RFC 5280 §4.1                                           | Y |
| `x509_verify.nova`                | RFC 5280 + RFC 8017                                     | Y |

Cross-cutting observation: `md5.nova` and `sha1.nova` both carry a "historical
caveat" block in their headers documenting the known cryptographic breaks
(Wang et al. 2004, SHAttered 2017) and explaining why the module still ships
(legacy RFC compatibility -- SCRAM-SHA-1, TURN long-term credential auth).
The caveats are appropriate; both algorithms remain in the RFC corpus and are
required by named interop protocols.

#### 3.A.ii. Transducers -- image / vision (`src/io/transducers/image_*`)

All eighteen image modules are hand-rolled from published computer-vision
literature. Every header names the paper it follows.

| File                            | Spec / paper referenced                              | Attribution present |
|---------------------------------|------------------------------------------------------|--------------------:|
| `image_canny.nova`              | Canny 1986                                           | Y |
| `image_detector.nova`           | Dalal & Triggs CVPR 2005 (HOG detector)              | Y |
| `image_face_detect.nova`        | Viola & Jones 2001 (structural cascade only)         | Y |
| `image_face_recognize.nova`     | Ahonen et al. 2006 (LBP face recognition)            | Y |
| `image_harris.nova`             | Harris & Stephens 1988                               | Y |
| `image_hog.nova`                | Dalal & Triggs CVPR 2005                             | Y |
| `image_lbp.nova`                | Ojala 1996 (LBP texture)                             | Y |
| `image_ocr.nova`                | Template-matching OCR (textbook)                     | Y |
| `image_optical_flow.nova`       | Lucas & Kanade 1981                                  | Y |
| `image_orb.nova`                | Rublee et al. ICCV 2011                              | Y |
| `image_panorama.nova`           | Textbook 4-step homography stitching                 | Y |
| `image_pgm.nova`                | Netpbm PGM-P5 public spec                            | Y |
| `image_segmentation.nova`       | Lloyd's k-means                                      | Y |
| `image_sift.nova`               | Lowe 2004 (detection only)                           | Y |
| `image_sobel.nova`              | Sobel & Feldman 1968                                 | Y |
| `image_stereo.nova`             | Block-matching stereo (textbook SAD)                 | Y |
| `image_superpixels.nova`        | Achanta et al. 2012 (SLIC)                           | Y |
| `image_tracker.nova`            | Kalman filter + greedy Hungarian assignment          | Y |

Two of the above (SIFT, Viola-Jones) had published patents in the past; both
are expired. See §3.F for the patent-status review.

#### 3.A.iii. Transducers -- audio (`src/io/transducers/audio_*`)

Eleven audio modules; each header cites the relevant classical DSP or speech
literature.

| File                          | Spec / paper referenced                                              | Attribution present |
|-------------------------------|----------------------------------------------------------------------|--------------------:|
| `audio_capture.nova`          | Internal shell-out to `scripts/audio_capture.sh`; canonical 44-byte WAV parser | Y |
| `audio_dsp.nova`              | Schroeder 1962 ("Natural-Sounding Artificial Reverberation", JAES)   | Y |
| `audio_melody.nova`           | MIDI-note quantisation of F0 estimates (textbook)                    | Y |
| `audio_mfcc.nova`             | Textbook MFCC pipeline (Mel filter bank + DCT-II)                    | Y |
| `audio_noise_reduce.nova`     | Boll 1979 / Lim & Oppenheim 1979 (spectral subtraction / Wiener)     | Y |
| `audio_pitch.nova`            | Autocorrelation F0 (textbook)                                        | Y |
| `audio_psola.nova`            | Moulines & Charpentier 1990 (TD-PSOLA)                               | Y |
| `audio_speaker_id.nova`       | Reynolds & Rose (speaker-recognition literature)                     | Y |
| `audio_spectrogram.nova`      | Short-Time Fourier Transform (textbook)                              | Y |
| `audio_vad.nova`              | Energy + zero-crossing-rate VAD (textbook)                           | Y |
| `audio_wakeword.nova`         | MFCC template + DTW matched filter (textbook)                        | Y |

#### 3.A.iv. Transducers -- speech-backend integrations (`stt_seam.nova`, `vosk_backend.nova`, `whisper_backend.nova`)

Both external-STT backends are subprocess wrappers, not code ports.

| File                          | Upstream referenced                                  | License of upstream | Code copied into repo? |
|-------------------------------|------------------------------------------------------|---------------------|------------------------|
| `whisper_backend.nova`        | ggerganov/whisper.cpp                                | MIT                 | No -- fork/exec only   |
| `vosk_backend.nova`           | alphacephei/vosk-api                                 | Apache 2.0          | No -- fork/exec only   |
| `stt_seam.nova`               | Internal dispatcher across stub / subprocess / native | N/A                | N/A                    |

Each backend file cites its upstream in the file header (including license
name and URL). Because no upstream source lines have been copied, no upstream
license file needs to be shipped inside this tree. A downstream integrator
who chooses to bundle whisper.cpp or Vosk with a CrossEngin build MUST ship
the upstream LICENSE text alongside those binaries -- that is an obligation on
the operator, not on the CrossEngin tree.

#### 3.A.v. Transducers -- video (`src/io/transducers/video_*`, `visual_perception.nova`, `video_perception.nova`)

| File                              | Spec / paper referenced                                          | Attribution present |
|-----------------------------------|------------------------------------------------------------------|--------------------:|
| `video_motion_vectors.nova`       | Textbook block-matching motion estimation                        | Y |
| `video_perception.nova`           | Internal seam                                                    | Y |
| `video_smooth.nova`               | Kalman filter + greedy Hungarian (internal composition)          | Y |
| `video_y4m.nova`                  | YUV4MPEG2 public spec (Y4M)                                      | Y |
| `visual_perception.nova`          | Internal seam                                                    | Y |

#### 3.A.vi. Transducers -- codecs, transport, streams, XML

| File                              | Spec / paper referenced                                          | Attribution present |
|-----------------------------------|------------------------------------------------------------------|--------------------:|
| `deflate_decode.nova`             | RFC 1951                                                         | Y |
| `png_decode.nova`                 | RFC 2083 + inner zlib/DEFLATE                                    | Y |
| `jpeg_decode.nova`                | ITU-T T.81 baseline sequential                                   | Y |
| `http_client.nova`                | HTTP/1.1 (RFC 7230)                                              | Y |
| `input_transducer.nova`           | Internal (ADR-0011/0012/0014/0021)                               | Y |
| `kg_rss_ingest.nova`              | RSS 2.0 / Atom 1.0                                               | Y |
| `kg_sync.nova`                    | Internal wire protocol                                           | Y |
| `noise_xk.nova`                   | Noise Protocol Framework XK pattern (noiseprotocol.org)          | Y |
| `secure_channel.nova`             | Internal composition of ChaCha20 + Poly1305                      | Y |
| `stream_audio.nova`               | Internal                                                         | Y |
| `stream_http.nova`                | Internal                                                         | Y |
| `stream_stdin.nova`               | Internal                                                         | Y |
| `stream_unix_socket.nova`         | Internal                                                         | Y |
| `tls13_client.nova`               | RFC 8446 + RFC 8448 test vectors                                 | Y |

#### 3.A.vii. Learning (`src/learning/`)

All 28 learning modules are either (a) implementations of published academic
methods with citations present in the header, or (b) wholly internal CrossEngin
ADR machinery. None ports third-party code.

| File                                  | Spec / paper referenced                                             | Attribution present |
|---------------------------------------|---------------------------------------------------------------------|--------------------:|
| `ask_user_to_teach.nova`              | CrossEngin ADR-0027                                                 | Y |
| `atom_birth_monitor.nova`             | CrossEngin ADR-0025 / ADR-0023 / ADR-0024                           | Y |
| `atom_death_monitor.nova`             | CrossEngin ADR-0025                                                 | Y |
| `autonomous_research.nova`            | CrossEngin ADR-0026 / ADR-0028                                      | Y |
| `bayesian_updates.nova`               | CrossEngin ADR-0023 / ADR-0029 (Beta distribution -- public math)   | Y |
| `belief_decay.nova`                   | CrossEngin ADR-0023 / ADR-0088                                      | Y |
| `byzantine_aggregation.nova`          | Robust-mean literature (trimmed mean, coordinate median)            | Y |
| `confidence_thresholds.nova`          | CrossEngin ADR-0030                                                 | Y |
| `corroboration.nova`                  | CrossEngin ADR-0092                                                 | Y |
| `dns_resolver.nova`                   | DNS-over-UDP (RFC 1035)                                             | Y |
| `entity_resolve.nova`                 | CrossEngin ADR-0053 + HDC neighbourhood match                       | Y |
| `federated_aggregator.nova`           | Internal composition over DP + SecAgg (CrossEngin ADR-0054)         | Y |
| `formal_ingest.nova`                  | CrossEngin ADR-0087 / ADR-0088                                      | Y |
| `forward_forward.nova`                | Hinton 2022 ("Forward-Forward algorithm")                           | Y |
| `internet_fetch.nova`                 | CrossEngin ADR-0028 / ADR-0029                                      | Y |
| `learn_pipeline.nova`                 | CrossEngin ADR-0028 / ADR-0026 composition                          | Y |
| `learning_policy.nova`                | CrossEngin ADR-0096                                                 | Y |
| `maintenance.nova`                    | CrossEngin ADR-0037 / ADR-0023 / ADR-0025 / ADR-0088                | Y |
| `openie.nova`                         | Shallow heuristic OpenIE (not Stanford OpenIE code)                 | Y |
| `plasticity_modulation.nova`          | CrossEngin ADR-0035 / ADR-0007                                      | Y |
| `predictive_coding_runtime.nova`      | Rao & Ballard 1999 (predictive coding)                              | Y |
| `preprocess.nova`                     | Internal HTML-strip + tokenize + triple extract                     | Y |
| `promotion.nova`                      | CrossEngin ADR-0092                                                 | Y |
| `research_sources.nova`               | Internal (extends ADR-0026 / ADR-0028)                              | Y |
| `secure_aggregation.nova`             | Bonawitz et al. 2017 (Google SecAgg mask primitive)                 | Y |
| `self_learning_triggers.nova`         | CrossEngin ADR-0026 / ADR-0024 / ADR-0023                           | Y |
| `source_authority.nova`               | CrossEngin ADR-0029                                                 | Y |
| `source_whitelist.nova`               | CrossEngin ADR-0028                                                 | Y |

Two learning modules deserve a note:

- `openie.nova` -- The file header is explicit that this is a "shallow,
  heuristic parser (no full dependency parse)" tuned for precision over
  recall. It does NOT follow the Stanford OpenIE 2015 code (which is Apache
  2.0 and would still be safe to port with attribution). No Stanford code has
  been ingested; the implementation is a small hand-written pattern matcher.
- `secure_aggregation.nova` -- Cites Bonawitz et al. 2017 in the header. The
  paper describes the SecAgg protocol; the code here implements the pairwise
  additive-masking primitive from the paper as a fresh NOVA implementation.
  The referenced Google reference implementation is not included in the tree.

#### 3.A.viii. Spot-checked files outside the three primary directories

| File                                     | Spec / paper referenced                                     | Attribution present |
|------------------------------------------|-------------------------------------------------------------|--------------------:|
| `src/kg/hdc_embed.nova`                  | Kanerva 2009; Plate HRR; Gayler VSA                         | Y |
| `src/kg/semantic_search.nova`            | TF-IDF (classical IR)                                       | Y |
| `src/persistence/merkle_signing.nova`    | Merkle tree + Ed25519 (RFC 8032)                            | Y |
| `src/sandbox/skill_signature.nova`       | Internal (sha256 + Ed25519 sign-of-canonical-manifest)      | Y |

### 3.B. Permissively licensed with attribution present

None. No third-party source code has been ported into the audited scope, so
no B rows exist. (The subprocess integrations with whisper.cpp and Vosk are
covered in §3.A.iv and do not fall in category B because no upstream code
lives in the tree.)

### 3.C. Attribution missing

None. Every A-classified file names either an RFC / FIPS / ITU-T standard,
a published academic paper, or a CrossEngin ADR. No file was found whose
implementation appears to follow a permissively licensed upstream without
citing it.

### 3.D. Unknown provenance

None. Every file's header describes the algorithmic source in enough detail
to place the file in a category with confidence.

### 3.E. Copyleft / restrictive

None. No GPL, AGPL, LGPL, or otherwise copyleft-encumbered code was found.

### 3.F. Patent concern

Two files implement algorithms that once carried patents. Both patents are
expired; both file headers document the situation.

| File                              | Patent (historical)                                                                                   | Status    |
|-----------------------------------|-------------------------------------------------------------------------------------------------------|-----------|
| `image_sift.nova`                 | US Patent 6,711,293 ("Method and apparatus for identifying scale invariant features") -- Lowe / UBC   | RESOLVED (expired March 2020) |
| `image_face_detect.nova`          | US Patent 7,099,510 ("Method and system for object detection in digital images") -- Viola & Jones     | RESOLVED (expired; 20-year term from 2001 priority date) |

Both files ship the STRUCTURAL algorithm only. In particular,
`image_face_detect.nova` explicitly refrains from shipping OpenCV's trained
Haar cascade weights (`haarcascade_frontalface_default.xml`); that is
CrossEngin's Rule 4 (no frozen models) rather than a licensing gate, but it
also happens to remove a residual attribution obligation on the BSD-licensed
OpenCV file. The file header is explicit about the accuracy trade-off this
imposes.

No further F-class entries are open.

## 4. Cross-cutting concerns

- **RFC / FIPS standards.** The safety tree implements roughly a dozen
  IETF and NIST standards from scratch. Every module names the standard it
  follows. Standards documents themselves are not copyrightable as
  algorithms; no attribution obligation flows from implementing them beyond
  the file-header naming that is already present.
- **Refactor of duplicated SHA-256 / SHA-1 / MD5.** `sha256.nova`,
  `sha1.nova`, and `md5.nova` each document that they consolidate
  previously-inlined copies of the same FIPS 180-4 / RFC 1321 primitives
  that lived in other modules (noise_xk, merkle, dtls12, ecdsa, srtp, turn).
  All copies were the same textbook recipe -- no distinct upstream to cite,
  and no license-status change from the consolidation.
- **Two vision modules follow the same paper.** `image_hog.nova` and
  `image_detector.nova` both cite Dalal & Triggs CVPR 2005. That is not a
  license concern (the paper is public literature); it is only a note that
  a change in the cited version would apply to both.
- **External-STT subprocess seam.** `whisper_backend.nova` and
  `vosk_backend.nova` are the ONLY files in the audited scope that name
  external binaries. Neither ports code; both merely fork/exec if the
  upstream binary is installed on the host. Downstream integrators who
  bundle those binaries must ship the upstream MIT / Apache 2.0 license
  text with the binaries -- that obligation is on the binary bundle, not on
  the CrossEngin tree.

## 5. Rule 1 compliance

CrossEngin Rule 1 forbids third-party dependencies. Every `import` statement
found in the audited scope is either:

1. A repo-relative `.nova` file (e.g. `import "audio_capture.nova"`,
   `import "../../safety/chacha20.nova"`), or
2. A NOVA standard-library module (`std/io`, `std/syscall`, `std/string`),
   which is part of the NOVA runtime and not a third-party package.

Grep of `^import "` across `src/io/transducers`, `src/learning`, and
`src/safety` found no imports that name an external package (no `github.com/`,
no `pypi:`, no `npm:`, no `cargo:`, no bare package identifiers pointing at a
non-NOVA registry). The two files that touch external STT binaries
(`whisper_backend.nova`, `vosk_backend.nova`) do so through `fork+exec` via
`std/syscall`, not through a linkable dependency.

**Rule 1 status: COMPLIANT** across the audited scope.

## 6. Recommendations

Because no ACTION REQUIRED items were surfaced, the recommendation list is
short and forward-looking rather than remedial. Each item is labelled with a
suggested time frame.

1. **Before shipping v1.0.** Add a top-level `LICENSES/` directory (or a
   `THIRD_PARTY_NOTICES.md`) that enumerates the standards / papers each
   module implements. This is not a legal requirement -- attribution is
   already in each file header -- but it makes downstream licensing review
   trivial for enterprise adopters. A generator script that walks each
   header's "Algorithm references" block would keep the notice in sync
   automatically.
2. **Before shipping v1.0.** Add a short subsection to `docs/VISION.md`
   (or a dedicated `docs/LICENSING.md`) that states plainly: "CrossEngin
   contains no third-party source code. All modules are hand-rolled from
   public specifications and academic literature. See docs/IP_AUDIT.md for
   the file-by-file classification." This forestalls the recurring
   "which licence is this under?" question without a lawyer having to
   inspect the tree.
3. **Before shipping v1.0.** For any downstream integrator who chooses to
   bundle whisper.cpp or Vosk with a CrossEngin build, add a
   `docs/BUNDLING_BINARIES.md` that reminds them of the whisper.cpp MIT
   and Vosk Apache 2.0 obligations. This is a note to operators, not a
   change to the CrossEngin source tree.
4. **Ongoing (each new round).** New files added to `src/io/transducers/`,
   `src/learning/`, or `src/safety/` should carry a header block that names
   the algorithm's source (RFC number, FIPS section, or paper citation).
   Code review should refuse any new module whose header does not answer
   the question "where does this algorithm come from?".
5. **Ongoing (each new round).** Any new subprocess wrapper (analogous to
   `whisper_backend.nova`) should follow the same shape: cite the upstream
   project + license + URL in the file header, and shell out via
   `std/syscall` rather than link to a shared library.

There are NO priority-1 actions -- nothing in the audited scope requires
attribution addition, rewrite, or removal today.

## 7. Sign-off checklist

Future rounds should re-run this audit whenever any of the following happen:

- A new `.nova` file lands under `src/io/transducers/`, `src/learning/`,
  `src/safety/`, or one of the spot-checked directories (`src/kg/`,
  `src/persistence/`, `src/sandbox/`).
- Any existing file's header block is edited in a way that changes the
  cited spec or paper.
- A new subprocess-wrapper module is added that shells out to a
  previously-unmentioned external binary.
- Any `import` statement in the audited scope begins to reference a
  package identifier that is neither a repo-relative `.nova` file nor a
  `std/*` NOVA runtime module.
- A file's algorithmic implementation is materially changed such that the
  cited reference no longer describes what the code does.

A re-audit round should re-verify:

1. Per-file classification (A / B / C / D / E / F) against the updated file
   header block.
2. Rule 1 compliance via a fresh `grep` of `^import "` across the audited
   scope.
3. Patent-status entries in §3.F remain expired (no new patents have been
   granted on the same algorithms with wider claims -- unlikely but worth a
   check when a decade has passed).
4. Attribution presence in the header of every A-classified file (the item
   most likely to regress through casual header edits).

End of audit.
