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
