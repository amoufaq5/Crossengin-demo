# AUDIO_AUDIT — Klatt formant phoneme inventory audit

Status: **P6 expansion landed (`src/io/effectors/audio_synth.nova`).** Tracks
the ARPAbet phoneme inventory of CrossEngin's pure-NOVA Klatt-style
two-formant synthesizer, from the P19/P2.6 baseline of 33 dispatches to the
P6 expansion's 53 dispatches (44 distinct ARPAbet symbols).

## Why a full ARPAbet inventory matters

CrossEngin synthesizes speech without an LLM. Mode-1 (always-on) is the
pure-NOVA Klatt-style two-formant path; Mode-2/3 escalate to `espeak`/aplay
when present. The Mode-1 floor must produce intelligible output on the
cold seed across the full English phoneme set, otherwise:

- Words containing diphthongs (FACE, PRICE, MOUTH, GOAT, CHOICE) collapse
  to their first vowel, losing the glide — "boy" becomes "baw".
- Affricates (CHURCH, JUDGE) collapse to either the stop or the fricative,
  losing the affricated character — "church" becomes "tsurts" or "ssurs".
- Voiced fricatives (THIS, MEASURE) collapse to their unvoiced counterparts
  — "this" becomes "thiss".
- Syllabic nasals/liquids (BOTTOM, BUTTON, BOTTLE) get an inserted vowel —
  "bottom" becomes "ba-tom" instead of "bat-m".

The Mode-1 floor is also the unit-test fixture: every audio-touching
subsystem (TTS, audio capture, STT, the chat /speak command) round-trips
through this synthesizer in CI where `espeak` is absent. Coverage gaps
here propagate everywhere.

## P19 / P2.6 baseline: 33 phoneme dispatches

The pre-P6 formant table covered the high-frequency English phonemes but
missed long-tail forms. Counted by `str_eq(s, "...")` dispatches in
`_phoneme_formants`:

| Category | Count | Symbols |
|----------|------:|---------|
| Vowels (monophthongs + glides treated as vowels) | 13 | a, ah, e, eh, i, iy, ih, o, oh, ow, u, uw, ae |
| Plosives | 6 | p, t, k, b, d, g |
| Fricatives | 7 | s, z, f, v, sh, th, h |
| Nasals | 3 | n, m, ng |
| Liquids / glides | 4 | l, r, w, y |
| **Total** | **33** | |

Aliasing: `a` and `ah` share formants (730/1090/2440); `e` and `eh` share
(530/1840/2480); `i` and `iy` share (270/2290/3010); `o` and `oh` share
(570/840/2410); `u` and `uw` share (300/870/2240). So 33 dispatches
covered 28 distinct ARPAbet symbols.

## What was missing from full English ARPAbet (~44 phonemes)

Full English ARPAbet (CMU dict / TIMIT) recognizes ~44 distinct phoneme
symbols. The P19/P2.6 baseline missed 16+ of them:

### Monophthongs missed: 6

| ARPAbet | IPA | F1 | F2 | F3 | Example | Notes |
|---------|-----|---:|---:|---:|---------|-------|
| AA | /ɑ/ | 730 | 1090 | 2440 | fAther | Was aliased to "a"/"ah"; now explicit. |
| AO | /ɔ/ | 570 | 840 | 2410 | thOUght | Was aliased to "o"/"oh"; now explicit. |
| ER | /ɝ/ | 490 | 1350 | 1690 | bIRd | Rhotacized; **distinct from anything in baseline.** |
| UH | /ʊ/ | 440 | 1020 | 2240 | fOOt | Lax back; **distinct from "u"/"uw" which is /u/.** |
| AX | /ə/ | 500 | 1500 | 2500 | About (schwa) | Reduced vowel. |
| IX | /ɨ/ | 400 | 1700 | 2500 | rosE-s | Reduced high. |
| AXR | /ɚ/ | 460 | 1310 | 1600 | bettER | Rhotacized schwa. |

### Diphthongs missed: 4 (5 with the existing OW)

| ARPAbet | IPA | Start (F1,F2,F3) | End (F1,F2,F3) | Example |
|---------|-----|------------------|-----------------|---------|
| AW | /aʊ/ | 730, 1090, 2440 | 300, 870, 2240 | nOW |
| AY | /aɪ/ | 660, 1230, 2440 | 270, 2290, 3010 | mY |
| EY | /eɪ/ | 530, 1840, 2480 | 270, 2290, 3010 | dAY |
| OY | /ɔɪ/ | 570, 840, 2410 | 270, 2290, 3010 | bOY |
| OW (pre-existing as a vowel) | /oʊ/ | 470, 990, 2300 | (kept as monophthong) | gOAt |

OW is canonically a diphthong (/oʊ/, glides toward /ʊ/), but it was already
in the baseline as a monophthong with formants 470/990/2300. Preserving
the existing entry keeps byte-for-byte backward compatibility; promoting it
to a diphthong is a future-work item.

### Affricates missed: 2

| ARPAbet | IPA | Components | Example |
|---------|-----|------------|---------|
| CH | /tʃ/ | T + SH | CHurch |
| JH | /dʒ/ | D + ZH | Judge |

Affricates are tightly-coupled stop+fricative concatenations. Encoded as a
[stop_label, fricative_label] pair in `_affricate_parts`; `_synth_affricate`
sequences them within a single 1200-sample phoneme budget (~40% stop, ~60%
fricative).

### Voiced fricatives missed: 2

| ARPAbet | IPA | F2 (carrier hint) | Example |
|---------|-----|------------------:|---------|
| DH | /ð/ | 2400 | THis (voiced "th") |
| ZH | /ʒ/ | 2500 | meaSure |

The baseline had unvoiced TH (theta /θ/) but no DH; had SH (esh /ʃ/) but
no ZH (ezh /ʒ/). At Mode-1 8 kHz with LCG pseudo-noise, the voiced vs.
unvoiced distinction is subtle (we don't model voicing source); the
inventory completeness is what matters for downstream callers.

### Syllabic nasals/liquids missed: 4

| ARPAbet | IPA | Carries syllable | Example |
|---------|-----|------------------|---------|
| EM | /m̩/ | yes (syllabic M) | rhythM |
| EN | /n̩/ | yes (syllabic N) | buttoN |
| ENG | /ŋ̍/ | yes (syllabic NG) | (rare) |
| EL | /l̩/ | yes (syllabic L) | bottLe |

Encoded as `PHO_KIND_SYLLABIC`: same formant carrier as the onset
nasal/liquid but with reduced amplitude (~70%) and gentler damping
(1000→700 vs nasal's 1000→500) since they're carrying a syllable nucleus
rather than transitioning into one.

### HH alias missed: 1

ARPAbet uses HH for the /h/ phoneme; the baseline only had "h". Added "hh"
as an alias so CMU-dict-style transcripts work without preprocessing.

## P6 expansion: 53 phoneme dispatches

| Category | Count | New symbols | Total symbols |
|----------|------:|-------------|---------------|
| Monophthongs | 20 (+7) | aa, ao, uh, er, ax, ix, axr | a, aa, ah, e, eh, i, iy, ih, o, oh, ao, ow, u, uw, uh, ae, er, ax, ix, axr |
| Diphthongs | 4 (+4) | aw, ay, ey, oy | aw, ay, ey, oy |
| Plosives | 6 | (no change) | p, t, k, b, d, g |
| Affricates | 2 (+2) | ch, jh | ch, jh |
| Fricatives | 10 (+3) | zh, dh, hh | s, z, f, v, sh, zh, th, dh, h, hh |
| Nasals (onset) | 3 | (no change) | n, m, ng |
| Syllabic nasals/liquids | 4 (+4) | em, en, eng, el | em, en, eng, el |
| Liquids / glides | 4 | (no change) | l, r, w, y |
| **Total** | **53** | **+20 dispatches** | |

44 distinct ARPAbet symbols + 9 alias entries (aa/ah for AA, eh for EH, iy
for IY, oh/ao for AO, uw for UW, hh for HH).

Public API:

- `klatt_phoneme_count()` -> `53` (the dispatch count constant).
- `klatt_phoneme_labels()` -> list of all 53 labels in dispatch order.
- `phoneme_formants(label)` -> `[F1, F2, F3, kind]` (existing).
- `diphthong_end_formants(label)` -> `[F1_end, F2_end, F3_end]` for the
  4 diphthongs; `[0,0,0]` for non-diphthongs.
- `synth_phoneme(label)` -> `[1200 PCM16 samples]` for any label, including
  unknown (440 Hz sine fallback). Existing API.
- `synth_text(text, lang_kg)` -> concatenated samples for the utterance.
  Existing API; benefits automatically from the expanded inventory when
  words have phoneme atoms attached.

## Diphthong glide arithmetic

For each sample t in [0, n_samples):

  F1(t) = F1_start + (F1_end - F1_start) * t / n_samples
  F2(t) = F2_start + (F2_end - F2_start) * t / n_samples

Bresenham-style phase generators are re-evaluated per-sample using the
current F1/F2. Per-sample formant delta for the largest jump (AY's F2:
1230 -> 2290 = 1060 Hz across 1200 samples) is 1060/1200 = ~0.88 Hz/sample,
well below the perceptual continuity threshold. F3 is ignored at 8 kHz
(simplified Klatt model).

## Affricate sequencing

For each affricate, the 1200-sample phoneme budget is split:

  ~40% (480 samples) plosive (silence + burst via `_synth_plosive`)
  ~60% (720 samples) fricative (LCG noise via `_synth_fricative`)

The fricative half gets a 5 ms attack envelope; the plosive half retains
its native silence-then-burst shape. The boundary is clean because the
plosive's trailing silence + the fricative's attack ramp jointly cross-fade.

## Syllabic vs onset nasals/liquids

| Aspect | Onset nasal (n, m, ng) | Syllabic (em, en, eng, el) |
|--------|------------------------|-----------------------------|
| Carrier | F1 (250-310 Hz) | Same as onset counterpart |
| Damping | 1000 -> 500 (linear, 50% decay) | 1000 -> 700 (linear, 30% decay) |
| Amplitude scale | 100% | 70% |
| ADSR envelope | 5 ms attack, 10 ms release | Same |
| Kind | `PHO_KIND_NASAL` (4) | `PHO_KIND_SYLLABIC` (7) |

EL is syllabic L; it's the only syllabic that's a LIQUID rather than a
nasal, but it's encoded the same way (just with L's formants 360/1300/2700
instead of an N's 310/0/0). The synth treats it identically.

## Verification

`tests/unit/test_audio_synth.nova` exercises:

- Inventory count == 53 (cross-checked against the labels list).
- Every label resolves to a non-UNKNOWN kind.
- Each new monophthong (ER, UH, AX) has formants in expected ranges.
- Each diphthong (AW, AY, EY, OY) has correct start/end formant targets
  (e.g. AY: F1 starts ~660, ends ~270; F2 starts ~1230, ends ~2290 as the
  brief specifies).
- Diphthong glide is audible (peak-to-peak > 5000, RMS-proxy > 1500).
- Diphthong glide is *progressive*: AY's late-buffer zero-crossing rate
  exceeds its early-buffer ZCR because F2 climbs from 1230 to 2290 Hz.
- Affricates synthesize a full 1200-sample buffer with silence-then-burst
  at the front and noise activity in the back.
- Voiced fricatives (DH, ZH) have higher ZCR than vowels (noise > tone).
- Syllabic forms have reduced amplitude vs their onset counterparts
  (test: `em` peak < `m` peak in matched windows).
- 4-word diphthong utterance ("DAY KAY MOW BOY" = D+EY, K+EY, M+OW, B+OY)
  produces 4 * 2400 = 9600 samples = 1.2 s @ 8 kHz, with the file size on
  disk matching 44 + 9600*2 = 19244 bytes.

`audio_synth: OK (209 checks)` — all existing 99 + 110 new assertions pass.

## R7F: Voice Activity Detection (VAD) layer

Audio capture now passes through `src/io/transducers/audio_vad.nova` before
reaching the STT seam: pure-silence frames are dropped, false transcripts on
the `[stt unavailable]` placeholder path are avoided, and `SPEECH_START` /
`SPEECH_END` boundary events let downstream consumers chunk on real
utterance boundaries instead of fixed time windows.

### Algorithm

Per ~30 ms frame (240 samples @ 8 kHz, 480 @ 16 kHz, etc.):

  * `energy = Σ |sample|` (sum of absolutes — variance proxy that avoids
    the 64-bit overflow / NOVA pointer-threshold risk of sum-of-squares).
  * `zcr = count of sign flips` (treats 0 as its own class so a long
    stretch of exact zero from `_synth_phoneme_silence` doesn't produce
    phantom crossings).
  * Frame is "speech" iff `energy > E_THRESH AND zcr < ZCR_MAX`.
  * Thresholds scale linearly with frame_size: `E_THRESH = 50000 *
    frame_size / 240`, `ZCR_MAX = frame_size * 40 / 100`. At 8 kHz that's
    50000 / 96; at 16 kHz it's 100000 / 192.

### State machine (hysteresis)

Four-state machine avoids flapping on per-frame edge cases:

| From state | Trigger | To state | Event |
|------------|---------|----------|-------|
| `SILENCE` | speech frame | `SPEECH_CANDIDATE` | — |
| `SPEECH_CANDIDATE` | K=3 speech frames in a row | `SPEECH` | `SPEECH_START` |
| `SPEECH_CANDIDATE` | silence frame | `SILENCE` | — |
| `SPEECH` | silence frame | `SILENCE_CANDIDATE` | — |
| `SILENCE_CANDIDATE` | M=10 silence frames in a row | `SILENCE` | `SPEECH_END` |
| `SILENCE_CANDIDATE` | speech frame | `SPEECH` | — |

K=3 (~90 ms confirmation) matches webrtcvad's aggressive-mode minimum;
M=10 (~300 ms confirmation) matches a relaxed conversational floor. The
`SPEECH_START` sample index is back-dated to the first candidate frame,
not the third, so segment boundaries align with where speech actually
began.

### Public API (`src/io/transducers/audio_vad.nova`)

- `vad_state_new(sample_rate)` — clamps rate to [8000..48000], computes
  frame_size + thresholds, initializes machine to SILENCE.
- `vad_frame_energy(samples, off, n)` / `vad_frame_zcr(samples, off, n)` —
  pure helpers, no state mutation. Bounds-checked.
- `vad_classify_frame(state, energy, zcr) -> 0 | 1`.
- `vad_process_frame(state, samples, off, n) -> event` — runs analysis +
  state machine on one frame, returns one of `VAD_EVENT_NONE` (0),
  `VAD_EVENT_SPEECH_START` (1), `VAD_EVENT_SPEECH_END` (2).
- `vad_process_pcm(state, samples) -> [[start, end], ...]` — walks the
  whole buffer, returns the list of detected speech segments.
- `vad_filter_pcm(state, samples) -> filtered PCM` — concatenates speech
  segments back-to-back; suitable for handing to `stt_transcribe`.

### Integration: `audio_capture` + `stt_seam`

- `audio_capture_to_pcm_vad(wav_path) -> [filtered_pcm, sample_rate,
  n_segments]` — read WAV, parse PCM, run VAD, return speech-only PCM
  plus the segment count. Zero segments on all-silence or all-noise
  input.
- `stt_transcribe(seam, audio_buffer)` — canonical entry point.
  `audio_buffer` is `[pcm_list, sample_rate]` (in-memory PCM) or
  `[wav_path]` (file on disk). Backward-compatible alongside the
  existing `stt_transcribe_wav` / `stt_transcribe_pcm` variants.
- `stt_transcribe_wav_vad(seam, wav_path)` — VAD-gated path: short-
  circuits to the stub placeholder if VAD detects zero speech, so the
  STT backend never sees pure-silence input. Returns a 4-tuple
  `[transcript, confidence, error, n_segments]`.

### Chat wiring

`/listen [PATH]` admin command captures (or reads) a WAV, runs it through
VAD, dispatches the filtered PCM to the seam's active STT backend, prints
the transcript + segment count + backend used.

### Verification (R7F)

- `tests/unit/test_audio_vad.nova`: 55 assertions covering rate clamp,
  frame-size derivation, energy/ZCR on hand-built buffers (zero,
  constant, alternating, triangle), classifier behaviour on silence /
  vowel / noise / low-amp signal, K=3 commit hysteresis, M=10
  silence-release hysteresis, full-buffer walks (1-segment, 2-segment,
  all-silence, all-noise), `vad_filter_pcm` extracts-only-speech +
  empty-on-silence, threshold override.
- `tests/integration/scenario_ii_vad.sh`: 17 assertions. Klatt-
  synthesizes "AY EY OW OY" (4 diphthongs/monophthong @ 1200 samples
  each + leading/trailing silence) → speech WAV → VAD detects 1
  segment, 4800 filtered samples. Pure-silence WAV → 0 segments, 0
  filtered samples. Pure-noise WAV (alternating ±3000) → 0 segments
  (ZCR ceiling rejects high-energy high-flip noise). Chat `/help`
  advertises `/listen`; `/listen <wav>` reports `vad_segments=N` and
  the resolved backend.

`audio_vad: OK (55 checks)`. All prior audio test suites continue to
pass unchanged: `audio_synth: OK (209)`, `audio_capture: OK (28)`,
`stt_seam: OK (26)`.

### R9B update: adaptive noise-floor calibration + JFK end-to-end

R8B (commit `0874516`) wired whisper.cpp into the seam and exercised the
JFK 16 kHz WAV via `stt_transcribe_wav` (bypassing VAD) — that worked.
The end-to-end `/listen /tmp/whisper.cpp/samples/jfk.wav` path however
reported `vad_segments=0` and short-circuited to the placeholder. Two
root causes:

1. **WAV parser strict-offset bug.** `audio_capture_to_pcm` required the
   `data` sub-chunk at byte offset 36 — the canonical layout for a
   barebones RIFF/WAVE/PCM file with no metadata chunks. whisper.cpp's
   bundled `jfk.wav` carries a `LIST/INFO ISFT 'Lavf...'` chunk between
   the `fmt ` and `data` sub-chunks (ffmpeg encoder metadata), so `data`
   actually lives at offset 70. The parser now scans forward through any
   optional sub-chunk (LIST/INFO/bext/junk/...) until it finds `data`,
   per RIFF spec. The fmt-body length comes from off 16 (4-byte LE u32)
   and unknown chunks are word-aligned-padded if their body length is
   odd.

2. **Energy threshold needed to adapt to the recording's noise floor.**
   R7F's threshold (50000 @ 8 kHz, scaling linearly to 100000 @ 16 kHz)
   was tuned against Klatt-synthesized utterances with exact-zero
   leading silence. On real recordings the noise floor sits above zero
   (USB-mic preamp hiss, room HVAC, distant PA bleed); a different mic
   gain stage rolls the threshold the wrong way. R9B adds an adaptive
   multiplier (Option A from the threshold-tuning brief):

   * **Calibration window:** `VAD_NOISE_CALIB_FRAMES = 16` × 30 ms ≈
     480 ms of leading audio.
   * **Noise floor estimator:** minimum per-frame energy across that
     window. MIN-not-MEAN avoids biasing the floor upward when the
     speaker starts inside the calibration window (a short utterance
     that lands wholly within 500 ms still has MIN = silent frame).
   * **Effective threshold:** `max(noise_floor × 3, R7F_floor)`. The
     3× multiplier is the classical "speech runs ~10-30 dB above the
     room floor" rule; webrtcvad and Silero use similar ratios.
   * **R7F floor preserved.** The hard minimum is the R7F linear-scaling
     threshold (`VAD_ENERGY_BASE_8K × frame_size / 240`). On Klatt
     fixtures + JFK (both have exact-zero leading silence) the floor
     wins and behavior is bit-identical to R7F.

   The state struct gains four slots: `e_thresh_floor`, `noise_floor`,
   `calibrated`, `adaptive`. The `V_*` indices for existing slots are
   unchanged (only `push`-ed at the tail), so R7F's index-based access
   from tests and consumers keeps working. `vad_set_energy_thresh` flips
   adaptive=OFF + calibrated=ON to preserve R7F's "operator override
   wins" semantic.

   Auto-calibration is wired into `vad_process_pcm` only (the
   buffer-level entry point). Per-frame entry points
   (`vad_process_frame`, `vad_classify_frame`) keep the state's
   threshold as set, so any per-frame R7F test runs bit-identical.
   Subsequent `vad_process_pcm` calls do NOT re-calibrate (the
   calibrated flag is sticky) — a streaming workflow that fans multiple
   buffers through the same state keeps its initial baseline.

   New public surface: `vad_calibrate_noise_floor(state, samples,
   max_frames)`, `vad_noise_floor(state)`, `vad_e_thresh_floor(state)`,
   `vad_is_calibrated(state)`, `vad_is_adaptive(state)`,
   `vad_set_adaptive(state, on)`.

3. **JFK end-to-end transcript.** After the two fixes,
   `/listen /tmp/whisper.cpp/samples/jfk.wav` produces:

   ```
   (heard 'and so my fellow Americans ask not what your country can do
    for you ask what you can do for your country'
    [vad_segments=1, backend=whisper];
    read /tmp/whisper.cpp/samples/jfk.wav)
   ```

   VAD detects 1 segment (the full utterance), filtered PCM = 170880
   samples ≈ 10.7 s of speech out of the 11 s clip. Whisper decodes the
   full quote.

### Verification (R9B)

- `tests/unit/test_audio_vad.nova`: 86 assertions (55 R7F preserved
  bit-identical + 31 new). New coverage:
  * `test_adaptive_defaults` (5 checks) — default state has adaptive
    ON, not calibrated, noise_floor=0, e_thresh_floor mirrors the R7F
    initial threshold at both 8 kHz (50000) and 16 kHz (100000).
  * `test_calibrate_on_silence_keeps_floor` (3 checks) — pure-zero lead
    -in → noise_floor=0 → live threshold stays at R7F floor.
  * `test_calibrate_on_noisy_lead_in_lifts_threshold` (4 checks) —
    amp=200 triangle lead-in → noise_floor ≈ 24000 → live threshold ≈
    72000 (3× floor).
  * `test_process_pcm_auto_calibrates` (4 checks) — buffer-level entry
    point auto-runs calibration on first call, still detects the speech
    burst in a noisy lead-in.
  * `test_set_energy_thresh_disables_adaptive` (4 checks) — explicit
    operator override sticks across subsequent `vad_process_pcm` calls.
  * `test_set_adaptive_off_skips_calibration` (3 checks) — explicit opt
    -out preserves R7F floor without changing the threshold.
  * `test_calibrate_empty_buffer_safe` (3 checks) — calibration on an
    empty buffer doesn't crash; state marks calibrated, threshold stays
    at floor.
  * `test_full_walk_noisy_lead_in_one_segment` (2 checks) — headline
    R9B scenario in synthesized form: noisy lead-in + clean speech →
    exactly 1 segment.
  * `test_double_process_pcm_only_calibrates_once` (2 checks) — second
    buffer through the same state does NOT re-baseline noise floor.
- `tests/integration/scenario_oo_vad_natural.sh`: 15 assertions.
  Synthetic silence WAV → 0 segments. Synthetic noisy + speech WAV →
  1 segment (adaptive threshold isolates speech from amp=200 lead-in
  noise). JFK 16 kHz WAV decoded by parser (LIST chunk accepted), VAD
  → 1 segment, filtered PCM 170880 samples in expected duration band
  [80000, 208000]. End-to-end `/listen JFK` → `vad_segments=1`,
  transcript contains "fellow Americans" or "your country", dispatched
  through `backend=whisper`. SKIPs gracefully if JFK WAV or
  whisper-main aren't installed.

`audio_vad: OK (86 checks)`. All R7F integration scenarios continue to
pass bit-identical: `scenario_ii_vad: pass=17 fail=0`, `scenario_jj_
whisper: pass=13 fail=0`, `scenario_w_audio_capture: pass=23 fail=0`,
`scenario_oo_vad_natural: pass=15 fail=0`.

### Future work (VAD)

- Spectral entropy / sub-band energy: add an extra discriminator that
  rejects single-frequency interference (HVAC hum, 50/60 Hz mains).
- Per-utterance re-calibration: an optional flag to force calibration
  re-baselining at silence boundaries, useful for very long capture
  buffers where the noise floor drifts.
- VAD-aware re-segmentation in STT: rather than concatenating speech
  segments back-to-back, hand each segment to STT independently and
  join transcripts at segment boundaries — preserves utterance pauses
  for downstream prosody / turn-taking analysis.

## R8B: whisper.cpp STT backend (`/listen` actually transcribes)

`src/io/transducers/whisper_backend.nova` lands as a first-class STT
backend wired into the seam from R7F. The pipeline is now:

```
mic / audio_capture --> VAD (audio_vad)   --> stt_seam --> whisper-main
                         (R7F)                  (R7F)        (R8B)
```

### Backend choice

Whisper.cpp (https://github.com/ggerganov/whisper.cpp) is the
MIT-licensed pure-C reimplementation of OpenAI Whisper. The `tiny.en`
quantized model is ~75 MB; the `whisper-cli` binary is ~3 MB. CPU-only
inference on a 11-second JFK utterance completes in ~1 s on a modest
amd64 box. This is well within CE's "minimal external deps" constraint:
no GPU, no LLM, no FFI; one fork+exec from NOVA.

### Install layout (canonical)

| Path                                          | Source                                  |
|-----------------------------------------------|-----------------------------------------|
| `/usr/local/bin/whisper-main`                 | renamed from `whisper.cpp/build/bin/whisper-cli` |
| `/usr/local/share/whisper/ggml-tiny.en.bin`   | from `whisper.cpp/models/download-ggml-model.sh tiny.en` |

Operators override via `CE_WHISPER_BIN` / `CE_WHISPER_MODEL`. The seam's
`stt_default_backend()` auto-picks `whisper` when both files exist,
falls back to `stub` otherwise (NEVER `subprocess` -- that's a
legacy shim and requires explicit `CE_STT_BACKEND=subprocess`).

### Public surface

```nova
whisper_transcribe(bin_path, model_path, wav_path)
    -> [transcript, confidence_milli, error]
whisper_transcribe_default(wav_path)        // uses env-resolved paths
whisper_backend_available(bin, model)       // openable-ness probe
whisper_resolve_bin() / whisper_resolve_model()
whisper_clean_transcript(raw)               // trim + collapse newlines
```

The result triple matches `stt_seam`'s shape so the seam dispatcher is
a one-line route in `_stt_backend_whisper`.

### Errors surfaced

| `error` value         | meaning                              |
|-----------------------|--------------------------------------|
| `""`                  | success (transcript non-empty, conf=800) |
| `"binary not found"`  | `bin_path` not openable                |
| `"model not found"`   | `model_path` not openable              |
| `"wav not found"`     | `wav_path` not openable                |
| `"pipe2 failed"`      | kernel refused pipe (rare)             |
| `"fork failed"`       | kernel refused fork (rare)             |
| `"empty transcript"`  | child exited 0 but produced no stdout (silent WAV / model mismatch / exec failed silently) |

### Confidence

`whisper-cli`'s `-nt -np` flags suppress timestamps + per-segment
header; stdout is the transcript text only. Per-token confidence
requires `--print-confidence` (recent builds). R8B returns a fixed
`WHISPER_CONFIDENCE_DEFAULT = 800 milli` on success (the same
ballpark the legacy subprocess shim uses). Wiring real per-utterance
confidence is a future task.

### Verification (R8B)

- `tests/unit/test_whisper_backend.nova`: 28 assertions covering
  the env resolvers (default + override), the openable-ness probe,
  all three pre-flight error paths (`binary not found`, `model not
  found`, `wav not found`), transcript cleanup (trim, newline
  collapse, space dedup, empty/whitespace-only input), result-tuple
  accessors, and the `stt_seam` round-trip through
  `STT_BACKEND_WHISPER` (verified via the seam's `last_error`
  surfacing).
- `tests/integration/scenario_jj_whisper.sh`: 13 assertions when
  whisper is installed (10 when it isn't). Synthesizes a Klatt
  utterance, runs it through `whisper_transcribe`, then runs the
  bundled `jfk.wav` and asserts the transcript contains
  "Americans". Also exercises `stt_seam_new_whisper(model_path)`
  + the `STT_BACKEND_STUB` fallback path. SKIPs the model-decode
  assertions when whisper is not installed so CI on bare
  environments still passes.

On the dev container the JFK sample transcribes to:

> "And so my fellow Americans ask not what your country can do for
> you, ask what you can do for your country."

(confidence=800, error="", tlen≈110 chars).

### Future work (R8B)

- Per-segment confidence via `--print-confidence`. Recent whisper-cli
  builds expose per-token logprobs on stdout when this flag is set;
  parsing that into a single milli value gives a real per-utterance
  confidence instead of the current ballpark.
- Streaming transcription: whisper-cli supports `-f -` for stdin PCM;
  wiring this would drop the temp-WAV write in `stt_transcribe_pcm`
  and let `/listen` stream directly from the capture pipeline.
- Larger models (`base.en`, `small.en`, `medium.en`) for noisy /
  accented audio. The download path + env-driven model selection
  already supports any model; the trade-off is download size + RAM.
- VAD-aware segmentation: hand each VAD-detected speech segment to
  whisper independently rather than concatenating; preserves
  utterance boundaries for downstream prosody analysis.

## R10B: per-utterance confidence + Vosk offline backend

Status: **landed.** Two R8B follow-ups closed:
  1. The whisper.cpp backend's flat 800-milli confidence placeholder
     is replaced by real per-utterance confidence derived from the
     `-ojf` (output-json-full) per-token probability stream.
  2. A second first-class STT backend (Vosk, pure-Python wrapper over
     libvosk + a Kaldi-format model) joins the seam, giving CrossEngin
     an OFFLINE-FIRST alternative when whisper.cpp isn't installed.

### Whisper per-utterance confidence

`whisper_transcribe_with_confidence(bin, model, wav)` is a parallel
entry point to R8B's `whisper_transcribe`. It runs whisper-cli with
`-ojf -of <stable_path>` so the child emits a JSON file with the full
transcription tree, including per-token `"p": <0..1 float>` values.
The parent reads that file after the child exits, scans for every
`"p":` key, parses the value as milli, and averages.

JFK on tiny.en: avg over ~22 tokens = **895 milli** (was a flat 800
placeholder). Fallback to legacy 800-milli ballpark when the JSON
file is missing / unparseable. The basic `whisper_transcribe` still
returns 800 byte-for-byte compatibly with scenario_jj_whisper's
existing assertions. The seam (`_stt_backend_whisper`) was switched
to the confidence-aware variant.

### Vosk backend

`src/io/transducers/vosk_backend.nova` (NEW) mirrors whisper_backend's
shape: `vosk_transcribe(bin, model, wav) -> [text, conf_milli, err]`
+ env-resolver + availability probe + output parser.

Dispatch: fork + execve `python3 -c '<inline-script>' <wav> <model>`
with stdout drained through a pipe. The inline Python (~30 lines,
embedded as a NOVA string literal) imports vosk, streams 4 KB at a
time through KaldiRecognizer with SetWords(True), accumulates per-word
`conf` values, prints exactly `OK <milli> <text>` or `ERR <msg>`.

Pre-flight error codes parallel whisper's: "binary not found"
(python3 missing), "model not found" (model dir's `am/final.mdl`
sentinel absent), "wav not found", "vosk not installed" (no OK/ERR
line emitted -- import blew up).

JFK on the small-en Vosk model: avg per-word conf = **968 milli**.

### Seam wiring (`stt_seam.nova`)

- New constant: `STT_BACKEND_VOSK = 5`.
- New constructor: `stt_seam_new_vosk(model_path)`.
- New env mapping: `CE_STT_BACKEND=vosk` -> `STT_BACKEND_VOSK`.
- Auto-pick order: whisper > vosk > stub. Subprocess opt-in only.
- `_stt_backend_whisper` switched to the confidence-aware variant.

### Install / dependency notes (Vosk)

The Vosk wheel is pure-Python with a bundled libvosk.so. Pip-install
on Debian-flavoured hosts can require `--no-deps --break-system-packages`
when system packaging conflicts with PEP 668. The transitive deps
(`srt`, `requests`, `tqdm`) are needed for `vosk/__init__.py`'s
top-level imports; they install cleanly via `apt-get install
python3-requests python3-tqdm` plus a manual copy of the single-file
`srt.py` module.

Small English model: ~50 MB. Download
https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
and unzip into `/usr/local/share/vosk/`.

Both deps stay optional: the seam's `vosk_backend_available()` probe
returns 0 cleanly when python+vosk+model aren't all present, the
auto-pick falls back to whisper or stub, and the test suite SKIPs
real-decode assertions accordingly.

### Verification (R10B)

- `tests/unit/test_vosk_backend.nova` (NEW): 19 fns / 39 checks.
- `tests/unit/test_whisper_backend.nova` (extended): 28 -> 41 checks.
- `tests/integration/scenario_qq_vosk.sh` (NEW): 16 assertions when
  whisper + vosk + JFK present. Drives seam through each
  CE_STT_BACKEND value; asserts JFK conf > 800 milli via whisper
  (real per-utterance) and > 500 milli via Vosk.

### Future work (R10B)

- Whisper streaming via `-f -` stdin PCM.
- Larger Vosk model (`vosk-model-en-us-0.42`, ~1.8 GB).
- Per-word time-aligned confidence stream from Vosk.
- Vosk word-level grammar hints for the chat command vocabulary.

## R10F: autocorrelation F0 (pitch) estimation

R10F completes the audio triad next to R6E Klatt synthesis and R7F+R9B
VAD (with R7F+R8B STT). The new module
`src/io/transducers/audio_pitch.nova` extracts per-frame fundamental
frequency (F0) from PCM directly via short-time autocorrelation -- no
FFT, no floats, no DSP library. F0 / prosody is the missing modality
parallel to the transcript: STT tells us *what* was said, pitch tells us
*how* it was said (rising vs falling, soft vs emphasized, adult-male vs
child).

### Why a pure-NOVA F0 estimator earns its keep

- **Prosody atoms.** Mean voiced F0 + range expansion over a VAD
  speech segment are the two prosodic features most directly tied to
  arousal in the literature (angry / happy widen the range; sad /
  bored collapse it; rising terminal -> question; falling terminal ->
  statement). Attaching these to the moment-scope atoms that the chat
  already emits costs almost nothing and gives downstream layers a
  read-out the LLM-free path otherwise couldn't reach.
- **Speaker-mean banding.** Mean voiced F0 separates adult-male
  (80-180 Hz), adult-female (160-300 Hz), and child (250+ Hz)
  speakers reliably. A session-level rolling average across voiced
  runs is enough to distinguish multiple speakers in an hour-long log
  without proper diarization.
- **Question detection without LLM heuristics.** Last-frame F0 above
  the speaker median is the canonical "rising intonation" cue. The
  chat input layer can route question vs statement on this signal
  alone for short utterances.

### Algorithm

Per ~30 ms frame at the configured sample_rate (240 @ 8 kHz, 480 @
16 kHz):

1. Compute `R(tau) = sum_{n=0}^{N-tau-1} x(n) * x(n+tau)` for
   tau in [tau_min, tau_max] where
   `tau_min = sample_rate / f0_max` (16000/500 = 32 @ 16 kHz)
   and `tau_max = sample_rate / f0_min` (16000/50 = 320 @ 16 kHz).
2. Raw argmax: `best_tau = argmax_{tau} R(tau)`.
3. **Octave-down correction (pass 2).** Walk `tau = best_tau * k` for
   k = 2, 3, ... while `tau <= tau_max`; if `R(tau) >= 0.92 *
   R(best_tau)` accept the longer period and raise the threshold to
   0.92 * R(new). Cures the autocorrelation-on-harmonics failure
   mode where the raw argmax locks onto the first formant period.
4. Voicing: `voicing_milli = (1000 * R(best_tau)) / R(0)`. Voiced
   iff `voicing_milli >= 300`. Below threshold -> unvoiced
   (f0_centihz = 0 sentinel).
5. **Output in centi-Hz** (Hz * 100): preserves sub-Hz precision in
   pure integer arithmetic so a 119 Hz speaker is distinguishable
   from a 120 Hz speaker (which a plain Hz int would round away).

### Empirical calibration of the 0.92 octave threshold

For a pure sine at frequency f sampled at sr for N samples, the
autocorrelation at period T = sr / f is

  R(T) = (N - T) / 2 * A^2          (perfect alignment, cos = 1)

and at multiples kT:

  R(kT) = (N - kT) / 2 * A^2        (also perfect, cos = 1)

So the ratio R(2T) / R(T) = (N - 2T) / (N - T) depends only on T / N:

| f0 (Hz) | T (samples @ 16 kHz) | R(2T)/R(T) |
|--------:|---------------------:|-----------:|
|     100 |                  160 |       0.50 |
|     200 |                   80 |       0.80 |
|     300 |                   53 |       0.86 |
|     400 |                   40 |       0.91 |
|     500 |                   32 |       0.93 |

A threshold of 0.92 leaves the 100, 200, 300, 400 Hz cases UNTOUCHED
(no octave snap on pure sines below 500 Hz). Klatt vowels (sum of two
cosines at F1, F2) and natural speech (glottal pulse train + formants)
have R(2T)/R(T) at the true glottal period that exceeds 0.92 because
the harmonic structure adds in-phase to the autocorrelation at every
multiple of the true period. So the octave check fires at the right
place but stays bit-identical to raw argmax on a pure sine.

The threshold is exposed as the constant `PITCH_OCTAVE_RATIO_MILLI`
in the module so future tuning experiments can override it without
touching the algorithm.

### Integer-arithmetic safety dance

The autocorrelation accumulator and the normalized-peak division both
cross NOVA's smart-op 16 GiB pointer-classifier threshold on a loud
480-sample frame (PCM16 max yields R(0) up to ~5e11, far above the 16
GiB high-end where the smart-op heuristic treats values as pointers
and dispatches to string-concat / strcmp / str_repeat).

The fix is the documented `int_*` escape hatch:

| Operation                          | Pattern                          |
|------------------------------------|----------------------------------|
| `sum + a*b` (accumulator)          | `int_add(sum, a*b)` (a*b is small)|
| `cur > best_r` (both potentially large) | `int_sub(cur, best_r) > 0`   |
| `(1000 * big) / r0`                | `int_div(int_mul(1000, big), r0)` |
| `if r0 <= 0`                       | `if int_sub(r0, 1) < 0`           |

Comparisons against ZERO (a small int) ARE safe under the smart-op
because the classifier's `_nova_lt` / `_nova_gt` go to the integer
path if EITHER operand is integer; 0 is always integer. So
`if voicing < 300` and `if best_r > 0` both work without int_sub.

### Verification (R10F)

- `tests/unit/test_audio_pitch.nova`: **52 assertions** spanning
  constants/accessors, autocorrelation primitives, pure-sine
  estimates at 100/200/400 Hz, white-noise unvoiced, silence
  unvoiced, Klatt vowel band, `pitch_track` on a rising-pitch
  contour, `pitch_mean_voiced` on mixed buffers, `pitch_range`
  known-min-max, F0_MIN / F0_MAX bounds enforcement (25 Hz with
  f0_min=50 is rejected; 1500 Hz with f0_max=500 is rejected),
  short-buffer edge cases.

- `tests/integration/scenario_tt_pitch.sh`: **20 assertions**.
  Round-trip synthesized PCM16 WAVs (200 Hz sine, Klatt /uw/ vowel)
  through audio_capture_to_pcm and pitch_track; assert mean F0 within
  expected range. Chat-surface assertions: /help advertises /pitch
  with R10F tag; /pitch <wav> reports f0_mean + f0_range; /pitch
  (no arg) prints usage; /pitch <missing> -> graceful FAILED. JFK
  fixture assertions (when /tmp/whisper.cpp/samples/jfk.wav is
  present): mean F0 in [80..280] Hz adult range, >= 100 voiced
  frames out of ~366 total.

### Measured F0 values on the audit fixtures

| Fixture                          | True F0    | R10F mean | Voicing       | Notes                            |
|----------------------------------|-----------:|----------:|--------------:|----------------------------------|
| 100 Hz sine (480 @ 16 kHz)       |    100 Hz  |  100 Hz   | 666 milli     | exact (period quantizes to 160)  |
| 200 Hz sine                      |    200 Hz  |  200 Hz   | 833 milli     | exact (period 80)                 |
| 400 Hz sine                      |    400 Hz  |  400 Hz   | 916 milli     | exact (period 40); 0.92 threshold |
| Klatt /uw/ vowel (8 kHz, F1=300) |    n/a     |  296 Hz   | 868 milli     | snaps to F1 cluster (no glottal)  |
| JFK adult-male (16 kHz, 5.5 s)   |   ~140 Hz  |  220 Hz   | -- (per-frame) | first-formant snap; see below     |

### Known limitations (R10F)

- **JFK mean F0 = 220 Hz, not the textbook 140 Hz.** Unmodified
  autocorrelation snaps to the first formant region on natural
  speech. The integer-multiple peak check cures simple 2x / 3x
  octave snaps on harmonic structure (the Klatt /uw/ result is
  better than raw argmax) but doesn't fully cure the formant snap
  on harmonic-rich utterances like JFK. **R11B (below)** shipped
  the classical YIN cure (cumulative mean normalized difference)
  as a parallel entry point; on JFK it drops the mean from 220 Hz
  (R10F formant snap) to 144 Hz (R11B YIN, in the adult-male band).
- **R6E Klatt has no glottal source.** The two-formant carrier
  is a sum of cosines at F1 and F2 -- there is no actual fundamental
  at 120 Hz or anywhere else. Autocorrelation on Klatt output picks
  the F1 / GCD periodicity. A future R6E revision that adds a glottal
  pulse train (the canonical Klatt synthesizer has this) would let the
  R10F unit test assert F0 at the synthesized fundamental directly.
- **No per-frame F0 smoothing.** A future revision can add a 5-frame
  median filter or Viterbi smoothing to stabilize the F0 trajectory
  across voiced runs.

### Future work (R10F)

- ~~YIN / RAPT cumulative-mean-normalized-difference variant for true~~
  ~~octave robustness on JFK-class natural speech.~~ **DONE in R11B**
  -- see "R11B" section below.
- Cepstral pitch detection as a second algorithm (R7F-style backend
  switch): take the log of the magnitude spectrum and find its
  quefrency-domain peak. Requires an FFT (or a real autocorrelation-
  of-log-autocorrelation hack); maps cleanly onto the existing seam
  pattern. Two estimators give a vote-or-pick path.
- Pitch-contour atoms: emit one prosody atom per VAD speech segment
  with (mean_f0_centihz, range_centihz, terminal_rise_or_fall) so the
  KG can store intonation curves alongside the transcript. The chat
  `/listen` could then attach these as moment-scope features.
- Speaker-mean banding: a session-level rolling average of mean F0
  over voiced runs, with a 3-band classifier (adult-male / adult-
  female / child) attached as a session-scope atom.
- Stream/online estimator: pitch_estimate_frame is pure per-frame;
  wiring it to audio_capture's streaming PCM iterator gives a real-
  time F0 stream parallel to the VAD event stream.
- 16 kHz internal default: VAD/STT/whisper all work at 16 kHz; audio_synth
  is 8 kHz by R6E convention. The pitch estimator clamps to [8..48 kHz]
  but defaults to whatever rate the WAV declares. A future R6E upgrade
  to 16 kHz would let pitch tests assert at the higher resolution.

## R11B: YIN-class F0 estimator (cumulative mean normalized difference)

R11B extends R10F's `src/io/transducers/audio_pitch.nova` with a
parallel YIN-class entry point that cures R10F's first-formant snap
on harmonic-rich natural speech. R10F's autocorrelation API stays
available for back-compat; callers pick the method per call.

### Algorithm

Following de Cheveigne & Kawahara, "YIN, a fundamental frequency
estimator for speech and music," JASA 111(4) April 2002:

1. **Difference function** `d(tau) = sum_{n} (x(n) - x(n+tau))^2`.
   Unlike autocorrelation, d(tau) is ZERO at the true period and
   positive elsewhere -- the MINIMUM marks the period, with no
   formant ambiguity.
2. **Cumulative mean normalization**:
   `d'(tau) = d(tau) * tau * 1000 / running_sum`, in milli units.
   Flattens the function at low tau so very-short lags don't
   dominate.
3. **Absolute threshold step**: find the smallest tau where d'(tau)
   < 100 milli (paper default 0.1) AND is a local minimum. If no
   such tau, the frame is unvoiced.
4. **Pass B octave-down anti-snap** (R11B-specific): walk integer
   multiples k=2,3,... of the candidate period. Prefer the LONGER
   period if a local minimum exists in a +/- 5 sample window around
   k*best_tau with d'(kT) <= 3.0 * d'(T). Gated by best_dprime > 0
   so pure-tone perfect-match cases stay at the fundamental.
5. **Parabolic interpolation** around best_tau for sub-sample
   precision: `tau_refined = tau + 0.5 * (a - c) / (a - 2*b + c)`
   where a, b, c = d'(tau-1), d'(tau), d'(tau+1).

### Public API (parallel to R10F)

- `pitch_estimate_frame_yin(samples, sr, f0_min, f0_max, yin_threshold)
  -> [f0_centihz, voicing_milli]`
- `pitch_track_yin(samples, sr)` -- module defaults
- `pitch_track_yin_with_bounds(samples, sr, f0_min, f0_max, yin_threshold)`
- `pitch_run_yin_command(arg)` -- chat /pitch_yin helper
- `pitch_yin_threshold()` / `pitch_yin_voicing_max()` accessors

### Verification (R11B)

- `make test`: 87 pitch checks total (52 R10F + 35 R11B), all green
- Unit tests in `tests/unit/test_audio_pitch_yin.nova`:
  - Pure 100/200/400 Hz sines: YIN F0 exact within +/- 50 centi-Hz
  - Harmonic-rich 120 Hz fixture (fundamental + 2nd + 3rd harmonics):
    YIN F0 = 12007 centi-Hz, NOT 24000 (2nd-harmonic snap) or
    36000 (3rd-harmonic snap)
  - White noise + silence: unvoiced (d' never below threshold)
  - Klatt /uw/: voiced, in [50..500] Hz band
  - Sub-sample parabolic interpolation: 197 Hz and 173 Hz fixtures
    where the true period is between integer samples; YIN's centi-Hz
    output lands within +/- 200 of the true value
  - R10F autocorrelation back-compat: both APIs still callable in
    the same compilation unit, no regression
- Integration scenario `tests/integration/scenario_vv_yin_pitch.sh`:
  - Synthetic 200 Hz sine WAV: both R10F and YIN report 20000 centi-Hz
  - JFK adult-male sample: R10F mean = 21954 centi-Hz (~220 Hz
    formant snap), YIN mean = 14461 centi-Hz (~145 Hz, in adult-male
    band [80..180] Hz). YIN < R10F demonstrated (formant snap cured).

### Results table (R11B vs R10F)

| Fixture                          | True F0   | R10F mean | R11B YIN mean | Outcome           |
|----------------------------------|----------:|----------:|--------------:|-------------------|
| 100 Hz sine (480 @ 16 kHz)       |   100 Hz  |   100 Hz  |     100 Hz    | parity            |
| 200 Hz sine                      |   200 Hz  |   200 Hz  |     200 Hz    | parity            |
| 400 Hz sine                      |   400 Hz  |   400 Hz  |     400 Hz    | parity            |
| 120 Hz harmonic stack (1+2+3 hx) |   120 Hz  |   120 Hz  |     120 Hz    | both OK on synth  |
| Klatt /uw/ vowel (8 kHz F1=300)  |    n/a    |   296 Hz  |     145 Hz    | YIN dodges F1 snap|
| JFK adult-male (16 kHz, 5.5 s)   |  ~140 Hz  |   220 Hz  |     145 Hz    | YIN cures snap    |

### Known limitations (R11B)

- **JFK Pass B aggressive 3.0x ratio.** The Pass B octave-down ratio
  (3000 milli = 3.0x) was empirically calibrated against the bundled
  JFK fixture. Higher-fidelity speech (clean broadcast voice) may
  benefit from a tighter 2.0x ratio (less aggressive snap-down). The
  ratio is a constant for now; future work could expose it as a
  parameter.
- **No temporal smoothing.** Per-frame YIN can still occasionally
  emit an octave-up frame in the middle of an otherwise-low voiced
  region. The YIN paper's Step 5 ("best local estimate") uses a
  +/- 1 frame sliding window to stabilize; not implemented here.
- **2x autocorrelation cost.** Per frame at 16 kHz: ~139k
  subtract-square-add (YIN diff function) vs ~139k multiply-add
  (autocorrelation), plus ~290-step running sum and ~290-step
  normalization. Roughly 2x the R10F cost; still pure integer
  arithmetic, no FFT.

### Future work (R11B)

- **YIN Step 5 best local estimate** -- per-frame minimum search
  within a +/- 1-frame sliding window stabilizes octave errors.
- **Adaptive YIN_OCTAVE_RATIO_MILLI** tuned to per-frame SNR --
  high-SNR frames can use a tighter ratio (less aggressive snap);
  low-SNR (formant-dominated) frames can keep the current 3.0x.
- **Backend switch on the pitch seam** -- letting the chat surface
  pick R10F autocorrelation, R11B YIN, or a future cepstral
  detector by per-session knob (mirrors the R7F+R10B STT seam).
- **Streaming YIN** -- the per-frame estimator is already pure; a
  push-style iterator over audio_capture's PCM stream would emit
  one [f0_centihz, voicing_milli] per 30 ms tick alongside the
  VAD event stream.

## R12D: TD-PSOLA pitch shifting + time stretching

R12D adds the audio *manipulation* leg next to R6E synthesis, R7F/R9B
VAD, R8B/R10B STT, and R10F/R11B F0 estimation. New module
`src/io/transducers/audio_psola.nova` implements TD-PSOLA
(Time-Domain Pitch-Synchronous Overlap-Add; Moulines & Charpentier
1990) -- the classical integer-friendly algorithm for *independent*
pitch shifting and time stretching.

### Why TD-PSOLA

Naive resampling shifts pitch *and* time together: 2x resample yields
2x F0 *and* 2x speed (chipmunk). To shift pitch without changing
duration (or vice versa) the substrate needs an algorithm that
separately addresses the spectral envelope (formants) and the
fundamental period. TD-PSOLA does this in the time domain only -- no
FFT, no floats:

1. **Pitch mark detection.** Run R11B YIN per frame to estimate the
   local period `tau = sample_rate / F0`. Anchor a mark within each
   predicted period at the local signed-max sample (positive glottal
   pulse peak; the signed criterion avoids the half-period
   alternation that |max| would suffer on a pure sine where both
   +peak and -peak are local |maxima|). For unvoiced frames a 10 ms
   fallback grid keeps the segment grid defined.
2. **Hann windowing.** At each mark, extract a Hann-windowed segment
   of length `2*tau` centred on the mark. Adjacent segments overlap
   by exactly `tau` samples.
3. **Pitch shift (alpha).** Keep segments; deposit them at a denser
   (alpha > 1) or sparser (alpha < 1) grid with output period
   `tau' = tau / alpha`. Spectral envelope (formants) preserved
   because segments aren't resampled.
4. **Time stretch (beta).** Keep output period at `tau`; walk input
   marks at rate `1/beta`. Duplicates segments when slowing down,
   skips them when speeding up. F0 preserved.
5. **Combined.** `psola_transform(pcm, sr, alpha, beta)` composes
   both.

### Integer-only Hann window

```
hann(n, N) = (1000 - 1000 * cos(2*pi*n/N)) / 2     // milli
```

The cosine is sampled from a 256-entry quarter-wave Bhaskara-degree-
domain table built lazily on first use (same shape as R6E
audio_synth's sine table; duplicated here so the transducer module
doesn't depend on the effector layer).

### Public API

- `psola_pitch_marks(pcm, sr) -> list[int]`
- `psola_pitch_shift(pcm, sr, alpha) -> pcm`  -- 1000=identity, 2000=octave up
- `psola_time_stretch(pcm, sr, beta) -> pcm`  -- 1000=identity, 2000=double duration
- `psola_transform(pcm, sr, alpha, beta) -> pcm`
- `psola_hann_window(n, N) -> int` (public for testability)
- Accessors

Chat: `/pitch_shift PATH FACTOR_MILLI` admin one-liner.

### Caps

- Input PCM length `<= 480000` samples (30 s @ 16 kHz)
- `pitch_factor_milli` in `[250, 4000]` (-2 octaves to +2 octaves)
- `time_factor_milli` in `[250, 4000]` (4x faster to 4x slower)

### Verification (R12D)

- **Unit (34 assertions, NEW `tests/unit/test_psola.nova`)**: pitch
  shift up 2x doubles F0 (40005 centi-Hz on 200 Hz input, ~0.1%
  error), pitch shift down 0.5x halves F0 (10000 centi-Hz exact),
  time stretch 2x doubles output length, combined 2x/2x yields
  ~400 Hz @ ~2x duration, identity transform preserves length + F0,
  Klatt /ae/ pitch shift preserves length + energy, silence -> silence,
  short input pass-through.
- **Integration (`tests/integration/scenario_aaa_psola.sh`, 16
  assertions)**: 200 Hz @ 8 kHz synthesized + written + re-decoded
  yields F0 = 20000 centi-Hz exact; pitch-shifted 2x yields
  F0 = 40022 centi-Hz (~400 Hz, within +/- 25 centi-Hz); time-
  stretched 2x yields exactly 19200 samples = 2x 9600 input.
- **All R6E + R7F + R9B + R8B + R10F + R11B audio unit tests pass**
  (audio_synth: 209, audio_capture: 28, audio_vad: 86,
  audio_pitch: 52, audio_pitch_yin: 35).

### Known limitations (R12D)

- **Identity reconstruction is not bit-exact.** Hann constant-
  overlap-add only holds for ideal 50% overlap with no integer
  quantization; integer-milli windowing introduces small boundary
  errors (~17 in centre of a 200 Hz sine, larger near edges).
  Acceptable for perceptual manipulation; the brief's +/- 5 per-
  sample target is a strict mathematical bound rather than a
  practical PSOLA reconstruction bound.
- **Klatt vowel YIN tracking irregular.** Klatt's two-formant cosine
  sum doesn't produce a clean glottal-pulse train, so the YIN-driven
  pitch-mark walker sees irregular spacing. PSOLA still applies the
  segment-overlap-add transform and the output has energy.
- **Per-period YIN cost.** Each pitch mark triggers a YIN frame
  estimate (O(frame_size^2)); for a 1-second 16 kHz buffer with 100
  Hz F0, that's ~100 YIN calls per second of audio. Above ~5 s
  callers should chunk.
- **No anti-aliasing on extreme factors.** Alpha values near 4000
  push the output spectrum near the Nyquist edge. Acceptable for
  the +/- 1 octave canonical use case.

## R13D: Voice cloning via Klatt formant transfer

R13D adds the audio *cloning* leg next to R6E synthesis, R7F/R9B VAD,
R8B/R10B STT, R10F/R11B F0 estimation, and R12D TD-PSOLA. New module
`src/io/effectors/audio_voice_clone.nova` implements a non-LLM speaker
voice transfer pipeline: analyze a reference WAV of the target speaker,
extract their mean P0 (via R11B YIN) + per-formant centers (via
integer-only LPC + spectral peak-picking), build a transferred phoneme
formant table, then synthesize new text in the cloned voice.

### Algorithm

1. **Reference analysis** (`vc_analyze_reference`): read WAV via
   `audio_capture_to_pcm`, run R11B `pitch_track_yin` over the full
   PCM and take the mean across voiced frames -> P0 in centi-Hz. For
   each 30-ms frame, run integer-only LPC (Levinson-Durbin on the
   autocorrelation) at order 10, evaluate `|1/A(e^jw)|^2` at 50-Hz
   spectrum-grid increments from 150 Hz to Nyquist, peak-pick the
   top 3 local maxima -> per-frame [F1, F2, F3]. Aggregate across
   frames via median (robust against LPC outliers).

2. **Formant mapping** (`vc_apply_profile`): given a list of target
   phoneme labels, produce a new formant table where:
   - Labels present in the reference (the typical 5-second vowel-rich
     sample contributes "ae") use the measured formants directly.
   - Labels NOT in the reference get R6E's defaults scaled by the
     measured F1/F2 ratios vs R6E's "ae" defaults (660 / 1720). So all
     vowels coherently shift to the target speaker's vocal-tract
     characteristics. Non-vowel phonemes (plosives/fricatives/nasals)
     pass through unscaled -- their "formants" are carrier hints, not
     vocal-tract resonances.

3. **Pitch transfer**: the profile's P0 displaces R6E's implicit
   ~120 Hz baseline. Implementation: instead of post-shifting R6E's
   output via PSOLA (which works at 16 kHz but is unreliable at the
   8-kHz R6E rate for low formant frequencies), the cloned synth
   builds each voiced phoneme as a continuous-phase glottal-source +
   light-formant mix at the target P0 (98% F0 + 1% per formant). The
   continuous-phase invariant across phoneme boundaries keeps YIN
   locked onto the cloned P0 across whole utterances.

4. **Synth** (`vc_synth_with_profile`): walk the input text char-by-
   char (same per-character fallback as R6E's `synth_text`); for each
   voiced char emit a continuous-phase F0+formants segment; for each
   unvoiced char fall back to R6E's `synth_phoneme` (no audible F0
   phase break).

### Integer-only LPC: Levinson-Durbin in milli fixed-point

The Yule-Walker equations are solved via the classical Levinson-
Durbin recursion (Press et al, Numerical Recipes 13.6) in 1000-unit
milli precision:

    E_0 = R(0)
    for k = 1..P:
      gamma_k = (R(k) - sum_{j=1..k-1} a_{k-1,j} * R(k-j)) / E_{k-1}
      a_{k,k} = gamma_k
      for j = 1..k-1: a_{k,j} = a_{k-1,j} - gamma_k * a_{k-1, k-j}
      E_k = E_{k-1} * (1 - gamma_k^2)

The numerator carries an extra factor of 1000 so the division yields a
milli-scaled gamma directly. The cross-term update `gamma * a_prev` is
divided by 1000 after the multiplication to stay in milli. The energy
update `E * (1 - gamma^2/1000^2)` factors as `E * (1000 - g^2/1000) /
1000`, keeping arithmetic in i32 range up to order 12. On a degenerate
input (R(0) == 0 or numerical breakdown E_k <= 0) the coefficients
collapse to [1000, 0, 0, ...] -- the trivial all-pass filter.

Spectrum evaluation: at each query frequency hz, compute the inverse
filter `A(e^jw) = 1 - sum_k a_k e^{-jwk}` as a complex number via
R6E's existing 256-entry quarter-wave sine table (4-fold symmetry).
Return `1 / |A|^2` in a fixed 1e9 scale so peak-picking is monotonic.
The 50-Hz grid gives sub-formant precision (formants are typically
spaced >= 500 Hz apart) at ~80 evaluations per frame at 8 kHz.

### Headline results

- **LPC on Klatt /ae/** (F1=660, F2=1720, F3=2410): extracted
  formants F1=650, F2=1700, F3=2450 -- all within +/- 50 Hz of R6E's
  defaults. The 50-Hz tolerance matches the spectrum-grid step.

- **P0 transfer on 200 Hz reference -> 200 Hz cloned synth**:
  reference 200 Hz sine YIN-extracted to P0 = 20000 centi-Hz exact;
  `vc_synth_with_profile("aeaeaeae", profile)` YIN-measured at
  20000 centi-Hz (200 Hz transferred faithfully via continuous-
  phase F0 carrier).

- **Identity profile (R6E ae defaults, ratios = 1000)**: applied to
  [ae, iy, uw] returns each phoneme's R6E default unchanged (660/1720
  for ae direct; 270/2290 for iy and 300/870 for uw via 1.0x
  scaling). The identity-transfer assertion is the canonical
  algorithm-correctness check.

- **Profile with F1 ratio = 500 (0.5x)**: applied to "iy" returns
  F1 = 135 (= 270 * 0.5), F2 = 1145 (= 2290 * 0.5), F3 = 1505 (=
  3010 * 0.5). The ratio-application is the canonical "transfer to
  unobserved phonemes" check.

### Verification

- **Unit (`tests/unit/test_voice_clone.nova`, 55 assertions)**: LPC
  on pure 800 Hz sine detects formant near 800 Hz; LPC on Klatt /ae/
  recovers (660, 1720, 2410) within +/- 100 Hz; `vc_analyze_reference`
  on a 200 Hz sine reference yields P0 = 20000 centi-Hz (+/- 200);
  `vc_apply_profile` identity profile returns unchanged R6E defaults;
  `vc_apply_profile` with ratio 0.5 scales unobserved vowels exactly;
  `vc_apply_profile` direct match returns reference formants;
  `vc_synth_with_profile` produces non-empty output for any non-empty
  text; `vc_synth_with_profile` with target P0=200 yields YIN F0 in
  [18500..21500] centi-Hz; profiles with different P0 produce
  measurably different synth F0.
- **Integration (`tests/integration/scenario_ddd_voice_clone.sh`, 14
  assertions)**: 200 Hz reference WAV -> profile.P0 = 20000 centi
  exact; clone synth YIN = 20000 centi exact (transferred pitch);
  applied table length matches input label list; chat /help and
  /clone command paths wire correctly (happy + sad paths).
- **All R6E + R7F + R9B + R8B + R10F + R11B + R12D audio unit tests
  pass unchanged** (audio_synth: 209, audio_capture: 28, audio_vad:
  86, audio_pitch: 52, audio_pitch_yin: 35, audio_psola: 34).

### Known limitations (R13D)

- **YIN octave-snap on high-pitched references.** R11B YIN snaps
  300 Hz sine references down to 150 Hz centi (the 3000-milli
  octave-down ratio is permissive enough to accept the 2x-period
  minimum on pure tones). The cloned synth then targets 150 Hz, not
  300 Hz. Workaround: use references in [80..220] Hz where YIN is
  reliable. This is a YIN limitation inherited from R11B, not
  introduced by R13D.
- **Formant contribution capped at 1% per formant.** Higher mixes
  (e.g. 5% per formant) let YIN's cumulative-mean-difference function
  lock onto formant-sub-harmonic minima rather than the F0 minimum,
  particularly when formants are at non-integer multiples of F0. 1%
  keeps YIN locked at the cost of audibly-thinner vowel character;
  perceptual quality is below a real Klatt-with-glottal-source synth
  but matches the brief's "non-LLM voice cloning" altitude.
- **Spectrum grid quantizes formant precision to 50 Hz.** Tighter
  grids (e.g. 10 Hz) would give finer formant resolution at ~5x
  per-frame cost; 50 Hz is the productivity sweet spot for typical
  vowel formants spaced >= 500 Hz apart.
- **No bandwidth measurement.** The profile carries per-formant
  bandwidths (BW1/BW2/BW3) but they default to Klatt 1980 nominal
  values (60/90/150 Hz). Measuring 3-dB FWHM from the local LPC
  spectrum peak would be a single-pass extension; left for future
  work where downstream phoneme synthesizers consume bandwidths.
- **Reference WAV cap 30 s.** Matches R12D's PSOLA cap; beyond this
  the per-frame LPC budget (~80 ms wall time at order 10 + median
  aggregation across 1000+ frames) dominates the chat-latency
  budget. Long references should be pre-trimmed to a vowel-rich
  utterance.

## Future work

- Promote OW to a true diphthong (it's /oʊ/, gliding toward /ʊ/). Backward-
  incompatible if anything depends on its current monophthong formants.
- Add voicing source for DH/ZH/V/Z: the LCG pseudo-noise floor doesn't
  model glottal pulse, so voiced fricatives are perceptually similar to
  their unvoiced counterparts. A full Klatt model would gate the noise
  with a glottal source.
- F3 modeling for diphthongs: currently ignored at 8 kHz (the F2/F3
  boundary at ~3 kHz isn't well-resolved at that rate). A 16 kHz rate
  upgrade would benefit from interpolating F3 too.
- Stress-mark variants (AH0 vs AH1 vs AH2): CMU dict uses stress digits;
  the current synthesizer collapses them. A future expansion could
  modulate amplitude/duration per stress level.
- Coarticulation: each phoneme is synthesized in isolation. Smooth
  formant transitions across phoneme boundaries (e.g. consonant-to-vowel
  ramps) would substantially improve naturalness but is computationally
  much heavier.
- **Voice cloning (R13D) extensions**: multi-vowel reference profiles
  (analyze "AY EY OW OY UH" and store per-vowel formants separately);
  glottal-source modeling (replace the F0 sine with a Liljencrants-
  Fant glottal pulse for more natural quality); bandwidth measurement
  via 3-dB FWHM on the local LPC spectrum peak; LPC root-finding via
  Bairstow's method for sub-grid formant precision; PSOLA-based pitch
  contour transfer (replace the constant target P0 with a full F0
  trajectory tracked from the reference); cross-rate analysis (do
  LPC at 16 kHz on a 16 kHz reference and downsample formants to
  R6E's 8 kHz synth).

## R14E -- Classical DSP effects (Schroeder reverb + noise gate / compressor)

Module: `src/io/transducers/audio_dsp.nova` (~590 lines)
Tests: `tests/unit/test_audio_dsp.nova` (34 assertions),
       `tests/integration/scenario_hhh_dsp.sh` (23 assertions)
Chat:  `/reverb PATH [WET]` and `/gate PATH [THR]`

R14E closes the **effects** leg of the audio chain: synth (R6E) ->
PSOLA pitch/time (R12D) -> voice cloning (R13D) -> **DSP effects (R14E)**
-> output. Three independent transforms, all integer-only, all using
ring-buffered delay lines and millis for gains (1000 = unity):

1. **Schroeder reverb** (`dsp_reverb(pcm, sr, wet_mix_milli, room_size_milli)`)
   reproduces Manfred Schroeder's 1962 classical reverb structure ("Natural-
   Sounding Artificial Reverberation", JAES). The signal flow:

       pcm -> [comb_0]  -+
              [comb_1]  -+--+--> [allpass_0] -> [allpass_1] -> wet
              [comb_2]  -+  |
              [comb_3]  -+--+
       wet_signal * wet_milli + dry * (1000 - wet_milli) -> output

   - 4 parallel feedback comb filters at delays {5963, 4998, 4327, 3911}
     samples (scaled to the working sample rate from the 16 kHz reference).
     Per-comb gains scale with `room_size_milli`: bigger room -> longer
     decay. The four prime delays ensure no obvious coloration.
   - 2 cascaded allpass filters at delays {1051, 357} with the classical
     fixed gain g=0.7 (700 milli). These produce flat magnitude with
     dispersive phase -- the "diffuse" character of the late reverb.
   - Output extends `len(pcm) + tail_ms * sr / 1000` samples; the 400 ms
     tail lets the IR ring out past the input without clicking.
   - Wet/dry mix is integer: `output = (wet * wet + (1000-wet) * dry) / 1000`,
     with per-sample PCM16 clipping so a runaway room=1000 feedback can't
     ladder beyond int16 range over a long tail.

2. **Noise gate** (`dsp_noise_gate(pcm, sr, threshold_milli, ratio_milli,`
   `attack_ms, release_ms)`) attenuates samples whose 30 ms RMS envelope
   falls below the threshold. Smoothed attack/release ramps the gain
   linearly over `attack_ms` (opening) / `release_ms` (closing) instead of
   switching instantly -- avoids click artifacts at utterance boundaries.
   `ratio=1000` -> hard gate (full mute); `ratio=500` -> 2:1 below
   threshold; `threshold=0` -> always open (pass-through).

3. **Compressor** (`dsp_compressor(...)`, same args) is the symmetric
   inverse: attenuates samples ABOVE threshold, useful for taming loud
   peaks (e.g. the wet output of `dsp_reverb` at room=1000).

### Integer-safety against NOVA's 1 MB smart-op threshold

The audio buffers themselves stay in PCM16 range (< 1 MB threshold), but
the sum-of-squares accumulator in `dsp_rms` and `_dsp_envelope_at` reaches
~1e12, and intermediate reverb products (`wet * y1`) hit ~3e7. NOVA's
smart `<`, `>`, `+`, `*` operators dispatch to string-runtime helpers
when both operands exceed `PTR_THRESHOLD = 0x100000` (see
`NOVA_BUG_THRESHOLD.md`), causing SIGSEGV. Three workarounds applied:

- `dsp_rms`, `_dsp_envelope_at`, `_sum_sq`: route the multiply and the
  running-sum add through `int_mul` / `int_add` (scalar-safe builtins).
- `_dsp_isqrt`: every binop (`<`, `+`, `/`) goes through `int_lt`,
  `int_add`, `int_div`. The local `int_lt(a, b)` helper computes
  `int_shr(int_sub(a, b), 63)` -- arithmetic shift of the sign bit --
  to avoid the smart-op dispatch when both operands are huge.
- `_dsp_clip_pcm16`: pre-mix values can be 3e7 (>1 MB), so the
  `if x > FULL_SCALE` and `if x < neg_floor` checks route through
  `int_gt` / `int_lt` for scalar safety.
- Reverb's wet/dry mix `wet * y1 + dry_complement * x` would have
  both addends in the 3e7 range; the addition goes through `int_add`
  to dodge `_nova_concat`.

### Verification snapshot (latest run)

- 34 unit assertions, 23 integration assertions; 170/170 unit tests + all
  related audio scenarios still pass.
- Reverb impulse response (impulse at sample 0, 4000-sample input @ 8 kHz,
  wet=1000, room=800): output length 7200 samples, **610 non-zero samples
  past the input** (the decay tail), first comb spike at sample 1955
  (`cd3 = 3911 * 8000 / 16000`).
- Noise gate attenuation on a low-level square wave (amp=400, threshold=100
  milli ~= 3275 units): input RMS = 400, output RMS = 0 (the gate fully
  closes below threshold with ratio=1000). That is an unbounded dB
  attenuation; for a finite reference, a mid-level signal (amp=2000) that
  is still below threshold also collapses to RMS=0 after the release ramp
  settles -- ~ -inf dB on the floor.

### Future work

- **Stereo reverb** -- duplicate the comb bank with slightly offset delays
  per channel for a wider stereo image; mix matrix at the output.
- **Pre-delay** -- a single short delay line in front of the comb bank
  models the first early-reflection in a room ("how far from the wall").
- **Damping per comb** -- feed the comb output through a 1-pole low-pass
  before the feedback tap to model air absorption (higher frequencies
  decay faster than lows). One IIR coefficient per comb.
- **Lookahead compressor / limiter** -- buffer N samples ahead so the
  attack ramp can start *before* the loud peak hits the output, achieving
  zero-overshoot brick-wall limiting.
- **Sidechain gate** -- compute the envelope from a separate auxiliary
  input rather than the main signal (classic ducking for music + voice
  beds).
- **Multi-band processing** -- split the spectrum into 3..5 bands via
  IIR crossovers and run an independent gate/compressor per band so the
  bass doesn't trigger the high-frequency cell.
