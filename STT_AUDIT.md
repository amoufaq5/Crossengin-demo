# STT_AUDIT — what real speech-to-text in CrossEngin would take

Status: **deferred runtime seam (NOVA enhancement #14, STT half).** P19 + P2.6
landed the TTS half (`src/io/effectors/audio_synth.nova` Klatt-style synthesis
+ `audio_speak.nova` espeak/aplay escalation). The STT half is the framework
this audit accompanies — `src/io/transducers/stt_seam.nova` is the
pluggable-backend surface and `scripts/transcribe.sh` is the
runtime-detected subprocess shim. This document mirrors `WIN32_AUDIT.md` /
`MACOS_AUDIT.md` / `TLS_AUDIT.md` / `WASM_AUDIT.md` — the realistic path,
not a promise.

## Why STT is structurally hard

A microphone is not a typewriter. The raw signal is non-stationary noise
(room tone, fans, traffic, the speaker breathing) plus the voiced segments
the agent actually cares about. The voiced segments themselves vary in
fundamental frequency (60-300 Hz), formant transitions, speech rate, accent,
prosody, coarticulation across word boundaries, and channel response (mic
placement, codec). Decoding "fever" from a waveform demands either (a) a
brute-force deep-learning acoustic model trained on thousands of hours
(Whisper, wav2vec 2.0, Conformer-RNN-T), (b) a classical pipeline of
voice-activity detection + MFCC frontend + GMM-HMM acoustic model + n-gram
language model (the pre-2017 Kaldi/HTK shape), or (c) a pure phoneme
recognizer that hands the phoneme stream up to a word-binding layer in the
KG.

None of (a), (b), (c) is a weekend's work. (a) presupposes a trained model
(hundreds of MB), an FFT, a transformer kernel, and an attention mechanism —
NOVA has none of the four. (b) presupposes a Viterbi search through a
weighted FST, a Gaussian-mixture EM training pipeline, and at least a small
corpus to train on. (c) presupposes a phoneme dictionary (we have one —
`src/language/phoneme_atoms.nova`, ADR-0015) plus an MFCC frontend plus
some form of acoustic matching plus a phoneme-to-word binder. (c) is the
only pure-NOVA option that doesn't import an LLM, and it's still a
multi-month engineering project. **Pure-NOVA STT is unrealistic this
decade.**

The sandbox CrossEngin tests against has no microphone hardware and none
of the standard CPU acoustic toolchains installed (no `whisper-cli`, no
`vosk-transcriber`, no `arecord`, no `parecord`). A real implementation is
not testable here. This audit is the design; the framework is what
`stt_seam.nova` ships now.

## Realistic options for CrossEngin, in increasing difficulty

1. **Subprocess shim to whisper.cpp or vosk** *(easiest)*. The agent
   delegates STT to an external CLI: pass it a WAV path, read the
   transcript back from stdout. Same shape as `scripts/learn.sh`'s curl
   shim for HTTPS — a thin escape hatch over a domain we don't intend to
   write ourselves. Latency on whisper.cpp (CPU) is ~1-2 s per 5-second
   utterance; vosk is closer to real-time for short queries.
   `scripts/transcribe.sh` is exactly that shim.

2. **WASM-compiled Whisper in-process** *(medium)*. Once P2.7 WASM matures
   the agent can host a Whisper-WASM blob (~50-150 MB tiny.en quantized)
   inside its own address space. No `fork`/`exec` cost, no subprocess
   ABI, deterministic memory budget. The blocker is P2.7 WASI — without
   it the WASM blob has no way to call back into the agent's
   `stt_register_backend` seam. Same shape as `WASM_AUDIT.md` envisions
   for general-purpose user code in NOVA.

3. **Phoneme classifier in NOVA** *(hardest)*. The agent's language KG
   already carries phoneme atoms (ADR-0015 — 33 distinct labels covering
   the English ARPABET inventory, used in P2.6 for TTS). A pure-NOVA STT
   could MFCC-window the input WAV (FFT on 25 ms frames at 10 ms hop) and
   matched-filter each frame against the phoneme inventory's expected
   formant profile (mirror of `_phoneme_formants` in `audio_synth.nova`).
   The classifier emits a phoneme stream; an HMM-like or simple
   pronunciation-dictionary lookup binds runs of phonemes to word atoms.
   No deep learning, no external dependencies — just FFT, MFCC, and
   matched filtering, all of which fit in a few thousand lines of NOVA
   with care for the codegen pointer-threshold (gotcha #11). Multi-month
   effort but ADR-0014-aligned and ADR-0015-consistent.

## WASI / Linux audio-capture surface

| Platform | Capture command | Output |
|----------|----------------|--------|
| Linux + ALSA | `arecord -d 5 -q -f cd /tmp/ce_input.wav` | 44.1 kHz 16-bit stereo WAV |
| Linux + PulseAudio | `parecord --file-format=wav /tmp/ce_input.wav` | sane defaults |
| Linux native | `libasound` via dlopen | PCM frames into a NOVA buffer (no NOVA binding yet) |
| macOS | `say` (TTS), `sox -d -t wav /tmp/ce_input.wav` | macOS native (Darwin) |
| Windows | `Sndrec32`, `powershell SpeechRecognitionEngine` | system-dependent |
| Browser / WASM | `getUserMedia` + AudioBuffer | `wasi-snapshot-preview1` (not yet standardized) |

For the subprocess path we let the operator parametrize the capture
command via `CE_AUDIO_CAPTURE_CMD` rather than baking a platform branch
into NOVA. The default in this sandbox would be `arecord -d 5 -q -f cd
/tmp/ce_input.wav`; on macOS one would set
`CE_AUDIO_CAPTURE_CMD='sox -d -t wav /tmp/ce_input.wav trim 0 5'`.

## `scripts/transcribe.sh` contract

Input: one argument, the absolute path to a WAV file (any sample rate,
the backend re-samples internally). Output: the transcript on stdout,
one line. Exit 0 on success **including the "no backend installed"
fallback** — a missing whisper.cpp must not be a fatal error for the
caller; the seam routes to the placeholder "[stt: no backend
installed]" instead. Standard error carries diagnostics. The script
probes for backends in order (highest quality first):

1. `whisper-cli` (the official whisper.cpp CLI) — `whisper-cli -f WAV
   --output-txt`
2. `main` (legacy whisper.cpp binary name) — `main -m
   models/ggml-tiny.en.bin -f WAV --no-prints`
3. `vosk-transcriber` (Python vosk wrapper) — `vosk-transcriber -i WAV`
4. Fallback — `echo "[stt: no backend installed]"`

Install commands documented in the script header:

```sh
# whisper.cpp (CPU): git clone, make, download ggml-tiny.en.bin
# vosk: pip install vosk vosk-transcriber + download a small model
```

## Latency budget

For a conversational agent ("/ask <spoken phrase>" -> transcript ->
percept), end-to-end STT latency must sit comfortably under **500 ms**
to feel responsive. Reality on the listed backends:

| Backend | 5-second utterance | 10-second utterance |
|---------|---------------------|---------------------|
| whisper.cpp tiny.en (CPU, 1 thread) | 1.0-2.0 s | 2.5-5.0 s |
| whisper.cpp base.en (CPU, 4 threads) | 0.4-0.8 s | 1.0-2.0 s |
| vosk small-en model | 0.05-0.15 s | 0.1-0.3 s |
| pure-NOVA phoneme classifier (projection) | 0.3-0.6 s | 0.6-1.2 s |

For the subprocess path, vosk hits the 500 ms target on commodity
hardware; whisper.cpp tiny.en is over budget but produces noticeably
better transcripts. The framework treats latency as a backend choice,
not a constraint.

## Recommended path

* **Short term (this session and the next 1-2):** the subprocess shim.
  Land `stt_seam.nova` + `scripts/transcribe.sh`. Document the install
  steps. Defer the integration test until microphone hardware is
  available.
* **Medium term:** the phoneme classifier (#3). Aligned with ADR-0014
  (no LLM in cognition; STT is modality-bridge, but the bridge is pure
  NOVA), aligned with ADR-0015 (phoneme atoms exist for this reason),
  and unblocks the no-network deployment target. Multi-month.
* **Long term / once P2.7 WASM lands:** the WASM Whisper path (#2) as a
  drop-in higher-quality backend behind the same `stt_register_backend`
  seam. The pluggable shape means the call sites — `stream_audio.nova`,
  the chat's eventual `/listen`, the daemon's idle-poll audio source —
  don't change.

## Wall-clock estimates per option

| Option | Wall-clock |
|--------|-----------|
| Subprocess shim (#1) — this session | **3-5 days** |
| WASM Whisper integration (#2) — depends on P2.7 | **2-3 weeks once P2.7 ships** |
| Pure-NOVA phoneme classifier (#3) | **3-6 months** |

The subprocess shim is what landed in this session. The pluggable seam
means upgrading to #2 or #3 later replaces one function pointer, not
the surrounding integration.

## Cross-references

* `src/io/transducers/stt_seam.nova` — the pluggable STT seam (P2.5).
* `src/io/transducers/stream_audio.nova` — env-gated audio-capture
  source (P2.5; the `CE_AUDIO_CAPTURE_CMD` + `CE_STT_BACKEND`
  consumer).
* `scripts/transcribe.sh` — the subprocess shim with backend
  auto-detection.
* `src/io/effectors/audio_synth.nova` / `audio_speak.nova` — the TTS
  half (P19 + P2.6) this STT half pairs with.
* `src/language/phoneme_atoms.nova` (ADR-0015) — the phoneme inventory
  the pure-NOVA classifier (#3) would target.
* `nova-deps.toml` entry #14 — upstream tracker for the modality
  bridge.
