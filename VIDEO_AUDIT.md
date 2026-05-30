# VIDEO_AUDIT — what real video perception in CrossEngin would take

Status: **deferred runtime seam (NOVA enhancement #15 / ADR-0014 video half).**
P3.2 lands the minimum-viable plank: a pure-NOVA decoder for the raw
YUV4MPEG2 (Y4M) container (`src/io/transducers/video_y4m.nova`), a pluggable
video perception seam that turns per-frame pixel statistics + frame-to-frame
deltas into substrate-shaped feature atoms (`src/io/transducers/
video_perception.nova`), the chat-side admin command `/play PATH [MAX_FRAMES]`,
and the `scripts/video_to_y4m.sh` ffmpeg shim. This document mirrors
`IMAGE_AUDIT.md` / `STT_AUDIT.md` / `TLS_AUDIT.md` — the realistic path, not a
promise.

## Why video is structurally harder than image

A single image is one perception in a 2-D field of intensities. Video is a
STREAM of perceptions in TIME ORDER, each correlated with its neighbors —
the temporal dimension is what makes vision systems hard. Two distinct
problems both grow with the temporal axis: (1) the **codec** problem —
unlike a still image, every interesting video format uses *inter-frame*
prediction (the current frame is encoded as a delta against earlier ones)
on top of *intra-frame* compression (DCT, entropy coding) inherited from
JPEG, so the decoder has to maintain a reference-frame buffer and run
motion compensation; and (2) the **perception** problem — anything more
interesting than "what's in this single frame" requires correlating frames:
optical flow, object tracking, action recognition. Pure NOVA covers
neither today; the plank we land in P3.2 is Y4M (no compression, ~200
lines) + crude per-frame statistics (mean intensity, dominant bucket,
histogram entropy from P3.1) + naive temporal features (mean absolute
luma difference for motion, threshold for scene change) so the framework
can be exercised end-to-end against a tractable fixture format.

The sandbox tested against has neither a camera nor `ffmpeg`. The unit
suite covers only the in-memory Y4M decoder + statistics + motion proxy;
the shim's "no backend installed" branch is what CI sees for non-Y4M
input.

## Why Y4M, and why only Y4M

YUV4MPEG2 (the Y4M container) is the video equivalent of PGM: an ASCII
header line (`YUV4MPEG2 W<w> H<h> F<num>:<den> ... C420\n`) followed by a
sequence of raw uncompressed YCbCr frames each prefixed by `FRAME\n` and
encoding the Y / Cb / Cr planes back to back. No compression, no inter-
frame coding, no entropy decoder. A correct decoder is ~200 lines of
straight-line NOVA. The format is a common test fixture: `ffmpeg -i
input.mp4 -pix_fmt yuv420p -f yuv4mpegpipe -` writes it directly to
stdout, and `scripts/video_to_y4m.sh` wraps that for the operator. A
working Y4M decoder PROVES the framework (the pluggable seam, the
per-frame feature extraction, the motion proxy, the `/play` admin
command, the integration scaffold) without the multi-month trap of
writing a real H.264 decoder.

The trade-off: Y4M is **enormous on the wire**. A single second of
480p uncompressed YCbCr at 30 fps is ~13 MB. A full minute is ~800 MB.
Y4M is fine as a test fixture and for short clips, but it is not how
production video moves over networks.

## Realistic options for CrossEngin, in increasing difficulty

1. **Subprocess shim to ffmpeg** *(easiest — landed)*. The operator
   points `/play` at a Y4M file, or pre-converts via
   `scripts/video_to_y4m.sh PATH` (probes `ffmpeg`; otherwise prints
   the install hint and exits 0). Same shape as `scripts/transcribe.sh`
   (STT) and `scripts/image_to_pgm.sh` (image) — a thin escape hatch
   over a domain we don't intend to write ourselves.
2. **WASM-bundled libavcodec** *(medium-hard)*. Once P2.7 WASM matures
   the agent can host a stripped libavcodec build (~500 KB blob)
   compiled to WASM that decodes the common codecs (H.264, H.265, VP9).
   The blocker is P2.7 WASI — without filesystem / argv it has no way
   to read a path. Same shape as `WASM_AUDIT.md` envisions for
   whisper-WASM on the STT side.
3. **Pure-NOVA MJPEG** *(hard, ~3-4 weeks)*. Motion JPEG = a Y4M-shaped
   container with per-frame JPEG decoding instead of raw bytes. Once a
   pure-NOVA JPEG decoder lands (~6-8 weeks per `IMAGE_AUDIT.md`),
   MJPEG comes essentially for free — it's a JPEG decoder in a loop,
   no inter-frame coding, no entropy state across frames.
4. **Pure-NOVA H.264** *(months)*. H.264 = NAL-unit container + CABAC
   (context-adaptive binary arithmetic) entropy coder + 4x4 and 8x8
   integer DCT + intra-prediction (9 modes for 4x4 / 4 for 16x16) +
   inter-prediction with motion compensation + deblocking filter. ~10K
   lines of careful NOVA with the small-multiplier discipline gotcha
   #11 already imposes. Two to four months of focused work.
5. **Pure-NOVA H.265 / AV1 / VP9** *(not feasible this year)*. Each is
   2-3x the H.264 complexity (~30K lines each, even more intricate
   entropy coding and prediction modes). Reserved for the WASM path.

## Vision feature pipeline beyond pixels

Decoding the pixel buffer is half the battle. The other half is turning
the resulting stream into something the agent's concept atoms can latch
onto. P3.2 ships a deliberately crude set:

- The per-frame image features from P3.1 (`image_dim_*`, `image_dark/
  mid/bright`, `image_bucket_<0..7>`, `image_hist_<peaked|uniform>`).
- `motion_<low|mid|high>` — mean absolute luma difference between
  consecutive frames. Thresholds: 1..15 low, 15..50 mid, >=50 high.
- `scene_change` — frame-to-frame delta exceeds 50, fires
  independently of motion_high so the substrate can treat "high
  motion" and "scene cut" as overlapping but distinct evidence.

The realistic feature ladder, each rung its own multi-week lift:

| Feature                              | NOVA effort     |
|--------------------------------------|-----------------|
| Mean intensity / motion / scene-change | landed (P3.2) |
| Optical flow (Lucas-Kanade)          | 1-2 weeks       |
| Object tracking (IoU / Kalman)       | 2-3 weeks       |
| Background subtraction (MOG)         | 1-2 weeks       |
| Temporal histograms                  | 1 week          |
| Action recognition (3D CNN)          | many months + GPU |
| Audio-visual fusion                  | 4-6 weeks       |

A "production agent that can watch a YouTube video and reason about it"
is **4-8 months** for the codec + features piece (H.264 decode + optical
flow + object tracking + background subtraction), and **12+ months** for
trained action-recognition. Pure-NOVA 3D CNN training is unrealistic
this decade; the WASM libavcodec + an embedded action-recognition model
is the realistic embedded-model option once both halves land.

## Mapping video features to atoms

Each per-frame feature becomes an atom of the form
`visual_<feature>_<value>` in the moment stream, exactly the way image
features and word atoms are bound. Sustained features (e.g. "motion_high
for 30 consecutive frames") consolidate into a single durable atom per
ADR-0022 (consolidation), exactly the way the substrate consolidates
repeated word observations into stable concept atoms. The substrate
can then learn associations between, say, `motion_high + scene_change`
and the downstream concept "action sequence" — the same Hebbian path
the text perception loop uses (ADR-0023 + ADR-0025).

The current shipped seam emits per-frame `EV_MESSAGE`-shaped lines as
chat output; the atom-creation side (binding each label to an
`ATOM_VISUAL` concept atom, attaching the source-authority tier,
dispatching the per-frame perception event to the reader) lives in
`src/agent/loop_perception.nova` and is a separate follow-up. The
substrate isn't wired to ingest 30 frame-events per second of wall-
clock yet; the realtime pacer (P0.6) caps perception throughput at
~10 events / second today, which is fine for the chat REPL but not
for a live camera feed.

## Wall-clock estimate

| Milestone                                          | Effort           |
|----------------------------------------------------|------------------|
| Y4M + per-frame stats + motion + ffmpeg shim       | landed (P3.2)    |
| Pure-NOVA MJPEG (per-frame JPEG)                   | 3-4 weeks*       |
| Pure-NOVA H.264                                    | 2-4 months       |
| Pure-NOVA H.265 / AV1 / VP9                        | 6-12 months each |
| Optical flow (Lucas-Kanade) in pure NOVA           | 1-2 weeks        |
| Object tracking (IoU / Kalman) in pure NOVA        | 2-3 weeks        |
| Background subtraction (MOG)                       | 1-2 weeks        |
| WASM-bundled libavcodec bridge                     | 2 weeks post-P2.7|
| Action recognition (3D CNN, trained)               | 12+ months       |

\* Requires pure-NOVA JPEG (~6-8 weeks per `IMAGE_AUDIT.md`) as a
prerequisite, so MJPEG lands ~9-12 weeks from a cold start.

Combined honest estimate: **4-8 months** to a daemon that can ingest
compressed video (H.264 decode + optical flow + object tracking +
background subtraction + atom-binding wire-up). Production-grade
scene understanding (action recognition / VQA on video) is **12+
months** of focused effort.

## Recommended path

Today: **`scripts/video_to_y4m.sh` shim** for any operator who needs to
feed real footage to a CrossEngin daemon. Single-backend (ffmpeg) and
exits 0 in all branches so the seam never crashes on a sealed sandbox.
Set `CE_Y4M_MAX_DIM=432` and `CE_Y4M_MAX_FRAMES=30` to respect the
pure-NOVA decoder's 768x432 pixel cap and the realtime pacer's
~10 events/second perception budget.

Next: revisit pure-NOVA decoders only after the modality bridge
matures AND a concrete use case demands them. **MJPEG before H.264**
— MJPEG falls out of pure-NOVA JPEG nearly for free; H.264 is months
of unavoidable code regardless of how the framework is shaped.
Pure-NOVA H.265 / AV1 / VP9 are not on any roadmap within the next
year.

## NOVA gotchas worked around in P3.2

- **Codegen pointer-threshold (gotcha #11, NOVA enhancement #6+).** Any
  in-function multiply whose product exceeds ~2^20 misroutes into
  `str_repeat`. The Y4M decoder caps dimensions at 768 x 432 per axis
  so `width * height <= 331776` and even the per-frame total
  (`w*h * 3/2 == 497664` for 4:2:0) stays under the empirical ceiling.
  Larger Y4M files are refused at header time with a clear "downsample
  first" error.
- **`read_file` builtin NUL stop.** NOVA's `read_file` returns a NUL-
  terminated string buffer, and `len()` stops at the first embedded
  NUL. Raw video bytes contain plenty of zeros. We use `sys_open` +
  `sys_read` in a loop accumulating into a raw byte buffer
  (`alloc(N) + store8/load8`) — the same NUL-safe pattern image_pgm.nova
  uses for P3.1.
- **Small-intermediate motion math.** The mean absolute luma
  difference uses one byte-wise loop with a single `int` accumulator;
  at the cap (768 * 432 * 255 = ~85M) it stays comfortably under 2^27,
  well within the in-function multiply ceiling.
- **Chroma layout assumption.** P3.2 targets 4:2:0 chroma subsampling
  (the format `ffmpeg ... -pix_fmt yuv420p` produces). Other layouts
  (4:2:2, 4:4:4) write different chroma plane sizes; supporting them
  is a deferred follow-up. The header's `C` tag is parsed but its
  value is currently ignored — a real production shim should reject
  non-C420 streams with a clear diagnostic.

## Cross-references

* `src/io/transducers/video_y4m.nova` — pure-NOVA Y4M decoder +
  per-frame iterator + mean-absolute-difference motion proxy.
* `src/io/transducers/video_perception.nova` — pluggable seam +
  per-frame feature extraction (image features from P3.1 + motion +
  scene-change).
* `scripts/video_to_y4m.sh` — ffmpeg shim with a "no backend" exit-0
  fallback so a sealed sandbox never crashes the operator's pipeline.
* `examples/crossengin_chat.nova` — `/play PATH [MAX_FRAMES]` admin
  command + dispatch + /help entry.
* `tests/unit/test_video_y4m.nova` — in-memory assertions covering
  header parsing, frame iteration, malformed inputs, end-of-stream
  semantics, and the motion proxy.
* `tests/integration/scenario_s_video_play.sh` — end-to-end /play chat
  assertions against a hand-rolled 5-frame 4x4 Y4M fixture with two
  forced scene changes.
* `nova-deps.toml` enhancement #15 — upstream tracker for full visual
  stack (image and video decode, feature extraction, embeddings).
* `IMAGE_AUDIT.md` — sibling audit for the still-image modality
  bridge; pure-NOVA JPEG (a prerequisite for MJPEG) is on the same
  enhancement.
* `STT_AUDIT.md` — sibling audit for the audio modality bridge.
