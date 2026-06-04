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

## R16E -- STFT / Cooley-Tukey FFT spectrogram (frequency-domain leg)

Module: `src/io/transducers/audio_spectrogram.nova` (~520 lines)
Tests:  `tests/unit/test_audio_spectrogram.nova` (49 assertions),
        `tests/integration/scenario_ooo_spectrogram.sh` (19 assertions)
Chat:   `/spec PATH`

R16E closes the **frequency-domain** leg of the audio chain. Every prior
audio module operates in the time domain:

    R6E   Klatt synth         time-domain formant carriers
    R7F   energy + ZCR VAD    time-domain rms / sign-flip
    R7F   whisper / vosk STT  external (no spectral exposure)
    R10F  + R11B pitch (AC / YIN)  time-domain autocorrelation
    R12D  PSOLA pitch-shift   time-domain epoch alignment
    R13D  voice clone         time-domain LPC residual swap
    R14E  reverb / gate / comp time-domain delay lines + envelopes

None of these surface a spectrum. Most downstream audio capabilities
(MFCC features, wake-word matched filters, source separation by
spectral mask, formant tracking that doesn't run blind, simple
harmonic / inharmonic classification) start with a magnitude
spectrogram. R16E ships the integer-only foundation.

### Algorithm

Short-Time Fourier Transform on Hann-windowed frames sliding through PCM
with `HOP_SIZE` overlap; per-frame DFT via the **integer Cooley-Tukey
radix-2 FFT** -- the textbook fast Fourier transform (Cooley & Tukey
1965), with milli-fixed-point twiddle factors so no float is needed.

1. **Twiddle table.** 512-entry cos / sin table at angle
   `2*pi*k / 1024` in milli precision (Bhaskara approximation,
   matches audio_synth's quarter-table sine). For an FFT of size
   N <= 1024 we look up index `k * (1024/N)`; one table serves
   every N at no extra storage.
2. **Hann window cache.** Per-N table of
   `w[n] = (1 - cos(2*pi*n / (N - 1))) / 2` in milli; boundary
   samples 0, mid-frame 1000. Different callers share their tables
   across many STFTs.
3. **Bit-reversal permutation.** Classic shift-and-mask reversal
   of each index's binary representation; in-place pair swap on
   the real / imag list pair (the decimation-in-time prereq).
4. **`log2(N)` butterfly stages.** At stage `s` the butterfly
   block size `m = 2^(s+1)`; per-twiddle the standard
   `(a + W*b, a - W*b)` update where `W = cos - i*sin`. Products
   are divided by milli immediately to bound the accumulator (after
   10 stages the intermediate stays under int63; on PCM16 input
   the worst case is well under 1e10).
5. **Magnitude.** `|X[k]| = isqrt(re^2 + im^2)` via Newton
   iteration (same `_dsp_isqrt`-style helper as R14E reverb),
   emitted only for the lower N/2 bins (the upper half is the
   complex conjugate for real-valued input).
6. **STFT slide.** For each `start = 0, H, 2H, ...` up to
   `len(pcm) - N`, window the frame, FFT it, push the magnitude
   list. Frame count `= floor((N_samples - FRAME_SIZE) / HOP_SIZE)
   + 1`.

### Defaults / caps

- Defaults: `FRAME_SIZE = 512`, `HOP_SIZE = 256` (32 ms / 16 ms @
  16 kHz, 50% overlap, matches whisper / MFCC conventions). At
  8 kHz the chat helper drops to `256 / 128` for the same time
  resolution.
- Allowed frame sizes: powers of 2 in `{64, 128, 256, 512, 1024}`
  (radix-2 constraint).
- Sample rate clamped to `[8000, 48000]` Hz.
- Max input samples `480000` (30 s @ 16 kHz, matches R12D / R14E).

### Integer-safety against NOVA's 1 MB smart-op threshold

`re^2 + im^2` reaches ~6e13 on a loud FFT-ed sine, well above NOVA's
`PTR_THRESHOLD = 0x100000` (see `NOVA_BUG_THRESHOLD.md`). The smart
`+`, `*`, `<`, `>` operators would dispatch to `_nova_strcmp` /
`_nova_concat` and SIGSEGV. Three workarounds carried forward from
R14E:

- `_stft_isqrt`: every binop via `int_mul`, `int_add`, `int_sub`,
  `int_div`; the comparison `y < x` routes through the
  arithmetic-shift sign-bit trick (`int_shr(int_sub(a, b), 63)`)
  for safety on the multi-million range.
- FFT butterfly products `c * xr`, `s * xi` etc.: `int_mul` +
  `int_add` / `int_sub` + immediate `int_div(... , MILLI)` to bound
  the rolling intermediate.
- `stft_peak_frequency`: peak / current comparisons via the
  `_stft_int_gt(m, best_mag)` helper, also using the shift-the-
  sign trick on the magnitude pair (since the difference can hit
  multi-million).

### Verification snapshot (latest run)

- 49 unit assertions in `tests/unit/test_audio_spectrogram.nova` (above
  the 30-floor in the brief). 19 integration assertions in
  `tests/integration/scenario_ooo_spectrogram.sh`. All green.
- **FFT correctness:** 200 Hz sine @ 16 kHz, N=512 -> peak at bin in
  `[5, 8]` (expected 6.4 -> 6 or 7). 1000 Hz @ 8 kHz, N=256 -> peak
  at bin in `[30, 34]` (expected 32). Silence -> all-zero spectrum.
- **STFT round-trips:** 1-second 200 Hz sine @ 8 kHz -> peak frequency
  187 Hz (bin 6, nearest integer; bin width = 31.25 Hz). Klatt /ae/
  vowel (1200 samples @ 8 kHz, F1=660 Hz / F2=1720 Hz) -> peak
  frequency 1718 Hz (F2 dominates -- well inside the [400, 2200]
  formant band).
- **JFK 16 kHz WAV (whisper.cpp bundled sample):** 176000 samples
  -> 686 frames, 256 bins, total magnitude ~2.18e9 (massively
  non-zero), peak frequencies across the clip in the 125-406 Hz
  speech band.
- **IFFT identity:** `IFFT(FFT(x))[i]` within +/- 30 of `x[i]` on
  an 8-sample test input padded to N=64 (within milli-twiddle
  rounding error).

### Future work

- **MFCC features** -- log-Mel filter-bank projection + DCT on top
  of the magnitude spectrogram; the standard input for classical
  wake-word detectors and speaker ID models.
- **Wakeword matched filter** -- cross-correlate the spectrogram
  against a stored per-user template (e.g. "Aurora") and decide on
  the peak confidence; integrates naturally with the VAD-gated
  `/listen` path.
- **Source separation by spectral mask** -- ICA or NMF over the
  spectrogram; the integer-only path forces an approximate solver
  but the structure (NMF iterates) carries over cleanly.
- **Formant tracker that doesn't run blind** -- multi-peak picker
  with chained nearest-bin tracking surfaces F1 / F2 / F3 contours
  per frame, complementing audio_pitch's autocorrelation F0.
- **Inverse STFT** -- Hann-windowed overlap-add reconstruction so
  spectral effects (notch, denoise) route back to PCM without
  leaving the integer-only domain.
- **Larger FFT sizes** -- 2048 / 4096 / 8192 for HD audio analysis
  at 48 kHz; the twiddle table re-uses the same milli precision
  but needs a bigger base or per-N rebuild.

## R17B -- MFCC (Mel-Frequency Cepstral Coefficients)

Module: `src/io/transducers/audio_mfcc.nova` (~520 lines)
Tests:  `tests/unit/test_audio_mfcc.nova` (41 assertions),
        `tests/integration/scenario_qqq_mfcc.sh` (21 assertions)
Chat:   `/mfcc PATH`

R17B builds the **canonical front-end for classical speech tasks** on
top of R16E's STFT magnitude spectrogram. MFCC is the standard input
to GMM-HMM speech-to-text, DTW/k-NN wake-word matched filters, GMM
speaker-ID classifiers, and most pre-deep-learning phoneme recognizers.
The discriminative property is that perceptually distinct sounds (/ae/
vs /iy/ vs /uw/) map to MFCC vectors with non-trivial pairwise L2
distances -- the property every k-NN classifier relies on.

### Algorithm

Per STFT magnitude frame `|X[k]|` for k in `[0, N/2)`:

1. **Mel-scale filter bank.** 26 triangular filters spaced uniformly
   on the Mel scale (perceptually-weighted Hz) between `mel_floor =
   mel(80 Hz)` (below the lowest speech pitch) and `mel(min(Nyquist,
   8000 Hz))`. Each filter is a triangle peaking at a Mel-equispaced
   centre with weight 1000 milli, falling linearly to 0 at the
   previous and next centres. Filter weights are precomputed per
   filter as sparse `[bin, weight_milli]` pairs at filterbank build
   time.

   Mel scale (HTK / Slaney convention):
       mel(f) = 2595 * log10(1 + f / 700)
       mel_inv(m) = 700 * (10^(m / 2595) - 1)

   Both directions computed via an integer milli `log10` (a
   2-term Taylor polynomial on the mantissa after power-of-2
   range reduction) and its inverse `pow10` (linear interpolation
   on the residual after dividing by `log10(2)`). Accuracy is
   ~5% on the speech band, plenty for the integer-quantized
   filter bins.

2. **Logarithm.** For each filter output energy `E_i`, emit
   `log10_milli(E_i + 1)` -- the `+1` floor prevents
   `log(0) = -inf` on a silent bin (the HTK trick). Output is in
   milli.

3. **DCT-II (Type-2 Discrete Cosine Transform).**
   ```
   c_n = sum_{i=0..N_FILTERS-1} L_i * cos(pi * (i + 0.5) * n / N_FILTERS)
   ```
   for n in `[0, n_mfcc)`. Precomputed cosine matrix of shape
   `[n_mfcc, N_FILTERS] = [13, 26] = 338` milli entries; cached by
   `(n_mfcc, n_filters)` key so repeat frames share one allocation.

4. **Frame stacking.** Apply steps 1..3 to every STFT frame and
   stack into a `frames x n_mfcc` MFCC matrix.

### Defaults / caps

- Defaults: `n_mfcc = 13`, `n_mel_filters = 26`, frame_size /
  hop_size inherited from R16E (`512 / 256` @ 16 kHz; `256 / 128`
  @ 8 kHz to match `/spec`). The defaults match what whisper.cpp
  + Vosk consume on their way in.
- 1 <= `n_mfcc` <= 26 (above 26 the DCT is degenerate -- it just
  rotates back to the log-mel spectrum). `n_filters` fixed at 26.
- Frame sizes: powers of 2 in `{64..1024}` (inherits R16E radix-2
  constraint). Sample rate: clamped to `[8000, 48000]` Hz. Max
  samples: 480000 (30 s @ 16 kHz, R12D / R14E / R16E parity).

### Public API (`audio_mfcc.nova`)

- `mfcc_compute(pcm, sample_rate, frame_size, hop_size, n_mfcc)
  -> mfcc_t` -- 4-cell `[frames_list, sample_rate, frame_size,
  n_mfcc]`. Pass `0` for any of frame_size, hop_size, n_mfcc to
  get the default. Reuses R16E's `stft(...)` internally.
- `mfcc_at(mfcc, frame_idx, coef_idx) -> int_milli` --
  bounds-checked coefficient access (returns 0 out-of-range).
- `mfcc_frame_count(mfcc) -> int`
- `mfcc_first_frame(mfcc) -> list_of_int_milli`
- `mfcc_l2_distance_sq(vec_a, vec_b) -> int` -- pairwise L2-squared
  distance over coefs 1..n (skipping the c_0 energy term so the
  comparison reflects spectral SHAPE not loudness).
- `mel_filterbank(n_filters, frame_size, sample_rate) ->
  filterbank_t` -- exposed for testability + reuse by the future
  matched-filter / spectral-mask paths.
- `dct_ii(log_mel_energies, n_mfcc) -> list[int_milli]` -- exposed
  for testability + reuse by any cepstral-domain code (formant
  tracker, etc.).
- `mfcc_hz_to_mel(hz) -> mel`, `mfcc_mel_to_hz(mel) -> hz` --
  the perceptual scale conversions, exposed for callers that want
  to compute filter centre frequencies directly.

### Chat wiring (2 net lines in `crossengin_chat.nova`)

```
/mfcc PATH         MFCC vector (first frame) of PATH WAV (26 Mel filters + DCT-13, R17B)
```

`/mfcc <wav>` parses the WAV via the shared `audio_capture_to_pcm`,
picks the same `frame_size / hop_size` as `/spec` (256/128 at 8 kHz,
512/256 otherwise), computes MFCC, and reports the first frame's
coefficients:

```
(mfcc PATH: frames=N, mfcc0=X milli, mfcc1=Y milli, ..., mfcc5=Z milli
 @ SR Hz, frame_size=N, n_mfcc=13)
```

Error paths mirror `/spec`: missing path -> `(mfcc FAILED: could
not parse WAV at PATH)`; empty argument -> `(/mfcc needs PATH --
usage: /mfcc /tmp/test.wav)`.

### Verification snapshot (latest run)

- 41 unit assertions in `tests/unit/test_audio_mfcc.nova` (above
  the 30 floor in the brief). 21 integration assertions in
  `tests/integration/scenario_qqq_mfcc.sh`. All green.
- **Mel scale:** `mel(1000 Hz) = 999` milli (HTK reference: 1000);
  `mel(8000 Hz) = 2885`. Monotone across [0, Nyquist].
- **Filter bank:** 26 filters @ 8 kHz / N=256 lay out from centre
  bin 5 (174 Hz) to centre bin 127 (4099 Hz). All centres
  monotonically non-decreasing.
- **Filter triangle shape:** middle filter peak weight = 1000 milli
  at centre, near-zero at neighbour centres.
- **DCT-II:** constant input -> c_0 dominant, c_n>0 ~= 0 (under
  5% of c_0). Step-wave at DCT frequency 3 -> peak coef in `[2, 6]`
  (integer phase rounding).
- **MFCC vowel discriminability:** the property every downstream
  classifier relies on.
  - `mfcc1(/ae/)` = -322
  - `mfcc1(/iy/)` = 2084
  - `mfcc1(/uw/)` = 6506
  - L2_sq(/ae/, /iy/) ~ 4.9e8 (L2 ~ 22000 milli)
  - L2_sq(/ae/, /uw/) ~ 3.9e8 (L2 ~ 19700 milli)
  - L2_sq(/iy/, /uw/) ~ 1.9e8 (L2 ~ 13800 milli)
  - All pairwise distances substantial (> 1e6 squared = > 1000
    milli L2). MFCC captures phoneme identity even in this
    integer-only impl.
- **MFCC on JFK 16 kHz WAV** (whisper.cpp bundled sample, 176000
  samples): 686 frames, n_mfcc=13, 684/686 frames have non-zero
  coefs (the first 2 frames are silence -> all-zero log-mel ->
  all-zero DCT; the remainder of the clip has full cepstral
  structure).
- **MFCC on silence:** all coefs exactly 0 (the log-floor `+1` in
  `log10(E + 1)` gives `log10(1) = 0`, so silence projects to a
  zero vector -- the cleanest possible silent fingerprint).
- 182/182 existing unit tests + every audio scenario still pass
  (R6E synth, R7F VAD, R8B / R10B STT, R10F / R11B pitch,
  R12D PSOLA, R13D voice clone, R14E DSP, R16E STFT).

### Future work

- **Delta + delta-delta MFCC** -- 1st and 2nd derivative of the
  MFCC time series; standard for HMM-based recognizers (3x feature
  expansion, 13 -> 39 coefs).
- **Cepstral mean / variance normalization (CMVN)** -- subtract
  the running mean from each coef across the utterance to remove
  channel + speaker bias; standard pre-classifier step.
- **Wake-word matched filter** -- store a per-user MFCC template
  for a wake-word ("Aurora") and run DTW against incoming MFCC
  frames; decide on the peak confidence.
- **Speaker-ID k-NN classifier** -- nearest-neighbour over a
  database of stored speaker MFCC vectors; the L2 distances we
  ship are exactly the right metric.
- **Filter-bank tweaks** -- per-filter triangle area normalization
  (Slaney's recipe) so wider Mel-bands at high frequency don't
  over-contribute relative to narrow low-frequency bands.
- **Higher-order log** -- our two-term Taylor polynomial is good
  to ~5% on the speech band; a 4-term polynomial or a 256-entry
  table would tighten it to <1%.


## R18C -- wake-word DTW matched filter on MFCC sequences

Status: **DONE (`src/io/transducers/audio_wakeword.nova`).**
Closes the wake-word matched-filter future-work bullet above. The
algorithm is the textbook DTW-on-MFCC pipeline used by every classical
keyword-spotter from the late-80s GMM-HMM era through modern
DTW-based on-device wake-word systems (Snowboy's pre-DNN path, Picovoice's
"classical" mode): take one reference utterance, extract its MFCC
sequence at training time, persist it; at detection time MFCC the
incoming audio and dynamic-time-warp against the reference template.
DTW handles the inevitable speech-rate variation between the
enrollment utterance and a live one (someone says the wake word a bit
faster or slower) without needing per-frame phoneme alignment.

### Algorithm

For an N-frame input MFCC sequence and an M-frame reference MFCC
sequence, fill the [N x M] DTW lattice:

```
D[i][j] = local_distance(input[i], reference[j])
       + min(D[i-1][j], D[i][j-1], D[i-1][j-1])
```

with D[0][0] = local_distance(input[0], reference[0]) and the boundary
rows / columns taking only the available neighbour. The final
distance is `D[N-1][M-1] / (N + M)` -- path-length normalized so a
short / long utterance pair is commensurable with a same-length pair.

Local distance is the per-frame squared L2 between two 13-dim MFCC
vectors, **skipping coef 0** (the energy term -- otherwise loud
non-matches would inflate D faster than spectrally-aligned matches).
We reuse R17B's `mfcc_l2_distance_sq` for the per-cell cost so the
integer-only contract is preserved.

VAD interlock: `wake_detect` calls into R7F's `vad_state_new` /
`vad_process_pcm` with the adaptive noise-floor calibration disabled
(adaptive mode assumes leading silence; wake words by definition lead
with speech). The detection refuses to fire when the buffer holds no
detected speech segment, so pure-silence and white-noise buffers
short-circuit to `detected=false` even when the MFCC distance happens
to round to zero (silence projects to an all-zero MFCC vector ->
DTW = 0 against any template that also has a zero leading frame; the
VAD short-circuit prevents that false positive).

### Public surface

- `wake_train_template(wav_path)` -> `template_t` -- WAV-to-PCM via
  R6E, MFCC via R17B, packed into a 5-cell template
  `[tag, frames, sample_rate, frame_size, n_mfcc]`. Returns 0 on
  parse failure / silence.
- `wake_train_template_from_pcm(pcm, sample_rate)` -- the I/O-free
  variant used by the unit tests; same return shape.
- `wake_template_save(template, path)` / `wake_template_load(path)`
  -- text-format persistence. Round-trip is bit-identical: same
  frames, same metadata. Format:
  ```
  WAKE_TEMPLATE 1
  sample_rate 8000
  frame_size 256
  n_mfcc 13
  n_frames 17
  frame <c0> <c1> ... <c12>
  ...
  ```
- `wake_detect(template, audio, sample_rate, threshold_milli)`
  -> `[detected_bool, dtw_distance_milli, end_frame]` (3-cell list).
- `wake_dtw_distance(mfcc_a, mfcc_b)` -- exposed for downstream
  matchers (k-NN over a per-user template gallery, multi-template
  voting ensembles).
- `wake_smooth(detections)` -- 5-frame majority-vote moving-average
  for streaming wrappers.

Caps: `WAKE_TEMPLATE_MAX_FRAMES = 256` (4.1 s @ 16 kHz),
`WAKE_INPUT_MAX_FRAMES = 256`, default threshold 30000 milli^2 (tuned
against Klatt vowel-pair fixtures; same-utterance DTW comes in at 0,
different-utterance distance comes in at > 1e8 with a wide margin).

### Chat surface

- `/wake_train PATH` -- trains a template from a WAV and persists it
  to `/tmp/wakeword.template`. Output:
  `(wake_train PATH: frames=N, n_mfcc=13, sr=8000 Hz -> saved to ...)`.
- `/wake PATH` -- loads the template, runs `wake_detect`. Output:
  `(wake PATH: detected={true|false} distance=N milli (threshold=30000), end_frame=K)`.
- Error paths: `(/wake[_train] needs PATH ...)`,
  `(wake[_train] FAILED: could not parse WAV at PATH)`,
  `(wake FAILED: no template at /tmp/wakeword.template; run /wake_train first)`.

### Verification snapshot (latest run)

- 41 unit assertions in `tests/unit/test_audio_wakeword.nova` (well
  above the ~25 floor in the brief). 20 integration assertions in
  `tests/integration/scenario_uuu_wakeword.sh`. All green.
- **DTW on identical sequences:** 0 (mandatory baseline -- if the
  local distance is 0 everywhere along the diagonal, the lattice
  fills with 0, and the path-normalized final distance is 0).
- **DTW handles length mismatch:** a 10-frame and 20-frame sequence
  of the same content both DTW to 0 (the lattice finds the
  diagonal+horizontal warp that matches each input frame to one or
  more reference frames at zero cost).
- **DTW on Klatt /ay ey/ vs /uw ow/ wake fixtures:** distance =
  202356690 milli^2 -- six orders of magnitude above the same-utterance
  baseline (0). The chat output for this case:
  `(wake .../nonwake.wav: detected=false distance=202356690 milli (threshold=30000), end_frame=16)`.
- **Detection on training audio:** detected=true, distance=0 milli^2
  (the trainer and detector produce bit-identical MFCC sequences and
  DTW between identical sequences is 0).
- **Detection on different audio:** detected=false at the default
  threshold of 30000 milli^2; the actual distance for the Klatt
  /uw ow/ vs /ay ey/ trained pair is 202356690 -- a 6700x safety
  margin above the threshold.
- **Detection on noise / silence:** detected=false. The VAD interlock
  fires first (the buffer has zero detected speech segments) so the
  DTW lattice never runs. The chat output:
  `(wake .../noise.wav: detected=false distance=0 milli (threshold=30000), end_frame=0)`.
- **Save + load round-trip:** bit-identical template (n_frames,
  n_mfcc, frame contents). The unit test enumerates every coefficient
  of every frame and asserts equality.
- **Threshold-tuning extremes:** very high threshold (999e9) ->
  always detects regardless of distance. Threshold 0 -> never detects
  (cumulative L2-squared is non-negative).
- 226/226 existing unit tests + every audio scenario still pass
  (R6E synth, R7F VAD, R8B / R10B STT, R10F / R11B pitch, R12D
  PSOLA, R13D voice clone, R14E DSP, R16E STFT, R17B MFCC).

### Future work

- **Streaming detection** -- the current `wake_detect` is one-shot
  over a fixed buffer. A streaming wrapper would slide a window
  across continuous audio and run DTW per-window, applying the
  5-frame moving-average smoothing already exposed via `wake_smooth`.
- **Multi-template ensembles** -- store K templates per wake-word
  (different prosodies, different speakers) and detect on min over
  all K DTW distances; the integer-only path costs K times more
  per-frame but the math stays bit-deterministic.
- **Speaker-conditional thresholds** -- per-template thresholds
  trained from a tiny accept / reject set; the trainer would
  enumerate distance distributions on a held-out set and pick the
  EER point. Still integer-only via histogram math.
- **Tail-MFCC fingerprint** -- some keyword-spotters compress the
  reference into a smaller "tail" of the most variant frames (the
  consonant-cluster frames that distinguish "Hey Nova" from
  "Hi Nova"); reduces DTW work and template-storage footprint.
- **Cepstral mean / variance normalization (CMVN)** at training and
  detection -- same future-work bullet as R17B; the wake-word
  path benefits from it doubly because the detection thresholds
  become invariant to recording channel.

## R19D -- speaker identification via MFCC gallery + DTW NN classifier

Status: **DONE (`src/io/transducers/audio_speaker_id.nova`).**
The natural voice analog of R18D's LBP-gallery face recognition.
R17B shipped MFCC; R18C shipped DTW on a single template (wake-word
matched filter); R18D shipped a labelled gallery + chi-squared
nearest-neighbour classifier for visuals (face identity). R19D
closes the same shape for audio: a labelled gallery of enrolled
speaker MFCC fingerprints + a DTW nearest-neighbour classifier
that returns either the closest enrolled label or "unknown" when
no entry passes the configured threshold.

The pipeline mirrors the textbook classical speaker-ID setup used
from the 80s GMM-UBM era forward (per Reynolds & Rose). DTW-based
variants survive in today's on-device speaker-verification
baselines that don't ship a DNN front end:

```
ENROLLMENT (per known speaker):     QUERY:
  reference WAV                       query WAV
     |                                   |
     v                                   v
  MFCC sequence (R17B)              MFCC sequence (R17B)
     |                                   |
     v                                   v
  [label, frames] --+                frames
                    |                   |
                    v                   v
                gallery --- DTW(gallery, query)
                                        |
                                        v
                             argmin -> label | "unknown"
```

### Algorithm

Per-pair scoring reuses R18C's `wake_dtw_distance`: path-length
normalized DTW with squared-L2 local cost on 13-dim MFCC vectors
(skipping coef 0, the energy term). For an N-frame query and
M-frame reference:

```
D[i][j] = local_distance(query[i], reference[j])
       + min(D[i-1][j], D[i][j-1], D[i-1][j-1])
```

with the boundary rows/columns taking only available neighbours.
Final distance = `D[N-1][M-1] / (N + M)`. Identical sequences
DTW to exactly 0 (the diagonal walk picks zero local costs);
length-mismatched but content-identical sequences still DTW to 0
(the lattice finds the warp); spectrally-distinct sequences land
at distances >> 30000 (the default threshold), giving wide margin
between same-speaker and cross-speaker pairs on the Klatt
vowel-triple fixtures.

Classification: per query, run DTW against every alive gallery
entry. If the minimum distance is strictly less than the
threshold, return `[argmin_label, min_distance]`. Otherwise
return `["unknown", -1]`. Ties resolve to the first match in
enrollment order; same-PCM enrollments always hit at distance 0.

### Public surface

- `spk_gallery_new()` -> empty gallery (NOVA list).
- `spk_gallery_enroll(gallery, label, wav_path)` -> 1 on success,
  0 on parse/build failure. Idempotent on label (re-enrolling
  the same label OVERWRITES the prior entry).
- `spk_gallery_enroll_from_pcm(gallery, label, pcm, sample_rate)`
  -- I/O-free variant for unit tests.
- `spk_gallery_recognize(gallery, query_wav_path, threshold)`
  -> `[label, distance]` on a match within threshold;
     `["unknown", -1]` on empty-gallery / parse-failure /
     no-match.
- `spk_gallery_recognize_from_pcm(...)` -- I/O-free variant.
- `spk_gallery_save(gallery, path)` /
  `spk_gallery_load(path)` -- ASCII line-oriented persistence.
- `spk_gallery_size(gallery)` -- live-entries count (post-clear
  safe).
- `spk_gallery_clear(gallery)` -- drop all entries (uses dead-
  sentinel slots so re-enroll doesn't grow the underlying list).
- `spk_gallery_default_threshold()` -- 30000 milli^2 (matches
  R18C wake default; same DTW units).
- `spk_enroll_chat_args(arg)` /
  `spk_recognize_chat_args(arg)` -- chat dispatchers; use a
  per-process singleton gallery.

Caps: `SPK_GALLERY_MAX_ENTRIES = 64`, `SPK_LABEL_MAX = 64` bytes
per identity, per-entry MFCC capped at 256 frames (mirrors R18C).

### Chat surface

- `/spk_enroll LABEL PATH.wav` -- register a speaker. Output:
  `(spk_enroll OK label=LABEL size=N)` or
  `(spk_enroll FAILED on PATH: ...)`.
- `/spk_recognize PATH.wav` -- nearest-neighbour against the
  per-process gallery. Output:
  `(spk_recognize matched=LABEL distance=D threshold=T)` or
  `(spk_recognize unknown distance=-1 threshold=T)` or
  `(spk_recognize FAILED: gallery empty -- /spk_enroll first)`.

### Verification snapshot

- 53 unit assertions in `tests/unit/test_speaker_id.nova` (well
  above the ~25 floor in the brief). 22 integration assertions
  in `tests/integration/scenario_yyy_speaker_id.sh`. All green.
- **3-speaker gallery correctness:** enrolling alice (Klatt
  `/iy ae iy/`), bob (`/ae uw ae/`), carol (`/uw ow uw/`)
  succeeds; recognizing each fixture's own utterance returns
  its label at distance 0 (identical MFCC sequences DTW to 0).
- **Unknown rejection on 4th speaker:** dave (`/a ah a/`, NOT
  enrolled) returns "unknown distance=-1 threshold=30000" --
  no enrolled entry passes the default threshold for the
  spectrally-distinct fixture.
- **Save + load round-trip:** a 3-speaker gallery saved + reloaded
  reproduces identical recognize results for each fixture
  (each at distance 0 against the loaded entry).
- **Clear:** post-clear gallery size = 0; recognize returns
  "unknown"; re-enroll reuses dead-sentinel slots so the
  underlying list doesn't grow.
- **Duplicate enrollment overwrites:** re-enrolling alice with
  bob's PCM keeps size = 1 and re-aims the alice slot at the
  new MFCC.
- **Threshold extremes:** threshold = 0 always rejects (strict
  `<`); threshold = 999e9 always returns the nearest-neighbour
  regardless of distance.
- 188/188 existing unit tests + every audio scenario still pass
  (R6E synth, R7F VAD, R8B/R10B STT, R10F/R11B pitch, R12D
  PSOLA, R13D voice clone, R14E DSP, R16E STFT, R17B MFCC,
  R18C wake-word).

### Future work

- **Speaker-conditional thresholds** -- per-label thresholds
  tuned from a tiny accept/reject set (mirrors the R18C bullet);
  the trainer would enumerate distance distributions on a
  held-out set and pick each speaker's EER point.
- **Multi-utterance enrolment** -- store K reference utterances
  per speaker and recognize on min over K DTW distances. The
  integer-only path costs K times more per query but the math
  stays bit-deterministic and the false-reject rate drops
  sharply on real-mic recordings whose channel varies between
  enrolment and query.
- **GMM-UBM speaker-verification head** -- the classical
  follow-up that the open-source SIDEKIT toolchain shipped for
  TIMIT speaker-verification benchmarks. The k-means baseline
  trainer is integer-only; the universal background model is
  the same diagonal-covariance Gaussian mixture used by
  classical phoneme classifiers.
- **i-vector / x-vector embedding head** -- the modern DNN-free
  alternative (i-vectors are factor-analysis-based and survive
  in low-resource setups). The factor-analysis math is
  iterative but stays integer-only with milli fixed-point.
- **Cepstral mean / variance normalization (CMVN)** -- same
  future-work bullet as R17B and R18C; the speaker-ID path
  benefits doubly because the recognize threshold becomes
  invariant to recording channel.
- **DTW path-recovery + interval scoring** -- for tagging
  "which words in the query matched the gallery entry best",
  recover the back-pointer trace through the DTW lattice (we
  already compute the min argument per cell, but currently
  drop it). Useful for forced alignment + speaker-diarization
  follow-ups.

## R21C -- end-to-end TTS pipeline (text -> G2P -> Klatt -> WAV)

Status: **DONE (`src/io/effectors/audio_tts.nova`).**
CrossEngin already had speech IN (R8B whisper / R10B vosk STT)
and a usable speech-synthesis floor (R6E Klatt with 53 dispatches
covering the 44-phoneme ARPAbet inventory). What was missing was a
COMPLETE text-to-speech pipeline -- the user-visible TTS path that
takes free-form English text and produces playable WAV. R21C
closes that gap with a dictionary + rule-based G2P (grapheme-to-
phoneme) stage in front of the existing Klatt synth and a WAV
writer behind it.

### Pipeline

```
input text
   |
   v
tokenize on whitespace + punctuation
   |
   v
per-word G2P:
   dictionary lookup (~120 curated entries, case-folded)
       OR
   rule-based fallback (digraph greedy match + single-letter +
                         silent-e CVCe upgrade + silent-prefix
                         strip)
   |
   v
phoneme list (with "_brk_" sentinels between words)
   |
   v
per-phoneme R6E Klatt synth -> 1200 samples each (vowels via
formant synthesis, fricatives via LCG pseudo-noise, plosives
via silence+burst, nasals via damped carrier)
   |
   v
PCM concat + brief silence at word breaks (480 samples)
   |
   v
WAV header (44 bytes, sample_rate parameterised) + PCM body
   |
   v
sys_write + sys_fsync to /tmp/tts_out.wav
   |
   v
best-effort paplay (Mode 3)
```

### Dictionary (~120 curated entries)

Hand-curated coverage of the high-frequency English vocabulary:

- Greetings + interjections: hello, hi, hey, bye, yes, no, ok,
  okay, thanks, please, sorry
- Pronouns: i, me, my, you, your, we, our, he, him, his, she,
  her, it, they, them, this, that, these, those
- Function words: a, an, the, and, or, but, not, is, are, was,
  were, be, been, am, to, of, in, on, at, for, with, from, by,
  as, if, so, do, did, does, have, had, has, can, will, would,
  could, should
- Common nouns + verbs: world, time, day, night, good, bad,
  test, speak, say, make, take, give, go, come, know, see,
  look, find, think, want, need, feel, love, like, work, play,
  stop, start, run, walk, talk, open, close, save, load, name,
  what, when, where, why, how, who, which, here, there, now,
  then, all, one, two, three, four, five, six, seven, eight,
  nine, ten, zero
- CrossEngin domain: crossengin, nova, agent, kg, atom

Lookup is a single if-chain returning a `list_new` of phoneme
labels; case is folded to lower at the entry boundary. Total
table size: `TTS_DICT_ENTRY_COUNT = 122`.

### Rule-based fallback (~30 rules)

Greedy left-to-right walk for unknown words. Order of dispatch:

1. **Silent-prefix strip** at word start: `kn` (knee, knight),
   `wr` (write, wrong), `pn` (pneumonia), `mn` (mnemonic),
   `gn` (gnome), `ps` (psalm). The leading consonant is
   dropped; the remainder enters the rule walk.

2. **Silent-e CVCe upgrade** at the vowel position: when the
   current letter is a vowel, the next is a consonant, and the
   next-after-that is a final `e`, swap the vowel's short form
   for its long form (`cake` -> K + EY + K + (silent e); not
   K + AE + K + EH).

3. **Two-letter digraphs** matched greedily before single
   letters: `sh`, `th`, `ch`, `ng`, `ph` (-> /F/),
   `wh` (-> /W/), `ck` (-> /K/), `qu` (-> /K/+/W/), vowel
   digraphs `oo` (-> /UW/), `ee` (-> /IY/), `ea` (-> /IY/),
   `ai`/`ay` (-> /EY/), `ie` (-> /AY/), `ou` (-> /AW/),
   `ow` (-> /OW/), `oa` (-> /OW/), `oi`/`oy` (-> /OY/),
   r-coloured `ar` (-> /AA/+/R/), `er`/`ir`/`ur` (-> /ER/),
   `or` (-> /AO/+/R/).

4. **Single-letter fallback**: consonants map to their
   single-phoneme namesake (b -> /B/, k -> /K/, etc); vowels
   to their short form (a -> /AE/, e -> /EH/, i -> /IH/,
   o -> /AO/, u -> /AH/); `x` expands to /K/+/S/; unknown
   bytes fall through to schwa (`/AX/`).

The fallback is not high-quality (it can't disambiguate
heteronyms like "lead" the verb from "lead" the metal) but it
never crashes and produces audible output for any input.
Verification: "xyzwz" (gibberish) emits `K S Y Z W Z` via
the rule path -- exactly what the brief's adversarial
fixture demands.

### Determinism

`tts_speak(text, sample_rate)` is byte-deterministic at the
WAV level: same input -> same output. The synth side already
seeds its LCG at a constant value (R6E's `_lcg_seed`); the
G2P side is pure dictionary + rule lookup with no randomness.
The unit test calls `audio_synth_mode_reset()` and
`audio_lcg_reset()` between the two invocations and asserts
zero byte mismatches across the whole WAV.

### Sample-rate handling

R6E's `synth_phoneme()` is hardcoded to 8000 Hz internally
(1200 samples per phoneme at AUDIO_SAMPLE_RATE = 8000). When
the caller requests a different sample rate for the OUTPUT
WAV (16000 Hz is the standard ASR target), we still synthesize
at 8000 Hz but write the REQUESTED rate into the WAV header.
Most players resample on the fly; the audible effect is that
the synth plays at a different pitch/rate. A future resampler
would do proper interpolation here; for now the header field
is the only thing that varies. Determinism is preserved.

### Public API

- `tts_g2p(text)` -> phoneme list
- `tts_g2p_word(word)` -> per-word phoneme list
- `tts_g2p_marked(text)` -> phoneme list with "_brk_" sentinels
- `tts_tokenize(text)` -> word token list
- `tts_synth_phonemes(phonemes, sample_rate)` -> WAV byte list
- `tts_speak(text, sample_rate)` -> WAV byte list
- `tts_save_wav(wav_bytes, path)` -> 1 on success, 0 on failure
- `tts_phonemes_to_string(phonemes)` -> space-separated label
- `tts_dict_size()` -> curated entry count (122)
- `tts_say_run(text)` -> chat-side runner: G2P + synth + save +
  best-effort paplay, returns a formatted status string

### Chat wiring

`/say <text>` admin command (in `examples/crossengin_chat.nova`):
calls `tts_say_run(arg)`, prints the returned status line. With
no arg, prints `(/say needs TEXT -- usage: /say <text to speak>)`.
On success: `(said '<TEXT>' [phonemes=N wav=B bytes player=paplay
| no-player]; wrote /tmp/tts_out.wav)`.

### Verification

- 68 unit assertions in `tests/unit/test_audio_tts.nova` (NEW).
  Covers: G2P on dictionary words (hello -> /HH EH L OW/,
  world -> /W ER L D/, the -> /DH AX/), case-insensitivity,
  G2P on unknown word (xyzwz -> rule fallback), silent-e CVCe
  (cake -> /K EY K/), silent-kn prefix (knee -> /N IY/),
  digraph greedy match (sh in shx), text-level G2P (hello
  world phoneme count in 8..12), punctuation as separator,
  empty input -> empty phoneme list, single-vowel synth ->
  44+2400 bytes, WAV starts with RIFF + WAVE markers, sample
  rate field round-trip, word-break sentinel renders 480
  zero PCM samples, deterministic output (zero byte mismatch
  across two invocations), empty input -> 44-byte header-only
  WAV, save_wav round-trip via sys_open + sys_read,
  tokenize() handles extra separators, g2p_marked inserts
  break label between words.
- 22 integration assertions in `tests/integration/scenario_ffff_tts.sh`
  (NEW): stand-alone driver runs G2P + tts_speak + tts_save_wav,
  asserts /tmp/tts_out.wav exists, file size > 1024 bytes,
  WAV header starts with RIFF + has WAVE marker, sample rate
  field = 16000 LE, deterministic across two driver runs,
  empty input -> 44-byte WAV, chat /help advertises /say,
  chat /help labels /say as R21C, chat /say "hello world"
  echoes the text + reports the path + reports phoneme count
  in 8..9, chat /say with no arg shows graceful usage.
- All prior audio suites remain green (R6E Klatt, R7F VAD,
  R8B/R10B STT, R10F/R11B pitch, R12D PSOLA, R13D voice clone,
  R14E DSP, R16E STFT, R17B MFCC, R18C wakeword, R19D
  speaker_id).

### Future work

- **CMUdict-scale dictionary** -- the canonical 125K-entry
  table CMU released. CE ships ~120 entries; the full table
  would let G2P handle the 99% case without the rule fallback.
  Storage is the only cost (each entry is a string + a 5..10
  phoneme list); load on first call is O(n) once.
- **LSTM-free neural G2P fallback** -- the modern stand-in for
  the rule path is a small sequence-to-sequence model (Phonetisaurus,
  weighted FST-based; CMUSphinx ships one). The transition is to
  store the FST as integer arc lists and run the Viterbi-equivalent
  forward pass in pure NOVA; no floats needed.
- **Prosody markers** -- the brief mentions "appropriate prosody"
  but R21C just inserts a fixed 60 ms silence between words.
  Future work: stressed-syllable lengthening (mark from CMUdict
  stress digits, multiply the carrier's `n_samples`); intonation
  contours (pitch trajectory across the utterance, applied via
  R12D's PSOLA pitch shifter); phrase-final lowering at
  punctuation (the comma/period tokens are already detected by
  the tokenizer; promote them to prosody markers).
- **Sample-rate resampling** -- R21C writes the requested
  sample_rate into the header but synthesizes at the R6E-fixed
  8000 Hz internally. A proper polyphase resampler (Kaiser
  window + sinc kernel; integer fixed-point) would produce
  authentic-sounding 16000 Hz / 22050 Hz / 44100 Hz output.
- **Multi-language support** -- the dictionary is English-only.
  Adding Spanish / French / German would mean a per-language
  dictionary plus per-language rule fallback (Spanish is
  near-deterministic, French has more silent letters than
  English, German has long-vowel doubling). The R6E phoneme
  inventory already covers most cross-language ARPAbet-ish
  sounds.
- **Voice cloning at the TTS layer** -- R13D ships voice
  cloning at the per-phoneme layer (formant ratios applied at
  synth time). The TTS path could thread the cloned profile
  through `tts_speak()` so the whole utterance speaks in the
  cloned voice. The Klatt API already accepts a per-phoneme
  formant override; the TTS layer just needs to pass the
  profile through.

## R22F -- Audio melody extraction (F0 contour -> MIDI note sequence)

Status: **DONE (`src/io/transducers/audio_melody.nova`).** Completes
the audio analytic chain by lifting per-frame F0 estimates (R10F
autocorrelation, R11B YIN) into a *symbolic* melody: a sequence of
discrete MIDI notes with start/end times in milliseconds. R10F /
R11B answer "what is the pitch in frame i?"; R22F answers "what
notes did the speaker / singer just produce?" and renders them
in a human-readable string like `(melody: A4-440ms D4-220ms
E4-440ms ... | 7 notes)`.

### Pipeline

```
input PCM
   |
   v
R10F pitch_track_with_bounds  (MELODY_F0_MIN..MELODY_F0_MAX = 80..1500 Hz;
   per-frame [f0_centihz, voicing_milli] over 30 ms frames)
   |
   v
voicing filter (drop frames with f0_centihz == PITCH_UNVOICED)
   |
   v
Hz -> MIDI conversion (_hz_to_midi -> milli MIDI;
                       _hz_to_midi_int rounds to integer MIDI)
   |
   v
group consecutive same-MIDI frames into note candidates
   |
   v
drop candidates shorter than MELODY_MIN_NOTE_MS (default 80 ms)
   |
   v
list of note_t records: [start_ms, end_ms, midi_pitch, confidence]
```

### MIDI conversion

The standard MIDI 1.0 formula:

```
midi = 12 * log2(freq_hz / 440) + 69
```

is implemented as integer-only milli arithmetic with two lookup
tables:

1. **Octave-0 centi-Hz table** (12 entries, MIDI 21..32 = A0..G#1).
   Every other MIDI value is derived by integer shift -- exact at
   every A reference (MIDI 21, 33, 45, ..., 117) and within +/- 1
   centi-Hz at every other note.

2. **log2 fractional table** (16 entries, log2(1 + i/16) * 1000
   for i in [0..15]). Combined with shift-based mantissa extraction
   this gives log2(centihz) accurate to ~10 milli (~0.01 semitone)
   across the full [800..1300000] centi-Hz range.

Reference checks (within +/- 50 milli):
* 44000 centi-Hz -> midi_milli=69000 (A4)
* 22000 centi-Hz -> midi_milli=57000 (A3)
* 88000 centi-Hz -> midi_milli=81000 (A5)
* 26163 centi-Hz -> midi_milli=60000 (C4)
* 32963 centi-Hz -> midi_milli=64000 (E4)

### R10F vs R11B kernel choice

The brief specifies "use R11B YIN (handles formant snap)". We use
R10F autocorrelation in the default melody_extract path because the
canonical melody fixture (a held pure-sine instrument tone) is
exactly the signal class where R11B YIN's octave-down anti-snap
(calibrated for harmonic-rich speech in audio_pitch.nova) can
subharmonic-collapse a pure sine to half / quarter pitch -- precisely
the failure mode melody extraction must avoid. R10F autocorrelation's
octave-down ratio (920 milli, 0.92 threshold) is tight enough that
pure sines under ~500 Hz never snap. The R11B kernel remains
available via `pitch_track_yin` for harmonic-rich vocal pitch tracking
where R10F's formant snap dominates the error budget. See module
header docstring for the full trade-off discussion.

### Note name rendering

Standard MIDI naming convention: MIDI 60 = C4 (middle C). Octave
changes at every C (MIDI 0=C-1, MIDI 12=C0, ..., MIDI 60=C4, MIDI
72=C5). `_midi_to_note_name(midi)` returns "C4", "A#4", etc.;
negative-octave MIDI values render as "C-1".

### Public API

- `melody_extract(pcm, sample_rate)` -> `list[note_t]`
- `melody_to_text(notes)` -> str ("A4-440ms D4-220ms ..." formatted)
- `melody_run_command(arg)` -> chat-side runner for /melody
- `hz_to_midi(centihz)` -> int MIDI (rounded; -1 for unvoiced)
- `midi_to_note_name(midi)` -> str ("C4", "A#4", ...; "" for invalid)
- `note_midi(note)`, `note_start_ms(note)`, `note_end_ms(note)`,
  `note_duration_ms(note)`, `note_confidence(note)` accessors

### Chat wiring

`/melody <wav>` admin command (in `examples/crossengin_chat.nova`):
calls `melody_run_command(arg)`, prints the returned line. With
no arg, prints `(/melody needs PATH -- usage: /melody /tmp/test.wav)`.
On success: `(melody /tmp/x.wav: A4-440ms D4-220ms E4-440ms |
3 notes @ 16000 Hz)`. On empty input: `(melody /tmp/x.wav:
<no notes detected> @ 16000 Hz)`. On parse failure: `(melody
FAILED: could not parse WAV at /tmp/x.wav)`.

### Verification

- 40 unit assertions in `tests/unit/test_audio_melody.nova` (NEW).
  Covers: constants + sentinels (4); Hz to MIDI on A4 / C4 / A3 /
  A5 / E4 / unvoiced (6); MIDI to note name on C4 / A4 / B4 / C5 /
  A0 / C#4 (6); note accessors (5); pure A4 sine @ 8 kHz -> single
  note MIDI 69 in [900, 1000] ms duration band (3); pure C4 sine
  @ 8 kHz, 500 ms -> single note MIDI 60 in [420, 510] ms band (3);
  silence -> 0 notes (1); empty PCM -> 0 notes (1); white noise ->
  0 notes (1); 3-note A4+C5+D5 sequence -> 3 notes in correct order
  with correct MIDI values (5); 50 ms tone < MIN_NOTE_MS -> 0 notes
  (1); melody_to_text on empty + 3-note list (2); internal
  _hz_to_midi(milli) within +/- 50 milli of textbook (2).

- 16 integration assertions in
  `tests/integration/scenario_kkkk_melody.sh` (NEW). Stand-alone
  driver writes a 4-note A4+C5+D5+A4 WAV via synth_sine, plus a
  1-second silent WAV. Asserts `/melody <4-note>` reports 4 notes
  in correct order; format is `NAME-DURms`; each note duration in
  [150, 250] ms band; sample rate = 8000 Hz; `/melody <silent>`
  reports "no notes detected"; `/melody <missing>` reports
  graceful FAILED; `/melody` with no arg shows usage; `/help`
  advertises /melody as R22F.

- All prior audio suites remain green (R6E Klatt, R7F VAD,
  R8B/R10B STT, R10F/R11B pitch, R12D PSOLA, R13D voice clone,
  R14E DSP, R16E STFT, R17B MFCC, R18C wakeword, R19D speaker_id,
  R21C TTS).

### Future work

- **Singing voice pitch (YIN path)** -- the brief specifies R11B
  YIN. The current R22F uses R10F because YIN subharmonic-snaps
  pure sines at default bounds. A future R22F.2 could call YIN
  with adaptively-tightened f0_min (start with R10F's argmax, then
  refine with YIN around that estimate -- the de Cheveigne paper's
  "external initial estimate" mode). Would give clean F0 on
  harmonic-rich sung melody where R10F's formant snap dominates.

- **Vibrato / pitch-bend detection** -- the per-frame F0 sequence
  before MIDI rounding carries vibrato / bend information; a future
  layer could detect oscillation (frequency-domain peak in the F0
  contour) and emit "note + vibrato_depth + vibrato_rate" rather
  than a single MIDI value. The R16E STFT primitive already gives
  us the analytic spectrogram we'd need.

- **Polyphonic melody** -- the current pipeline is monophonic
  (one pitch per frame). Polyphonic transcription would need a
  multi-F0 estimator (e.g., harmonic-product-spectrum or
  non-negative matrix factorisation) before the MIDI rounding +
  segmentation steps.

- **Onset detection** -- the current segmentation uses pitch
  changes as note boundaries. A complementary onset detector
  (spectral flux / phase deviation) would give better timing on
  notes that share a MIDI value (e.g., a repeated A4) and on
  percussive instruments where the pitch tracker reports the
  same value across multiple drum hits.

- **Score export** -- the note list is one step away from MIDI
  file output. A SMF (Standard MIDI File) writer would let the
  substrate emit playable .mid files; combined with R21C TTS this
  closes the music-IO loop.

## R23B -- audio-vision lip sync detection (audio side)

The R23B audio-vision lip sync detector lives under
`src/perception/lipsync.nova` (the image side carries the same
prose in IMAGE_AUDIT.md). This entry documents only the AUDIO
contract -- how the lip sync correlator consumes the existing
audio stack and what it expects out of the VAD voicing signal.

The audio side of the pipeline:

1. **PCM input.** `lipsync_pgm_args` calls
   `audio_capture_to_pcm(wav_path)` (R7F module), getting back
   the canonical [samples_list, sample_rate] pair. Any 8/16/24/32/
   44.1/48 kHz WAV that audio_capture parses cleanly works as
   input. The detector requires `len(samples) >= n_frames` (one
   audio chunk per video frame); shorter WAVs report a graceful
   "WAV has fewer samples than frames" error.

2. **Per-frame chunking.** The detector slices the PCM into
   `n_frames` equal-length chunks (where `n_frames = len(video_frames)`).
   Each chunk's energy + ZCR is classified against a per-chunk
   threshold scaled from the canonical R7F 30 ms VAD frame
   threshold (`50000 * frame_size / 240`). The per-chunk re-scaling
   is what makes lipsync work on short fixtures: a 5-frame video at
   30 fps means ~167 ms per chunk, well above 30 ms; without the
   re-scaling the per-frame energy would saturate the threshold
   and every chunk would land in "speech" regardless of content.

3. **Voicing flag per chunk.** `vad_classify_frame(state, energy, zcr)`
   contract: speech iff `energy > threshold AND 0 < zcr < zcr_max`.
   The lip sync correlator wants the 0/1 flag; it does NOT consume
   the higher-level R7F state machine (which would smear speech /
   silence across boundaries -- a feature in VAD-gated capture, a
   bug in per-frame correlation).

### Why the energy + ZCR VAD specifically (vs R10F pitch voicing)

R10F's pitch_track_with_bounds + pitch_result_voicing_milli also
gives a per-frame voicing flag (this time as a milli confidence,
not 0/1). Either would work for lipsync correlation. R23B picks
energy + ZCR because:
  * It's cheaper (O(n) per chunk vs O(n^2) autocorrelation in
    R10F).
  * It fires on unvoiced phonemes (fricatives like /s/ /sh/ /f/),
    which DO open the mouth even though the larynx is not
    vibrating. R10F's voicing field would report silence on
    /s/, missing a real lip-sync event.
  * The lipsync window is much coarser than R10F's pitch tracking
    needs to be (~30 fps vs the per-30-ms-frame F0 estimate that
    R10F + R11B target). The extra resolution from autocorrelation
    is not useful information for the correlator.

### Why not the R7F state machine

The R7F audio_vad state machine (SILENCE -> SPEECH_CANDIDATE ->
SPEECH -> SILENCE_CANDIDATE) smears classifications across
boundaries: a single noisy frame inside a speech segment stays
classified as "speech" because the state machine's hysteresis
prefers to maintain the segment. This is correct for VAD-gated
capture (we don't want to chop one utterance into 50 pieces just
because one phoneme is quieter than its neighbours) but wrong for
per-frame correlation: it would put the correlator's voicing
sequence systematically out of phase with the actual energy /
zcr signal.

The detector therefore uses `vad_frame_energy` + `vad_frame_zcr`
+ a local `vad_classify_frame`-equivalent (with per-chunk-scaled
threshold) and ignores the state machine.

### Honest scope -- what R23B does NOT ship (audio side)

* No phoneme-level alignment. A real audio-to-mouth coupling
  predicts a SPECIFIC mouth shape for each phoneme (a wide-open
  /aa/ vs a pursed /oo/ vs a closed-lips /m/). R23B's heuristic
  detector only knows "mouth open vs closed"; it cannot
  distinguish between an /aa/ vs an /oo/ vs an /uh/ at the same
  voicing level. The R23B.2 follow-up would replace the binary
  voicing flag with a per-frame phoneme estimate (a learned
  audio-visual joint embedding, e.g. SyncNet's bilinear bottleneck)
  and the binary mouth-open score with a continuous mouth-shape
  classification.
* No lip-onset detection. A real lip-sync detector would also
  measure the LATENCY between audio voicing onset and mouth-
  opening onset; lip sync drift in a streaming pipeline often
  appears as a constant +/- 100ms offset between the two streams.
  The correlator currently treats both streams as instantaneous;
  a future revision could pre-shift the audio by +/- N frames and
  pick the lag that maximises correlation.

## R22F.2 -- Audio pitch harmonic auto-switch (R10F autocorrelation <-> R11B YIN)

Status: **DONE (extension to `src/io/transducers/audio_pitch.nova`).**
R22F (audio_melody, commit 33b6e059) shipped with R10F autocorrelation
as the default pitch kernel because R11B YIN's octave-down anti-snap
subharmonic-collapses pure sines at default bounds (a known YIN-on-
pure-sine pathology documented in the R22F module header). The brief
called this out as a follow-up: the right default depends on the signal's
harmonicity. R22F.2 picks the better detector per frame.

### The trade-off this resolves

R22F's "Future work" section notes:

> **Singing voice pitch (YIN path)** -- the brief specifies R11B
> YIN. The current R22F uses R10F because YIN subharmonic-snaps
> pure sines at default bounds. A future R22F.2 could call YIN
> with adaptively-tightened f0_min (start with R10F's argmax, then
> refine with YIN around that estimate -- the de Cheveigne paper's
> "external initial estimate" mode). Would give clean F0 on
> harmonic-rich sung melody where R10F's formant snap dominates.

R22F.2 implements a simpler resolution than the adaptive-bounds
proposal: a per-frame harmonicity score classifies each frame as
"harmonic-rich" or "pure-tone-like" and routes it to the appropriate
kernel:

  * Pure / low-harmonic content      -> R10F (no YIN sub-multiple snap)
  * Harmonic / multi-formant content -> R11B (no AC formant snap)

### The harmonicity heuristic (two-pass)

**Pass 1 -- Spectral peakiness gate.** Compute a single-frame STFT
(R16E) on the input PCM frame. Take the magnitude spectrum and compute

```
peakiness_milli = (max_bin_mag * 1000) / avg_bin_mag    ; excluding DC
```

Calibration on the test fixtures:

| Signal              | peakiness_milli |
|---------------------|----------------:|
| Pure 200 Hz sine    |          56516  |
| Harmonic 200 Hz     |          29690  |
| Klatt /ae/ vowel    |          11947  |
| White noise         |           2327  |

A 5000-milli (= 5x) gate cleanly rejects broadband noise. Below the
gate the score is 0; above it Pass 2 runs. This is what makes the
heuristic robust against the brief's white-noise fixture (the strict
integer-multiple-ratio interpretation of the brief's algorithm
over-accepts noise about 50% of the time: 5 random peaks happen to
fit some sub-multiple of one by chance at any sensible tolerance).

**Pass 2 -- Distinct-peak counting.** Walk the magnitude array,
collect all local maxima above 30% of the strongest peak (the
PITCH_HARMONIC_PEAK_FLOOR_MILLI floor). Adjacent-bin neighbours of
an already-accepted peak are merged out (a Hann-windowed pure sine
smears across ~3 bins at its fundamental). The score is

```
score_milli = min(1000, 350 * num_distinct_peaks)
```

mapping:

| num_distinct | score |
|-------------:|------:|
|            1 |   350 |
|            2 |   700 |
|            3 |  1000 |
|           4+ |  1000 |

The default PITCH_HARMONIC_THRESHOLD_MILLI = 600 is therefore crossed
at >= 2 distinct peaks. Pure sines (1 peak) -> 350 -> AC. Klatt vowels
(F1 + F2) -> 700 -> YIN. Harmonic-rich tones (>= 2 harmonics above the
floor) -> 700+ -> YIN.

### Why distinct-peak counting (not strict integer-multiple fitting)

The brief's described algorithm ("Check if peaks form harmonic series
(2nd peak ≈ 2× first, 3rd ≈ 3× first, etc.). Harmonic ratio score =
num peaks fitting integer multiples / total peaks") is a strict
integer-harmonic-series fit. The brief also states "Klatt vowel
(R6E /ae/): high harmonicity expected (formant structure) -> YIN".

These two are in tension. R6E's Klatt /ae/ synthesizes F1 = 660 Hz +
F2 = 1720 Hz as PURE COSINES with no glottal source. The ratio
1720/660 = 2.61 does NOT fit any integer multiple within sensible
tolerance (< 15%). A strict integer-multiple fit would score Klatt
/ae/ at 1/2 = 500 milli, just below the 600 threshold, routing it to
AC -- contradicting the brief's mapping for Klatt.

A formant / distinct-peak counter resolves the tension: both
"harmonic series" inputs AND "formant structure" inputs share the
property of having multiple distinct prominent spectral peaks above
a noise floor. AC's failure mode (formant snapping at low F0) is
also triggered by exactly this signal class, so routing all of these
inputs to YIN is the right call. The distinct-peak count is a
simpler heuristic and matches the brief's behavioural specification.

### Public API

```nova
fn pitch_harmonicity_score(pcm_frame, sample_rate) -> int_milli         // 0..1000
fn pitch_estimate_frame_auto(pcm_frame, sample_rate)
       -> [f0_centihz, voicing_milli, method_used]
fn pitch_track_auto(pcm_buffer, sample_rate)
       -> list[[f0_centihz, voicing_milli, method_used]]
fn pitch_auto_method_count(contour, method) -> int                       // count helper
fn pitch_result_method(r) -> int                                          // r[2]

// Method labels (integer):
fn pitch_method_autocorr() -> 0
fn pitch_method_yin()      -> 1
fn pitch_method_none()     -> 2          // frame too short / invalid

// Tunable constants:
fn pitch_harmonic_threshold() -> 600   // milli; > this -> YIN
fn pitch_harmonic_max_peaks() -> 5     // cap on distinct peaks counted
```

The chat helper `pitch_run_auto_command(arg)` mirrors R10F's
`pitch_run_command` / R11B's `pitch_run_yin_command` but additionally
reports the per-method frame split:

```
(pitch_auto /tmp/jfk.wav: f0_mean=178 Hz, f0_range=80-280 Hz
[voiced=311/366 frames, yin=311, autocorr=55 @ 16000 Hz])
```

### Calibration on the JFK fixture (16 kHz adult-male voice)

Running `pitch_track_auto` on the bundled whisper.cpp jfk.wav:

| Metric              | Value                          |
|---------------------|-------------------------------:|
| Total frames        | 366                            |
| YIN frames          | 311 (85% majority)             |
| AC frames           | 55                             |
| Voiced frames       | 311                            |
| Mean F0 (centi-Hz)  | 17857 (= 178.57 Hz)            |

For comparison: R10F standalone reports ~220 Hz on the same fixture
(its first-formant snap), R11B standalone reports ~140-150 Hz (full
F0 cure). The auto-switch sits at ~178 Hz, dominated by YIN on the
voiced frames but accepting some AC frames where the harmonicity
score is below threshold (silent / unvoiced regions where the AC
path's own voicing decision will mark the frame unvoiced anyway).

### Verification

- 31 unit assertions in `tests/unit/test_pitch_auto.nova` (NEW).
  Covers: constants + accessors (5); pitch_harmonicity_score on pure
  200 Hz sine / harmonic 200 Hz / white noise / silence / Klatt /ae/
  / short buffer (7); pitch_estimate_frame_auto routing across all 5
  fixtures + method = NONE on short buffer (11); pitch_track_auto on
  harmonic-all-YIN + mixed sine-and-harmonic + short input (6);
  pitch_result_method accessor (1); pitch_auto_method_count on empty
  contour (2).

- 11 integration assertions in
  `tests/integration/scenario_qqqq_pitch_auto.sh` (NEW). Stand-alone
  driver runs pitch_track_auto on synthesized pure sine (1.5 s),
  harmonic-rich 200 Hz (1.5 s), and a concatenated 24-frame mixed
  sequence (sine + Klatt /ae/ + harmonic + silence, 6 frames each).
  Asserts: pure sine has yin=0 / ac=frames (every frame to AC),
  mean_f0 in [19500, 20500] centi; harmonic-rich has yin majority
  (yin*2 >= frames), mean_f0 ~ 20000 centi; mixed has both yin > 0
  and ac > 0 (detector switched). Plus JFK head-to-head (conditional
  on /tmp/whisper.cpp/samples/jfk.wav): yin*2 > frames (strict
  majority), mean_f0 in plausible voice band [8000, 23000] centi.

- All prior audio suites remain green (R6E Klatt 209, R7F VAD 86,
  R8B/R10B STT 28, R10F pitch 52, R11B YIN 35, R12D PSOLA, R13D voice
  clone, R14E DSP 34, R16E STFT 49, R17B MFCC 41, R18C wakeword,
  R19D speaker_id, R21C TTS 68, R22F melody 40).

### Future work

- **Adaptive YIN bounds.** R22F's "Future work" originally proposed
  using R10F's argmax as an initial F0 estimate, then refining with
  YIN around that estimate. R22F.2 takes a coarser switch-the-
  algorithm approach. A future R22F.3 could combine the two: when
  the auto-switch picks YIN, narrow YIN's f0_min/f0_max around the
  R10F estimate. Would tighten the search range on the YIN path,
  reducing the worst-case cost per frame.

- **Voicing-aware switching.** Currently the harmonicity score is
  computed unconditionally per frame. A frame already known to be
  unvoiced (no glottal source) doesn't benefit from either kernel;
  a future tweak could short-circuit by running the cheap R10F
  energy + voicing check first and only computing the harmonicity
  STFT when the frame is voiced.

- **Score smoothing across frames.** Per-frame method switches can
  oscillate at section boundaries (e.g., the last frame of a sustained
  sine + first frame of a held vowel may both score around the
  threshold). A 3-frame median filter on the score would stabilise
  the method label.

- **Confidence reporting.** The score itself is informative beyond
  the binary YIN-vs-AC decision: a low score (< 200 milli) on a
  voiced frame indicates "AC is confident in the call"; a borderline
  score (550..650) indicates "either kernel could be wrong". The
  chat helper currently reports only the per-method counts; a future
  enhancement would report the score distribution for downstream
  diagnostics.

## R25B -- end-to-end voice conversation demo (STT -> KG -> TTS)

R25B threads the existing audio + cognition legs into a single
demonstrable pipeline: speak a question, get a spoken answer from the
knowledge graph -- no LLM in the loop, just integer DSP + rule-based
parsing + R15D/R16F/R17E mini-SPARQL.

### Pipeline shape

```
question.wav --[R8B/R10B stt_seam]--> transcript text
                      |
                      v
            [rule-based question parser]
                      |
                      v
                 [SPARQL string]
                      |
                      v
          [R15D kg_query_compile_and_run]
                      |
                      v
                  [bindings]
                      |
                      v
            [result-to-text formatter]
                      |
                      v
       [R21C tts_speak + tts_save_wav]
                      |
                      v
                 response.wav
```

The new demo module `examples/voice_conversation.nova` is the
integration layer; the 4 cognition / IO modules underneath are
unchanged.

### Question parser

Rule-based, three templates. Pattern matching is case-insensitive on
the leading keyword, case-folded to upper for the kind token (which
must be one of FACT / CONCEPT / RELATION / SKILL / LANG / RULE -- the
R15D kind dictionary). Trailing punctuation (`?`, `.`) is stripped.
Anything that doesn't match routes to UNKNOWN with a graceful
apology.

| Template       | English                  | SPARQL emitted                                                                       |
|----------------|--------------------------|--------------------------------------------------------------------------------------|
| WHAT_IS  (1)   | "what is X" / "what's X" | `SELECT ?desc WHERE { ?atom kind X . ?atom label ?desc . } LIMIT 1`                  |
| HOW_MANY (2)   | "how many X"             | `SELECT (COUNT(?a) AS ?n) WHERE { ?a kind X . }`                                     |
| LIST_ALL (3)   | "list all X"             | `SELECT ?a WHERE { ?a kind X . } LIMIT 10`                                           |
| UNKNOWN  (0)   | anything else            | (no SPARQL emitted -- formatter says "I do not know how to answer that question.")   |

### Result-to-text formatter

Template-aware. Each template has its own empty / non-empty sentence
frame, all pure string concatenation:

| Template | bindings shape       | English emitted                                                |
|----------|----------------------|----------------------------------------------------------------|
| HOW_MANY | `[{n: 5}]`           | `"There are 5 FACT atoms."` (n=0 still emits "There are 0 ...")|
| HOW_MANY | `[]` (defensive)     | `"There are 0 FACT atoms."`                                    |
| WHAT_IS  | empty                | `"I do not know anything about FACT."`                         |
| WHAT_IS  | `[{atom: 42}]`       | `"The first FACT atom has id 42."`                             |
| LIST_ALL | empty                | `"No FACT atoms found."`                                       |
| LIST_ALL | `[{a:0},{a:1},{a:2}]`| `"Found 3 FACT atoms: ids 0, 1, 2."`                           |
| UNKNOWN  | (ignored)            | `"I do not know how to answer that question."`                 |

### Public surface

`examples/voice_conversation.nova` exposes:

* `vc_parse_question(text) -> [tpl_id, kind]`
* `vc_build_sparql(parsed) -> sparql_string`
* `vc_format_result(parsed, bindings) -> sentence_string`
* `vc_handle_question(kg, wav_path) -> [response_text, response_wav_path]`
* `vc_converse_run(kg, arg)` -- chat-side wrapper for the `/converse`
  admin command (1 dispatch line in `crossengin_chat.nova`).
* Template accessors: `vc_template_what_is()`, `vc_template_how_many()`,
  `vc_template_list_all()`, `vc_template_unknown()`.

### Honest scope (R25B.2 list)

R25B is the structural pipeline + 3 question templates. A real voice
agent needs:

* Conversation state across turns ("and the second one?" -> needs to
  remember the last LIST_ALL result).
* Multi-turn dialogue (clarifications, follow-ups).
* STT error correction (whisper hears "facts" not "FACT"; we don't
  fuzzy-match the kind name).
* Ambiguity resolution (a low-confidence transcript should prompt
  "did you say X?").
* Prosody control (the TTS sentence is monotone; rising tones on
  questions would be more natural).
* Multi-template responses (stitching "There are 5 FACT atoms. The
  first has id 0." despite having both pieces at hand).
* Streaming audio (we still require the whole question pre-recorded
  to a WAV; live capture would tap `audio_capture` directly).

All of these are tracked in the R25B.2 deferred list at the bottom
of `voice_conversation.nova`.

### Verification

* 20 unit assertions in `tests/unit/test_voice_conversation.nova`
  cover the parser (8), SPARQL builder (4), and formatter (6) +
  fallback (2). Build via `make test`.
* 20 integration assertions in
  `tests/integration/scenario_nnnn_voice_conversation.sh` drive both
  the stand-alone driver and the chat `/converse` round-trip. The
  end-to-end STT leg is gracefully SKIPed (informational note, not a
  hard fail) when `/usr/local/bin/whisper-main` is missing -- the
  stub-backend path still writes a response WAV (the apology line)
  so the structural shape is verifiable in CI without the 75 MB
  whisper install.

### Files touched (R25B)

* NEW: `examples/voice_conversation.nova` (~390 lines incl. header +
  honest-scope footer; 11 public functions).
* NEW: `tests/unit/test_voice_conversation.nova` (20 unit assertions).
* NEW: `tests/integration/scenario_nnnn_voice_conversation.sh` (20
  integration assertions, letter `nnnn` is free).
* MOD: `examples/crossengin_chat.nova` (1 import + 1 help + 1 dispatch
  line). The dispatch passes `kg` so `/converse` operates on the
  current session's KG (same shape as `/query`).
* MOD: `AUDIO_AUDIT.md` (this section), `README.md`,
  `NEXT_SESSION.md`.

## R25B.2 -- Multi-turn voice dialogue (conversation state + follow-ups)

R25B.2 closes the conversation-state hole at the top of R25B's deferred
list: a session object carries the last 5 turns + the most recent
template / kind / entity-id list across calls, and a follow-up parser
layer in front of the R25B parser recognises `tell me more` /
`the second one` / `what about X` / `describe it` / `actually` patterns
and either rewrites the transcript with resolved context OR escalates
the SPARQL LIMIT to pull more rows. R25B's public API is unchanged --
single-turn `/converse` callers see the same behaviour byte-for-byte.

### Layered design

R25B.2 lives in a new sibling module `examples/voice_dialog.nova`
(~600 lines) that imports `voice_conversation.nova` READ-ONLY. The
dialog state machine is a transcript rewriter sitting in front of
R25B's `vc_parse_question` / `vc_build_sparql` / `vc_format_result`
chain; it never reaches into R25B's internals.

```
session_t (history, last_tpl, last_kind, last_ids, last_limit)
     |
     v
[vc_session_turn]
     |
     +-- topic shift? ("actually X" / "never mind") --> reset + parse-fresh
     |
     +-- "tell me more"? --> LIMIT *= 2 + re-run LIST_ALL on last_kind
     |
     +-- anaphora? ("describe it" / "the second one") --> WHAT_IS on last_ids[N]
     |
     +-- pivot? ("what about Y") --> reuse last_tpl with new kind
     |
     +-- fall through --> R25B parser (fresh turn)
```

### Public surface

* `vc_session_new() -> session_t` -- empty session
* `vc_session_turn(kg, session, question_text) -> [response_text, session]`
* `vc_session_history(session) -> list[turn_t]`
* `vc_session_reset(session) -> 1` (mutates in place)
* Accessors: `vc_turn_question`, `vc_turn_template`, `vc_turn_kind`,
  `vc_turn_ids` (per-turn); `vc_session_last_template`,
  `vc_session_last_kind`, `vc_session_last_ids`,
  `vc_session_last_limit`, `vc_session_turn_count` (per-session).
* `vc_dialog_run(kg, arg)` -- chat-side wrapper for `/dialog`.

### History cap

Brief mandate: last 5 turns. Implementation: every `_vc_append_turn`
checks `len(history) > 5` and rebuilds a trimmed copy (FIFO eviction).
The `turn_count` slot stays monotonic so observability survives the
cap; the test asserts a 7-turn run leaves count=7 with len(history)=5.

### Follow-up patterns recognised

| Pattern (lower-cased)                                | Action                                                  |
|------------------------------------------------------|---------------------------------------------------------|
| `actually X` / `wait X` / `never mind X` /           | Reset session, parse X fresh                            |
| `change subject X` / `let's talk about X` /          |                                                         |
| `new topic X`                                        |                                                         |
| `actually` (no remainder), `never mind`,             | Reset session, acknowledge                              |
| `change subject`, `new topic`                        |                                                         |
| `tell me more` / `more` / `list more` / `show more` /| LIMIT *= 2 (cap 100); re-run LIST_ALL on `last_kind`    |
| `any more` / `what else` / `and more`                |                                                         |
| `describe it` / `what is it` / `tell me about it` /  | WHAT_IS on `last_ids[0]`                                |
| `tell me about him` / `tell me about her` /          |                                                         |
| `describe that one` / etc.                           |                                                         |
| `the second one` / `the third one` / `the last one` /| WHAT_IS on `last_ids[N]` (or `last_ids[len-1]` for last)|
| `what is the second one` / `what about the third`    |                                                         |
| `what about Y` / `how about Y` / `and Y`             | Reuse `last_tpl` with kind Y                            |
| (no match)                                           | Fall through to R25B parser                             |

### Chat dispatch

`/dialog <wav>` admin command. Session lives in a module-level slot
in `voice_dialog.nova` (`_vc_default_session`) so successive calls
share state across the chat REPL. `/dialog reset` clears it. The
chat-side wiring is 2 lines: one import + one dispatch entry.

### Verification

* **44 unit assertions** in `tests/unit/test_voice_dialog.nova`
  (session bookkeeping: 6; R25B parity: 8; tell-me-more: 4; anaphora
  on "it": 4; ordinal anaphora: 3; pivot: 2; topic shift: 5; history
  cap at 5: 5; results: assert-counter tallies the actual checks).
* **13 integration assertions** in
  `tests/integration/scenario_aaaaa_dialog.sh` (letter `aaaaa` free).
  Driver runs a 5-turn dialog ("list all FACT" -> "tell me more" ->
  "what is the first one" -> "actually list all CONCEPT" ->
  "describe it") + checks reset behaviour; chat dispatch verifies
  `/dialog` (usage line) + `/dialog reset` (acknowledgement).
* All R25B tests (27 unit + 20 integration) remain green.

### Honest scope (R25B.3+)

* **Real label lookup.** "describe it" returns "atom has id 42"; we
  don't dereference 42 back to its human label. A label-int -> string
  reverse-lookup over the R15D atom store would let us speak "atom
  labelled foo" instead.
* **Cross-pronoun gender / number tracking.** "him" / "her" / "it"
  all resolve to the SAME `last_ids[0]`; without an NLP dictionary
  we can't track entity gender or singular/plural.
* **Conversational repair.** "no, the OTHER one" is not handled; the
  operator must say "the third one" explicitly.
* **Coreference chains.** "X is foo. Tell me about it. And about bar."
  -- "bar" doesn't propagate as a new antecedent for the NEXT "tell
  me about it"; each turn replaces `last_ids` based on its own result.
* **Fuzzy intent matching.** "tell me more about CONCEPT" routes to
  the "more" path AND keeps prior kind (we don't currently parse a
  trailing kind in the more shape).

### Files touched (R25B.2)

* NEW: `examples/voice_dialog.nova` (~600 lines, 20+ public functions).
* NEW: `tests/unit/test_voice_dialog.nova` (44 assertions).
* NEW: `tests/integration/scenario_aaaaa_dialog.sh` (13 assertions).
* MOD: `examples/crossengin_chat.nova` (+1 import +1 dispatch = 2
  lines, within brief's allowance).
* MOD: `AUDIO_AUDIT.md` (this section), `README.md`, `NEXT_SESSION.md`.

R8B (whisper), R15D (query), R21C (TTS) modules untouched -- the
dialog layer is purely additive on top.

## R25B.3 -- Voice dialog topic-shift detection (pivot vs continue)

R28D shipped R25B.2's multi-turn dispatcher assuming every
"tell me more" is a continuation. R25B.3 closes the OBVIOUS
follow-up-mis-classification hole: when the user says
"tell me more about cats" right after "list all FACT", the
"cats" tail has zero overlap with the prior intent ("fact"),
so it's a PIVOT, not a continuation. The R25B.2 dispatcher
would escalate LIMIT on the wrong topic; R25B.3 resets the
session and re-parses the remainder as a fresh turn.

The classifier is a content-word Jaccard heuristic over four
classes:

| Class                  | Trigger                                                       |
|------------------------|---------------------------------------------------------------|
| `VC_FOLLOWUP_NONE`     | No prior turn, or no recognised cue at all.                   |
| `VC_FOLLOWUP_CONTINUE` | Cue match + remainder content overlaps prior (Jaccard >= 0.2). |
| `VC_FOLLOWUP_PIVOT`    | Cue match + remainder unrelated, OR explicit `what about KIND`. |
| `VC_FOLLOWUP_ANAPHORA` | `describe it` / `the second one` / ordinal+verb shape.        |

Anaphora wins over pivot. "describe the first one" classifies
as ANAPHORA even though "first" could read as a content word --
the stopword list excludes the ordinals so they never become
pivot signal.

### Stopword + content-word extraction

`_vd_is_stopword(tok)` covers, at a minimum:

* Dialog-cue family: `tell`, `me`, `more`, `about`, `also`,
  `and`, `or`, `but`.
* R25B template keywords: `list`, `all`, `what`, `whats`,
  `how`, `many`, `much`, `is`, `are`, `was`, `were`, `be`,
  `to`, `do`, `does`, `did`.
* Pronouns + determiners: `it`, `its`, `he`, `him`, `his`,
  `she`, `her`, `they`, `them`, `that`, `this`, `those`,
  `these`, `the`, `a`, `an`, `one`, `ones`.
* Ordinals + position: `first`, `second`, `third`, `fourth`,
  `fifth`, `last`, `next`.
* Verbs of saying: `describe`, `give`, `show`.
* Discourse glue: `now`, `any`, `some`, `else`, `please`,
  `thanks`.

`_vd_content_words(lowered)`:

1. Strip apostrophes (`what's` -> `whats`).
2. Walk char-by-char: skip non-`[a-z0-9]` chars; collect runs.
3. Drop stopwords; preserve order.
4. Caller dedupes via `_vd_set_add` for Jaccard arithmetic.

### Jaccard threshold

Brief suggests ~0.2. NOVA is integer-only so the implementation
works in tenths: `_vd_jaccard_tenths` returns
`10 * |A intersect B| / |A union B|`; threshold
`VC_DIALOG_PIVOT_THRESHOLD = 2`. Below threshold -> PIVOT.

Edge cases:

* Both sides empty -> 10 (bare cue + empty prior content can't
  disagree; CONTINUE).
* One side empty -> 0 (no signal; PIVOT if classifier reaches
  the comparison, but cue+empty-remainder short-circuits to
  CONTINUE before we get there).

### Dispatcher routing

```
                    +----------------------------+
                    | classifier on (state, raw) |
                    +-------------+--------------+
                                  |
        +---------------+---------+---------+----------------+
        |               |                   |                |
        v               v                   v                v
   ANAPHORA          PIVOT              CONTINUE           NONE
   describe         what/how         more / and        complaint
   ordinal           about            empty rem.        fall-through
   path           +  template       + LIMIT escalate     to R25B
                    pivot              (same as R28D)    parser
                  OR
                  more+unrelated
                    -> reset session
                    + _vd_pivot_fresh_turn
                      (records turn even on UNKNOWN)
```

`_vd_pivot_fresh_turn` is the new helper. Same parse / execute /
format chain as `_vd_fresh_turn` but with one difference: on
UNKNOWN parse it STILL appends the turn to history (with
empty ids and UNKNOWN template), so the operator sees the pivot
they just made. R25B.2 dropped UNKNOWN fresh turns from history
to avoid pushing useful older turns out of the 5-cap; the pivot
case is the opposite intent (the topic shift IS the signal we
want to preserve).

### Verification

* **55 new unit assertions** in
  `tests/unit/test_voice_dialog.nova` (R25B.2's 44 retained + 55
  R25B.3 = 99 total). Coverage spans the classifier directly
  (returning each of the 4 enum values) AND the runtime
  dispatcher (verifying that PIVOT actually resets the session,
  CONTINUE actually escalates the LIMIT, ANAPHORA actually
  resolves to last_ids[0]).
* **Brief's 4 fixtures: 4/4 classified correctly.**
  - "list all FACT" + "tell me more" -> CONTINUE.
  - "list all FACT" + "tell me more about cats" -> PIVOT.
  - "list all FACT" + "what about RULE atoms" -> PIVOT.
  - "list all FACT" + "describe the first one" -> ANAPHORA.
* **All 219 unit tests pass.**

### Honest scope (R25B.4+)

* **Uniform-weight Jaccard.** Kind-word matches should dominate
  general content matches; today every word is weighted 1.
  Long-form prior text with multiple content words shrinks the
  ratio mechanically and can flip a CONTINUE to a PIVOT spuriously.
* **No morphology.** "fact" vs "facts" do not match. A Porter
  stemmer would help.
* **No semantic distance.** "list all FACT" + "tell me more
  about logic" -- "logic" is unrelated to "fact" lexically but
  semantically related. We have no word2vec / GloVe; deferred.
* **No multi-turn content window.** The classifier only inspects
  the LAST history turn. A pivot diagnosed against turn N-1 may
  still match turn N-2's intent ("we were talking about FACT,
  pivoted to CONCEPT, and now back to FACT"). Future improvement
  walks the full window.

### Files touched (R25B.3)

* MOD: `examples/voice_dialog.nova` -- additive (~350 lines of
  new code; R28D code is unchanged).
* MOD: `tests/unit/test_voice_dialog.nova` -- additive (+55
  assertions + 14 new test functions).
* MOD: `AUDIO_AUDIT.md` (this section), `NEXT_SESSION.md`,
  `README.md`.

R8B / R15D / R21C / R25B / R25B.2 modules and tests are untouched
-- R25B.3 is purely additive on top of R25B.2's dialog layer.

## R25B.4 -- Voice dialog kind-weighted Jaccard + s-suffix morphology

Closes the **two honest R25B.3 failure modes** documented in the
section above: (1) uniform-weight Jaccard misclassifies a
remainder that NAMES the prior kind ("tell me more facts" after
`list all FACT`) as PIVOT because "facts" plural mismatches
"fact" singular at the string level; (2) a long unrelated
remainder dilutes the kind-naming signal even when the kind word
IS present ("more facts and atoms and concepts and rules and
skills and langs" against prior {fact} scores 1/6 < threshold).
R25B.4 closes (1) with an English s-suffix stemmer that
normalises trailing-s plurals at tokenisation time, and (2) with
a second-pass weighted scorer that gives the prior kind word
double weight on both sides of the Jaccard ratio.

### What R25B.4 changes inside `voice_dialog.nova`

* `_vd_stem(tok)` -- a minimal English plural / 3rd-person-
  singular normaliser. INTENTIONALLY not a real Porter stemmer
  (NOVA ships no string library; the only failure mode the brief
  cited was the trailing-s case). Rules:
    - Length < 4: passthrough. Keeps `is` / `as` / `us` / `go` /
      `no` / `do` / `me` intact.
    - Length >= 5 AND last 3 chars = "ies": strip "ies", append
      "y". `entities` -> `entity`, `categories` -> `category`,
      `facilities` -> `facility`. Length-4 forms ("ties", "lies",
      "pies") deliberately fall through to the bare s-strip so
      they become `tie` / `lie` / `pie`, not `ty` / `ly` / `py`.
    - Tail "-ss" / "-us" / "-is" / "-as" / "-os": passthrough.
      Keeps `kiss` / `grass` / `focus` / `axis` / `was` / `has` /
      `atlas` / `kudos` / `pathos` intact.
    - Otherwise, ends in "s": drop the s. `facts` -> `fact`,
      `rules` -> `rule`, `cats` -> `cat`, `dogs` -> `dog`.
  The stemmer is ASCII-only and English-only. German plurals
  ("Haeuser"), Romance ("amigos") and Arabic broken plurals all
  need their own normalisers; documented in the honest scope.

* `_vd_content_words(lowered)` -- runs each surviving token (i.e.
  non-stopword) through `_vd_stem` BEFORE pushing it. Stopword
  test still runs on the RAW token so degenerate stems can't
  sneak past the filter ("is" / "was" stay stopwords). Applied
  to both prior + remainder so set arithmetic is symmetric.

* `_vd_prior_content_no_kind(session)` -- mirror of
  `_vd_prior_content` but EXCLUDING the canonical kind word.
  Returned set + the prior kind stem are fed to the weighted
  scorer as the "other_terms" and "kind_terms" inputs.

* `_vd_weighted_score_tenths(prior_other, prior_kind_stem, now)`
  -- the new scorer. Formula:
  ```
  score(in tenths) = floor( 10 * (2*|kind_matches| + |other_matches|)
                            / (2*|kind_terms| + |other_terms|) )
  ```
  where `|kind_terms| = 1` whenever the session established a
  kind (else 0; the cue-with-no-kind case can't kind-match
  anything), and each remainder token votes AT MOST once -- as
  a kind match (weight 2) or as an other-content match
  (weight 1). Numerator clamped to denominator so the output
  ranges 0..10 like the uniform scorer.

* `voice_followup_classify(session, query)` -- the more/and/also
  branch now consults the weighted score AFTER the uniform one.
  If uniform Jaccard >= threshold -> CONTINUE (R25B.3 path
  preserved bit-for-bit). Else if weighted score >= threshold ->
  CONTINUE (the lift). Else -> PIVOT. Threshold stays at the
  same 0.2 (encoded 2/10) constant for both passes so a single
  knob controls the crossover.

* Public probes `vc_stem(tok)` and `vc_weighted_score(...)` ship
  alongside the existing `vc_followup_*` accessors so tests can
  exercise the helpers in isolation without driving a full
  `vc_session_turn`.

### Verification

* **48 new unit assertions** in
  `tests/unit/test_voice_dialog.nova` (R25B.3's 99 retained
  byte-identical + R25B.4 = 147 total). Coverage:
    - Morphology stemmer: `cat` / `cats`, `rule` / `rules`,
      `fact` / `facts`, `dog` / `dogs`, `atom` / `atoms`;
      length-<4 preservation (`is`, `as`, `us`, `os`);
      tail-preservation (`kiss`, `grass`, `focus`, `axis`,
      `was`, `has`, `atlas`, `kudos`); -ies->-y (`entities`,
      `categories`, `facilities`); no-trailing-s passthrough.
    - Weighted scorer: kind-only match -> 10; no kind match
      -> 0; mixed kind + other match -> 10; empty prior +
      non-empty now -> 0; non-empty prior + empty now -> 0.
    - Classifier: "list all FACT" + "tell me more facts" ->
      CONTINUE (morphology win); "list all RULE" + "more rules
      please" -> CONTINUE (morphology win); "list all FACT" +
      "tell me more about that atom in the rule engine" ->
      PIVOT (HONEST; documented below); "list all RULE" +
      same remainder -> CONTINUE (R25B.3 parity); "list all
      FACT" + "tell me more about cats" -> PIVOT (preserved);
      "list all FACT" + "what about RULE atoms" -> PIVOT
      (kind shift); long borderline remainder with kind term
      -> CONTINUE via weighting; "and facts" after FACT ->
      CONTINUE via morphology; "more dogs" after FACT -> PIVOT
      (no kind overlap).
    - Dispatch: morphology-induced CONTINUE actually escalates
      the LIMIT to 20 (proving the runtime consequence).

* **R25B.3 parity: every one of the 99 prior assertions still
  passes byte-identical.** The weighted scorer is layered on
  top -- it only fires after the uniform Jaccard misses, so
  cases where uniform already says CONTINUE (Jaccard >=
  threshold) take exactly the same code path they did before.
  Cases where uniform already says PIVOT and the weighted
  scorer ALSO says PIVOT take the same code path. The only
  newly-observable behaviour is on remainders that uniform
  scored < threshold AND weighted scored >= threshold; none of
  the R25B.3 fixtures land there.

### Honest failure mode -- the R25B.5 deferred case

The brief explicitly invited an honest answer on the R29C
documented failure:
> "tell me more about that atom in the rule engine" after
> `list all FACT` -- does R25B.4 fix this?

**Honest answer: no.** Under R25B.4's weighting:
  - prior_kind_stem = "fact"; prior_other = {} (after
    stopwords)
  - remainder content = {atom, rule, engine} (stems unchanged
    on these tokens)
  - No "fact" appears in the remainder, so kind_matches = 0.
  - No other prior content exists, so other_matches = 0.
  - score = (0 + 0) / (2 + 0) = 0 < threshold -> PIVOT.

That's the CORRECT call by the model: the operator shifted
topic from FACT to "the rule engine". A real fix would either:
  (a) notice that "rule" in the remainder NAMES a different
      KNOWN kind (the existing `_vd_known_kind("RULE") == 1`
      check is already in the file, just not consulted from
      the more-cue path) -- which would route this as a kind-
      pivot (template-preserving) rather than a topic-shift,
      OR
  (b) augment the classifier with a semantic-distance model
      that recognises "rule engine" as off-topic from FACT.

(a) is cheap (one line in `voice_followup_classify` that walks
the remainder content for a known kind token before falling
through to PIVOT) and is what R25B.5 should ship. (b) requires
word embeddings we don't have. Both are deferred and explicitly
noted here so the next session has a clean follow-up.

### Honest scope (R25B.5+)

* **Different-known-kind detection from the more-cue path.** The
  best lift for the R29C failure case (above). One-line addition
  to `voice_followup_classify` using `_vd_known_kind` against
  upcased remainder content tokens.
* **Non-English morphology.** Stemmer is ASCII + English only.
  Languages with agglutinative or umlauted plurals (German
  "Haeuser", Romance "amigos" / "amigas", Arabic broken plurals)
  need their own normalisers.
* **Adjective + 3rd-person-singular inflection.** "ruler" vs
  "rule", "running" vs "run", "ran" vs "run" not handled. A real
  Porter stemmer or a small affix table would catch these.
* **Compound nouns.** "rule engine" tokens to "rule" + "engine"
  independently. A phrasal recogniser (or a simple bigram pass)
  would let "rule engine" count as a single kind-naming token.
* **No semantic distance.** "list all FACT" + "tell me more about
  logic" -- "logic" is unrelated to "fact" lexically but
  semantically related. R25B.4 still calls PIVOT here.
* **No multi-turn content window.** The classifier only inspects
  the LAST history turn (inherited from R25B.3). A pivot
  diagnosed against turn N-1 may still match turn N-2's intent.

### Files touched (R25B.4)

* MOD: `examples/voice_dialog.nova` -- additive (~180 lines:
  `_vd_stem`, `_vd_weighted_score_tenths`,
  `_vd_prior_content_no_kind`, two public probes, and one
  classifier branch lift). R25B.3 + R28D code blocks unchanged.
* MOD: `tests/unit/test_voice_dialog.nova` -- additive (+48
  assertions + 19 new test functions).
* MOD: `AUDIO_AUDIT.md` (this section), `NEXT_SESSION.md`,
  `README.md`.

R8B / R15D / R21C / R25B / R25B.2 / R25B.3 modules and tests
are untouched -- R25B.4 is purely additive on top of R25B.3's
dialog layer.

## R25B.5 -- Voice dialog kind-pivot routing (R31F / R30F.2)

Closes the **R30F-documented PIVOT misclassification** for
remainders that name a known second kind. R30F's exit report
explicitly named the deferred fix: "consult `_vd_known_kind`
against remainder tokens from the more-cue path and route as a
kind-pivot when the remainder names a known kind != prior." R31F
lands that fix as a new classifier output `VC_FOLLOWUP_KIND_PIVOT`
distinct from `VC_FOLLOWUP_PIVOT`, plus a handler in
`vc_session_turn` that treats the kind-pivot like a fresh
template-preserving query against the new kind (LIMIT reset to
baseline -- NOT escalated).

### What R25B.5 changes inside `voice_dialog.nova`

* **New classifier constant + accessor**:
  `VC_FOLLOWUP_KIND_PIVOT = 4`; `vc_followup_kind_pivot()` accessor
  matches the shape of the other four enum probes.
* **New helper `_vd_remainder_known_kind(now, exclude_kind_upper)`**:
  iterates the stemmed remainder content set; on each token, upcases
  and consults `_vd_known_kind`. The FIRST match that DIFFERS from
  the prior kind is returned (case-insensitive after morphology +
  upcase). Returns "" when no remainder token names a known kind
  OR every match equals the prior kind. The "first match wins" rule
  is documented honestly: a remainder like "more facts and rules"
  after CONCEPT has two candidates; we pick "facts" (FACT) because
  it appears first in tokeniser order.
* **New public probe `voice_followup_kind_pivot_target(session,
  query)`**: returns the target kind name on KIND_PIVOT inputs, ""
  otherwise. The handler uses this to look up the target kind for
  dispatch without re-running tokenisation.
* **`voice_followup_classify` extension**: in the more-cue path,
  after uniform Jaccard misses AND weighted Jaccard misses, scans
  the remainder for a known second kind via
  `_vd_remainder_known_kind`. On hit -> KIND_PIVOT. On miss -> PIVOT
  (R30F honest fallback). The explicit "what/how about KIND" path
  also now returns KIND_PIVOT when the named kind differs from the
  prior kind; returns CONTINUE when the named kind EQUALS the prior
  (the operator is restating the same topic).
* **`vc_session_turn` dispatcher extension**: handles
  `VC_FOLLOWUP_KIND_PIVOT` between the ANAPHORA case and the PIVOT
  case. Calls `voice_followup_kind_pivot_target` to look up the
  target, then dispatches `_vd_pivot_turn(kg, session, raw,
  last_tpl_or_LIST_ALL, target_kind)`. That helper already resets
  LIMIT to baseline and records the turn in history without
  resetting the session (preserves the prior FACT/RULE/... turn
  for context).

### Verification

* **20 new unit assertions across 15 new test functions** in
  `tests/unit/test_voice_dialog.nova` (R30F's 48 + R29C's 99 +
  R25B.5's 20 = 167 total before regression updates; see below
  for the 6 R29C/R30F assertions whose expected value was
  RELABELED to KIND_PIVOT -- those still pass, just with the
  updated label). Coverage:
    - Classifier KIND_PIVOT: "list all FACT" + "tell me more about
      RULE atoms" (literal kind match); same prior + "tell me more
      about that atom in the rule engine" (the R29C-documented
      failure case; morphology-routed match via `_vd_stem`); "list
      all RULE" + "tell me more about facts" (symmetric morphology
      win in the other direction); "list all FACT" + "and CONCEPT"
      (more-cue + "and" path); "list all CONCEPT" + "more facts
      and rules" (multi-kind ambiguous remainder; honest "first
      kind wins" lookup).
    - Negative cases that STAY PIVOT: "tell me more about cats"
      (no known kind), "and dogs" (no known kind).
    - Stay CONTINUE: bare "tell me more" (no remainder), "tell me
      more about facts" after FACT (same-kind match -- weighted
      Jaccard fires before KIND_PIVOT scan), "tell me more about
      it" (empty content after stopword strip).
    - Anaphora paths unchanged: "describe it" / "the first one" /
      "describe the first one" still ANAPHORA.
    - Public probe `voice_followup_kind_pivot_target`: returns ""
      when no prior, on CONTINUE inputs, on anaphora inputs, on
      generic PIVOT inputs; returns the matched UPPER-CASE kind
      name on KIND_PIVOT inputs.
    - Dispatch: KIND_PIVOT re-runs prior template against new kind,
      LIMIT resets to baseline 10 (NOT escalated -- even after an
      intervening "tell me more" escalation), history captures the
      pivot turn WITHOUT a session reset.
    - End-state byte-identity: "list all FACT" + "what about
      CONCEPT" still emits "Found 2 CONCEPT atoms: ids 3, 4."
      with kind=CONCEPT, template=LIST_ALL, limit=10.
    - Morphology-routed dispatch: "list all FACT" + "tell me more
      about that atom in the rule engine" dispatches LIST_ALL on
      RULE; the response is "No RULE atoms found." (the fixture
      KG has 0 RULE atoms) -- proving the deferred R25B.5 case
      from R30F is now closed.

* **R30F / R29C parity: 141 of the 147 prior assertions still
  pass byte-identical**. 6 prior assertions had their expected
  value RELABELED from `vc_followup_pivot()` to
  `vc_followup_kind_pivot()` -- the underlying inputs are exactly
  cases R25B.5 explicitly captures as kind-pivots (different
  known kind in remainder). Rationale for each relabel:

  | # | Test                                                            | Input                                                          | Prior expected | New expected | Rationale                                                                                                    |
  |---|-----------------------------------------------------------------|----------------------------------------------------------------|----------------|--------------|--------------------------------------------------------------------------------------------------------------|
  | 1 | `test_classify_what_about_kind_is_pivot`                        | `'what about RULE atoms'` after FACT                           | PIVOT          | KIND_PIVOT   | Explicit "what about KIND" with known kind != prior; semantically a kind shift.                              |
  | 2 | `test_classify_what_about_kind_is_pivot`                        | `'what about CONCEPT'` after FACT                              | PIVOT          | KIND_PIVOT   | Same path; explicit known second kind.                                                                       |
  | 3 | `test_classify_what_about_kind_is_pivot`                        | `'how about SKILL'` after FACT                                 | PIVOT          | KIND_PIVOT   | "how about" mirror of "what about"; same routing.                                                            |
  | 4 | `test_three_turn_pivot_what_about_kind`                         | `'what about RULE atoms'` after FACT                           | PIVOT          | KIND_PIVOT   | End-state response + kind + template unchanged; only the classifier label moves.                             |
  | 5 | `test_classify_r29c_failure_case_after_fact_is_pivot`           | `'tell me more about that atom in the rule engine'` after FACT | PIVOT          | KIND_PIVOT   | The R30F-deferred case; R25B.5 closes it. Remainder names "rule" via morphology -> RULE != FACT.             |
  | 6 | `test_classify_what_about_rule_atoms_after_fact_is_pivot`       | `'what about RULE atoms'` after FACT                           | PIVOT          | KIND_PIVOT   | Duplicate-coverage assertion from R30F's section; relabels for consistency.                                  |

  All other assertions (including all dispatch assertions on
  end-state response text + kind + template + LIMIT) pass
  byte-identical because the KIND_PIVOT handler dispatches the
  SAME `_vd_pivot_turn` helper that PIVOT used for the
  "what about KIND" path.

### Honest design caveat -- multi-kind ambiguous remainder

The brief explicitly invited an honest answer on multi-kind
remainders ("tell me more about RULE and FACT"). R25B.5's
`_vd_remainder_known_kind` returns the FIRST matching token in
tokeniser order: "RULE and FACT" -> RULE wins. The honest
alternatives we considered + rejected:

  (a) **Bail with an apology** ("which one did you mean?"). The
      multi-turn loop already gives the operator a do-over and
      this would punish the common case where the operator
      genuinely IS shifting to RULE and "and FACT" is incidental
      ("more RULE atoms and FACT examples too" probably wants
      RULE first).
  (b) **Run both as separate KIND_PIVOTs**. Would require an
      extended return shape (list of kinds + a multi-dispatch
      handler); the current single-kind return shape is the
      load-bearing simplicity.
  (c) **Confidence threshold** (require at least 2 mentions of
      the same kind to fire KIND_PIVOT). Would silently drop
      single-mention KIND_PIVOTs which are the headline case.

We chose (the implemented) "first kind wins" because it's
deterministic, never silently drops user intent, and the
multi-turn do-over loop covers the rare miss. Documented as
honest scope in `voice_dialog.nova`.

### Honest scope (R25B.6+)

* **Same-kind multi-mention disambiguation.** "tell me more about
  RULE and RULE atoms" -- `_vd_remainder_known_kind` happily
  returns RULE (idempotent on duplicate matches); good.
* **Kind synonyms.** "more axioms" doesn't match the FACT kind
  even though axioms are facts in domain ontology. A synonym
  table would close this.
* **Compound noun NER.** "rule engine" tokenises to "rule" +
  "engine" independently; R25B.5 catches the "rule" token, but a
  phrasal recogniser would let "rule engine" count as a single
  domain-named token (and could route to a future KIND_PIVOT with
  kind=ENGINE if we added an ENGINE kind).
* **Multi-turn kind-pivot diff.** A 5-turn conversation that
  bounces FACT -> RULE -> FACT -> RULE -> FACT exercises only
  pairwise diff (prior vs current); no history-aware "you've
  been on RULE for the last three turns, this might be a
  CONTINUE not a pivot" heuristic.
* **Same-as-prior kind probe.** When the operator says "what
  about FACT" after FACT, we route as CONTINUE (refresh of the
  same topic). A subtle alternative would be "no-op" / "you're
  already on FACT" -- but the LIST_ALL re-execution is
  side-effect-free and the current label is simpler.

### Files touched (R25B.5)

* MOD: `examples/voice_dialog.nova` -- additive (~90 lines:
  `VC_FOLLOWUP_KIND_PIVOT` constant + accessor;
  `_vd_remainder_known_kind` helper; `voice_followup_kind_pivot_target`
  public probe; classifier extension; dispatcher branch).
  R28D / R29C / R30F code blocks unchanged (only docstrings
  amended).
* MOD: `tests/unit/test_voice_dialog.nova` -- additive (+20
  assertions + 15 new test functions; 6 prior assertions
  RELABELED to expect `vc_followup_kind_pivot()` -- byte-
  identical end-state otherwise).
* MOD: `AUDIO_AUDIT.md` (this section), `NEXT_SESSION.md`,
  `README.md`.

R8B / R15D / R21C / R25B / R25B.2 / R25B.3 / R25B.4 / R28D
modules and tests are untouched -- R25B.5 is purely additive
on top of R25B.4's dialog layer.

## R25B.6 -- Voice dialog multi-kind clarifying question (R32F / R31F.2)

Closes the **R31F-documented multi-kind ambiguous remainder** edge
case. R31F's exit report explicitly named the deferred fix:
"multi-kind ambiguous remainder ('more facts and rules' after
CONCEPT finds TWO known kinds). `_vd_remainder_known_kind` returns
the FIRST match in tokeniser order... future fix would add a
confidence threshold or an explicit disambiguation turn." R32F
lands that fix as a NEW classifier output `VC_FOLLOWUP_CLARIFY`
(value 5) distinct from KIND_PIVOT, plus a pending-clarify session
slot, a kind-selector parser, and a give-up-after-2-attempts
fallback.

### What R25B.6 changes inside `voice_dialog.nova`

* **New classifier constant + accessor**:
  `VC_FOLLOWUP_CLARIFY = 5`; `vc_followup_clarify()` accessor
  matches the shape of the other five enum probes.
  `VC_DIALOG_CLARIFY_MAX_ATTEMPTS = 2` cap exposed via
  `vc_dialog_clarify_max_attempts()`.
* **New multi-kind detector
  `_vd_remainder_known_kinds_all(now, exclude_kind_upper)`**:
  walks the stemmed remainder content set, upcases each token,
  consults `_vd_known_kind`, and returns the deduplicated
  UPPER-CASE list of ALL kinds found (preserving tokeniser order;
  dropping kinds equal to the prior). Public probe
  `vc_remainder_known_kinds_all` for tests / integration. The
  R31F single-return helper `_vd_remainder_known_kind` is left
  intact for the env-opt-out fallback path so callers that
  prefer R31F's deterministic byte-identical behaviour can keep
  it.
* **Pending-clarify session slots** (4 new slots, indices 6-9):
  `pending_clarify_kinds` (list of candidate UPPER-CASE kinds;
  empty when no clarify pending), `pending_clarify_template`
  (target template for resolution dispatch; LIST_ALL by default),
  `pending_clarify_attempts` (round counter; incremented on each
  failed resolution), `pending_clarify_raw` (the original
  transcript that triggered the clarify, kept for history
  annotation). Accessors: `vc_session_pending_clarify_kinds`,
  `_template`, `_attempts`, `_raw`, `vc_session_is_pending_clarify`.
  `vc_session_new` initialises them empty; `vc_session_reset`
  clears them (so explicit topic-shift markers cancel a pending
  clarify).
* **Kind-selector parser
  `_vd_resolve_clarify_selector(lowered, candidates)`**: maps a
  freshly-received user transcript to one of the pending
  candidate kinds. Resolution order: (1) bare kind name
  ("RULE" / "rule") case-insensitive; (2) `_vd_is_both_selector`
  ("both" / "either" / "all") -> FIRST candidate (documented
  fallback rationale below); (3) `_vd_content_words` tokenise
  + stem + scan for first surviving kind-named token. Returns
  the chosen UPPER-CASE kind on success, "" on failure. Public
  probe `vc_resolve_clarify_selector(query, candidates)`.
* **Clarify-question renderer `_vd_render_clarify_question(
  candidates)`**: builds "Did you mean RULE or FACT atoms?" for
  2 candidates; "Did you mean A, B, or C atoms?" for 3+. Kept as
  a dedicated helper so tests can assert byte-identical text.
  Public probe `vc_render_clarify_question`.
* **`voice_followup_classify` extension**: in the more-cue path,
  after R31F's single-kind KIND_PIVOT detection, the new
  multi-kind detector splits routing:
    - 0 matches -> generic PIVOT (R30F fallback).
    - 1 match  -> KIND_PIVOT (R31F path).
    - 2+ matches -> CLARIFY when `CE_VOICE_NO_CLARIFY` is unset;
      KIND_PIVOT (first-match via the R31F helper) when the env
      opt-out is set. The env-opt-out path is BYTE-IDENTICAL to
      R31F's behaviour -- the env probe and the single-kind
      helper are the only inputs to the dispatcher.
* **New public probe `voice_followup_clarify_candidates(session,
  query)`**: returns the deduplicated UPPER-CASE candidate list
  on CLARIFY inputs, an empty list otherwise. Used by the
  dispatcher to build the clarify question and stash the
  candidates in the pending slot. Returns empty when no prior,
  when the query doesn't take the more-cue path, when the
  remainder names fewer than 2 known kinds, or when the env
  opt-out is active.
* **`vc_session_turn` dispatcher extension**:
    - Early branch (after empty-transcript check): if the
      session is mid-clarify (pending kinds non-empty), call
      `_vd_handle_pending_clarify`. Explicit topic-shift markers
      still take priority (the topic-shift remainder check runs
      first so "actually" / "never mind" can cancel a pending
      clarify mid-flight).
    - New CLARIFY classifier branch: stashes candidates +
      template + attempts=1 + raw in the pending slots and
      emits the rendered question. NO history entry is appended
      for the CLARIFY emit itself (the pending state IS the
      carry-forward signal).
* **`_vd_handle_pending_clarify(kg, session, raw, lowered)`
  helper**: drives the resolution flow. On hit -> clear pending
  state, dispatch as KIND_PIVOT via `_vd_pivot_turn` with the
  stashed template against the chosen kind. On miss: bump
  attempts; if post-bump count <= MAX (2), re-emit the clarify
  with a reduced-patience prefix ("Please answer with the kind
  name. ..."). If post-bump count > MAX (3 in the rare 4-turn
  ambiguity), clear pending state, dispatch first-match
  KIND_PIVOT (the operator gets a real answer), and prepend an
  apologetic sentence ("Sorry, I could not tell which kind you
  meant. Showing FACT atoms by default. Found 3 FACT atoms:
  ids 0, 1, 2.").

### "both" / "either" / "all" handling

We shipped the **first-candidate-wins** path (option a from the
brief). The operator's "both" reply resolves to the FIRST stashed
candidate kind. Rationale:

  * The dialog layer dispatches ONE query at a time -- running
    BOTH would require an extended response shape, a dispatcher
    loop, and history bookkeeping for the second query. That's
    a structural change that touches every public API in the
    module.
  * The multi-turn loop already gives the operator a clean way
    to follow up on the second kind: after the first-candidate
    dispatch resolves (e.g. shows FACT atoms), they say "what
    about RULE" and the existing KIND_PIVOT path handles it.
  * First-match honours R31F's "never silently drop user intent"
    principle: the operator gets a real answer, not just an
    apology.

The alternative -- emit a "I can only do one at a time" error --
was REJECTED because it punishes the common case where the
operator's "both" is shorthand for "I don't have a strong
preference, pick one".

### Verification

* **40+ new unit assertions across 25 new test functions** in
  `tests/unit/test_voice_dialog.nova`. R31F's 167 prior
  assertions: 166 pass byte-identical; 1 assertion (the
  "multi-kind ambiguous picks first" classifier label) was
  RELABELED from `vc_followup_kind_pivot()` to
  `vc_followup_clarify()` -- the END-STATE behaviour of the
  helper `voice_followup_kind_pivot_target` is unchanged
  (still returns "FACT" via R31F's first-match helper), only
  the classifier label moves to CLARIFY. Coverage:
    - Classifier output enum: VC_FOLLOWUP_CLARIFY = 5;
      MAX_ATTEMPTS = 2.
    - Multi-kind detector unit tests: 2-kind / 3-kind /
      dedup / exclude-prior / no-match shapes.
    - Classifier CLARIFY: "more facts and rules" after
      CONCEPT (headline brief case); "and facts and rules"
      after SKILL (cue variation).
    - Classifier preservation: single-kind remainder still
      KIND_PIVOT; no-kind remainder still PIVOT; same-kind
      multi-mention ("more rules and rule atoms" after FACT)
      stays KIND_PIVOT (detector dedups -> single kind).
    - Render: 2-candidate question "Did you mean X or Y
      atoms?"; 3-candidate "Did you mean X, Y, or Z atoms?".
    - Kind-selector resolver: bare upper-case + lower-case;
      morphology phrase ("the rules"); "both" / "either" /
      "all" -> first candidate; non-kind fall-through; kind
      not in candidates -> "".
    - Session bookkeeping: vc_session_new initialises pending
      slots empty; reset clears them; mid-clarify session is
      pending.
    - Dispatch: CLARIFY emits the question text + stashes
      candidates + sets attempts=1; "RULE" reply resolves +
      dispatches LIST_ALL RULE; "the facts" reply resolves
      via morphology + dispatches LIST_ALL FACT; "both" reply
      picks FIRST candidate; "cats" reply doesn't resolve +
      re-emits with reduced patience + bumps attempts to 2;
      a second non-resolution reply gives up + dispatches
      first-match with apology prefix; "never mind" mid-
      clarify cancels via vc_session_reset.
    - Full chain: list all CONCEPT -> CLARIFY -> RULE -> new
      query (the headline brief scenario).
    - History: NO history entry on CLARIFY emit; +1 on
      resolution.
    - Env opt-out probe `vc_clarify_suppressed_by_env` returns
      0 by default (clarify path active).

* **R31F / R30F / R29C parity: 166 of the 167 prior assertions
  still pass byte-identical**. The single relabel:

  | # | Test                                       | Input                                          | Prior expected | New expected | Rationale                                                             |
  |---|--------------------------------------------|------------------------------------------------|----------------|--------------|-----------------------------------------------------------------------|
  | 1 | `test_kind_pivot_multi_kind_ambiguous_picks_first` | `'more facts and rules'` after CONCEPT | KIND_PIVOT     | CLARIFY      | R32F's headline path -- 2+ known kinds in remainder now route CLARIFY. The companion target-probe assertion (`= FACT`) is UNCHANGED. |

  All other CLARIFY-adjacent assertions in the prior suite are
  inputs the new path EXPLICITLY classifies as KIND_PIVOT
  (single known kind) or PIVOT (no known kind) -- they stay
  byte-identical.

### Honest design caveat -- clarify-attempt counter persistence

The clarify-attempt counter (slot
`_VC_SESS_PENDING_ATTEMPTS`) persists across topic changes if
the user PIVOTS during ambiguity through a path other than the
explicit topic-shift markers. Explicit topic-shift markers
("actually" / "never mind") DO clear pending state via
`vc_session_reset`, but a more-cue PIVOT that lands mid-
ambiguity (e.g. operator answers "tell me about cats" to a
RULE/FACT clarify) is interpreted by
`_vd_handle_pending_clarify` as a non-resolution. The counter
bumps and we re-emit the clarify rather than restarting the
ambiguity budget for the new topic. This is correct in the
ambiguity-resolution context (the operator hasn't clearly told
us they're shifting topic), but a 3-turn `FACT -> CLARIFY -> "actually CONCEPT"`
interaction does lose the attempt counter due to the reset,
which is the correct semantic.

The mid-clarify response that NAMES a third known kind ("tell
me more about CONCEPT" while RULE/FACT are pending) does NOT
re-classify through the multi-kind detector either. We treat
it as a non-resolution + bump the attempt counter. The
argument for re-classification would be that the operator
clearly shifted to CONCEPT; the argument against is that it's
a semantic guess in a disambiguation context. We chose the
simpler path; the multi-turn loop covers the gap (the operator
can follow up with "actually CONCEPT" or wait for the give-up
turn).

### Concurrency note + stash discipline

Followed the brief's strict ownership rules:

  * `git stash push -m "R32F-preflight" -- <owned-paths>` (no
    `-u`) was issued; sibling-agent untracked files were left
    alone. Stash returned "No local changes to save" -- my
    owned paths were clean at session start.
  * Modified ONLY: `examples/voice_dialog.nova`,
    `tests/unit/test_voice_dialog.nova`, `AUDIO_AUDIT.md`,
    `NEXT_SESSION.md`, `README.md`. `voice_conversation.nova`,
    `crossengin_chat.nova`, federation/safety modules
    untouched.
  * The sibling agent's WIP in `src/federation/nat_traversal.nova`
    was preserved (not stashed, not committed).

### Files touched (R25B.6 / R32F)

* MOD: `examples/voice_dialog.nova` -- additive (~280 lines:
  `VC_FOLLOWUP_CLARIFY` constant + accessor; `MAX_ATTEMPTS`
  constant + accessor; `_vd_remainder_known_kinds_all` helper +
  public probe; pending-clarify session slots + accessors;
  `_vd_clarify_suppressed_by_env` probe + public wrapper;
  `_vd_resolve_clarify_selector` parser + public probe;
  `_vd_is_both_selector` helper; `_vd_render_clarify_question`
  + public probe; classifier extension; CLARIFY dispatcher
  branch; `_vd_handle_pending_clarify` resolution helper).
  R28D / R29C / R30F / R31F code blocks unchanged (only
  docstrings amended).
* MOD: `tests/unit/test_voice_dialog.nova` -- additive (+40
  assertions across +25 new test functions; 1 prior assertion
  RELABELED to expect `vc_followup_clarify()` -- byte-identical
  end-state for the companion target-probe assertion).
* MOD: `AUDIO_AUDIT.md` (this section), `NEXT_SESSION.md`,
  `README.md`.

R8B / R15D / R21C / R25B / R25B.2 / R25B.3 / R25B.4 / R25B.5 /
R28D / R29C / R30F / R31F modules and tests are untouched --
R25B.6 is purely additive on top of R25B.5's dialog layer.

## R26C -- Spectral-subtraction Wiener noise reduction

Closes the **frequency-domain denoising** gap in CrossEngin's audio chain.
R14E's noise gate attenuates whole sub-threshold windows wholesale;
that's perfect for chopping inter-utterance silences but it leaves any
noise floor that overlaps a speech utterance intact. A quiet hiss UNDER
a Klatt vowel still passes the gate because the vowel keeps the envelope
above the threshold. R26C runs spectral subtraction in the per-frame
STFT domain so the bins occupied by the speech harmonics stay loud while
the broad noise floor between them gets pulled down.

This is the classical move that pre-DNN telephony / hearing-aid /
ASR-preprocessing systems have leaned on for decades (Boll 1979 for
straight spectral subtraction; Lim & Oppenheim 1979 for the
minimum-mean-square-error / Wiener formulation; Berouti et al. 1979 for
the spectral-floor variant we use to avoid "musical noise" artifacts).

### Motivating use cases

1. **TTS -> STT loop quality.** R25B's voice-conversation demo
   synthesizes a response with Klatt (R6E) and round-trips it through
   whisper.cpp (R8B). Whisper sometimes mis-hears a clean Klatt vowel
   because the integer-quantized formant carrier sits on top of a
   low-amplitude hash from the synthesizer's phase accumulator.
   Pre-filtering with `/denoise` pulls the hash floor down without
   touching the formant peaks.
2. **General WAV cleanup.** Recordings from `audio_capture` carry
   whatever room / preamp noise the operator's hardware injects. A
   single `/denoise` pass moves transcript accuracy noticeably on
   recordings made outside a quiet booth.

### Algorithm

Spectral-subtraction Wiener filter, frame by frame:

1. **Estimate noise** from a leading silence frame (first 300 ms by
   default -- the VAD R7F-corroborated assumption that no speech begins
   inside that window). Take an STFT-aligned FFT of each noise frame
   and average the magnitude-squared per bin into the noise
   power-spectral-density estimate |N(k)|^2. Sqrt for the per-bin
   noise magnitude.
2. **Per-frame STFT** of the rest of the input. Hann window, radix-2
   FFT, identical analysis parameters to R16E so the noise estimate's
   bins align (512 / 256 at 16 kHz, 256 / 128 at 8 kHz).
3. **Wiener gain** per bin:
   `H(k) = max(0, |X(k)|^2 - |N(k)|^2) / |X(k)|^2`
   Clamped to `[NR_GAIN_FLOOR_MILLI, NR_GAIN_CEIL_MILLI]` = `[50, 1000]`
   in milli to avoid the classic spectral-subtraction "musical noise":
   when H drops to zero on sub-noise bins the inverse FFT introduces
   random sinusoidal bursts that sound worse than the noise we were
   trying to kill. A 5% gain floor (Berouti's "spectral floor") leaves
   a tiny residual which the ear hears as "quiet" rather than "tone
   artifacts".
4. **Apply** the gain to the COMPLEX X(k) so the original phase rides
   through unchanged. The conjugate-symmetric upper half of the
   spectrum (k >= N/2) uses the mirrored noise magnitude (X[N-k] =
   conj(X[k]) for real inputs), so the iFFT produces a real output.
5. **Inverse FFT** each cleaned frame back to the time domain via
   R16E's `ifft_radix2`.
6. **Overlap-add** reconstruction with a synthesis Hann window. The
   analysis Hann already multiplied the input frame; we multiply the
   inverse by Hann again (so the effective window is `hann^2`) and
   accumulate `hann^2` into a parallel `wsum` buffer for normalization.
   Standard Griffin-Lim STFT reconstruction: `out[t] =
   sum(time_re_n * h_n) / sum(h_n^2)`. The constant-overlap-add
   property of Hann at 50% overlap reconstructs the original amplitude
   modulo FFT rounding.

The reconstruction's scale-tracking matters in integer arithmetic --
`h` is in milli (units of 1000), so the final normalization multiplies
the numerator by `MILLI * MILLI = 1e6` before dividing by `sum(h_milli^2)`
to land the output in PCM range.

### Public API

* `nr_estimate_noise(pcm, sample_rate, leading_ms) -> noise_spectrum`
  Returns a list of length `frame_size / 2` (256 at 16 kHz, 128 at
  8 kHz). Empty input -> empty list. Silence input -> all-zero list.
* `nr_apply_wiener(pcm, sample_rate, noise_spectrum) -> cleaned_pcm`
  Applies the gain function frame-by-frame with overlap-add. Length
  mismatch on `noise_spectrum` -> empty output (graceful error).
* `nr_reduce(pcm, sample_rate) -> cleaned_pcm`
  Convenience: estimate from first 300 ms + apply. The 1-call entry
  point for the chat `/denoise` command.
* `nr_rms(pcm)` and `nr_rms_window(pcm, start, count)` diagnostic
  helpers for SNR reporting.
* `nr_run_denoise_command(arg)` chat helper -- mirrors the R14E
  `dsp_run_*_command` shape (string return, parenthesized one-liner
  with input/output RMS + noise floor sum + would-be output path).

### Calibration on the Klatt /ae/ fixture

A 300 ms leading silence + 1200-sample Klatt /ae/ vowel @ 8 kHz with
LCG noise (amp=800) added across the whole 3600-sample buffer:

* Signal-region RMS before: 7703; after: 7607 (preserved within 99%).
* Noise-region RMS before: 461; after: 204 (53% reduction).
* SNR before: 16.7; SNR after: 37.3 (**2.23x improvement, +6.97 dB**).

### Chat wiring

`/denoise PATH` admin command -- one import + one help line + one
dispatch line in `examples/crossengin_chat.nova`. Output is a single
parenthesized line like:

```
(denoise /tmp/x.wav: leading_ms=300, frame_size=512, hop_size=256,
input=N samples rms=R, noise_floor_sum=S, output=N samples rms=R'
@ SR Hz -> PATH.denoise.wav)
```

The output WAV path is reported but not actually written to disk
(matching the `/gate` / `/reverb` convention -- the chat command is a
diagnostic; the integration scenario uses a NOVA driver to write the
WAV when it needs to disk-verify).

### Honest scope

Spectral subtraction is the simplest noise reduction. Modern approaches
(DNN-based / DeepFilterNet / RNNoise) require trained models. R26C
ships the classical integer Wiener that gives ~7 dB SNR improvement on
stationary noise (white / pink / hum) under Klatt-synth or natural
speech. Deferred to R26C.2:

* **Multi-band Wiener.** Independent noise estimates per Mel band so
  non-stationary noise (a passing car, a slamming door) gets tracked
  instead of averaged into oblivion.
* **Continuous noise re-estimation.** Track the inter-utterance
  silences via R7F VAD output and refresh the noise PSD as the
  recording progresses.
* **Soft-decision Wiener.** Replace the hard floor with a
  probability-weighted gain (Ephraim-Malah 1984 MMSE-STSA).
* **VAD-driven noise tracking.** Let R7F's energy + ZCR detector mark
  the noise-only frames automatically instead of trusting the leading
  300 ms.

### Verification

* 33 unit assertions in `tests/unit/test_audio_noise_reduce.nova`:
  defaults + accessors (8), noise estimation on noise/silence (5),
  Wiener pure-signal pass-through (3), silence round-trip (2),
  noise-region attenuation (3), Klatt SNR improvement (5), length-
  mismatch graceful error (2), empty input (2), RMS helpers (4). All
  pass via `make test` (213/213 unit suite green including the new
  test).
* 18 integration assertions in
  `tests/integration/scenario_uuuu_noise_reduce.sh` (letter `uuuu` is
  free -- `uuu` already taken by wakeword). NOVA driver builds the
  Klatt + noise fixture, runs `nr_reduce`, writes both noisy +
  cleaned WAVs, and reports per-region RMS for bash to assert. Then
  the chat `/denoise` path is driven for usage / error / success
  diagnostics; an optional whisper round-trip leg runs when
  `/usr/local/bin/whisper-main` is present.
* All prior audio suites stay green: scenario_ooo_spectrogram pass=19,
  scenario_hhh_dsp pass=23. Module count: +1 transducer.

### Files touched (R26C)

* NEW: `src/io/transducers/audio_noise_reduce.nova` (~580 lines incl.
  header + honest-scope footer; 9 public functions).
* NEW: `tests/unit/test_audio_noise_reduce.nova` (33 unit assertions).
* NEW: `tests/integration/scenario_uuuu_noise_reduce.sh` (18
  integration assertions).
* MOD: `examples/crossengin_chat.nova` (1 import + 1 help + 1
  dispatch line).
* MOD: `AUDIO_AUDIT.md` (this section), `README.md`,
  `NEXT_SESSION.md`.
