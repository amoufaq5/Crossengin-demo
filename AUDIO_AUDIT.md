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
