# ce_io findings — `CE/src/io/*` (65 files, 47,327 LOC), media audit docs, media scripts

## Plain-language summary

`src/io` is a hand-written, integer-only library of textbook signal-processing and computer-vision routines
(JPEG/PNG/inflate decoders, Sobel/Canny/Harris/SIFT/ORB/HOG/LBP/SLIC, Lucas-Kanade, stereo, YIN pitch, MFCC, PSOLA,
formant speech synthesis), plus networking (HTTP client, a TLS 1.3 client, Noise XK, a KG pub/sub protocol) and a
small "effector" layer. It is the largest directory in the repository and it is, for the most part, real working code:
the decoders I could check against ground truth are correct (JPEG within 1 grey level of libjpeg, PNG bit-exact) and
they survived 2,000 malformed inputs without a crash or hang.

Three things are true at the same time and the founder should hold all three:

1. **The code is genuine.** These are not stubs. Roughly two thirds of the 63 code modules implement the named classical
   algorithm completely enough to pass analytic tests (a 440 Hz sine yields 440 Hz; an image shifted by (1,1) yields flow (1,1)).
2. **It is almost entirely disconnected from the "cognition" it sits beside.** Every perception slash-command in the chat
   is `println(module_run_command(arg))` — the knowledge graph is not even passed in (CE/examples/crossengin_chat.nova:7543-7576).
   `/see` prints labels such as `image_dark image_edge_dense`; nothing is stored, learned or reasoned over.
   IMAGE_AUDIT.md itself says the atom-creation side "is a separate follow-up" (CE/IMAGE_AUDIT.md:632-635). There is no
   learned perception anywhere: no features-to-concept mapping is fitted from data.
3. **The one perception capability that matters for a talking system — speech recognition — is not in this code.**
   It is OpenAI Whisper (a transformer neural network, via whisper.cpp + a 75 MB pretrained model file) or Vosk
   (Kaldi neural acoustic model via a Python subprocess). Without one of them installed, STT returns the literal string
   `[stt unavailable]`. The "no transformers / no deep learning" claim holds for the Nova code and fails for the
   system as soon as it is asked to hear.

Nothing was validated on real photographs, real speech or real video: the repository contains zero media files, and
every unit test builds its input in memory. Several modules whose names promise a capability (face detection, OCR,
object detection, speaker ID, voice cloning) are structural skeletons that say in their own headers they will not work
on real data. Text output is template slot-filling. The "effector safety gate" gates only the returned reply string;
the shell-outs that actually touch the world (espeak, aplay, arecord, whisper, python3) do not pass through it.

How it got here: 45,741 of the 47,327 lines were added in six days (2026-05-29 to 2026-06-03, by `git log --numstat` additions; 15,540 lines on
1 June, 14,138 on 3 June), in 115 commits out of 749; 708 of the repository's 749 commits are authored "Claude".
This is a fast, machine-generated breadth-first sweep through a classical CV/DSP syllabus. It is competent, and it is
not on the path the mission statement describes.

## Findings

| ID | Sev | Category | Title | File:line | Evidence | Impact | Recommended fix | Effort | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| IO-01 | Critical | Hidden dependence | Speech recognition is Whisper (transformer) or Vosk (Kaldi NN); no STT exists in Nova | CE/src/io/transducers/whisper_backend.nova:72-73,407-427; vosk_backend.nova:71-72,204-232,467-481; stt_seam.nova:140-160,99; CE/scripts/transcribe.sh:80-113 | fork+exec `/usr/local/bin/whisper-main -m /usr/local/share/whisper/ggml-tiny.en.bin`; else `python3 -c "from vosk import Model,KaldiRecognizer"`; else `"[stt unavailable]"`. Auto-picked when files exist (stt_seam.nova:151-160). | `/listen`, `/converse`, `/dialog`, `examples/voice_*.nova` hear only through a pretrained neural network. "Non-LLM / no deep learning" is false for the voice loop. | State it plainly in README: "STT is delegated to an external pretrained neural model". Do not describe the voice demos as substrate-only. | S | CONFIRMED |
| IO-02 | Critical | Architecture / drift | Perception outputs never reach the knowledge graph | CE/examples/crossengin_chat.nova:7543-7576, 5244-5273, 5215-5231; CE/IMAGE_AUDIT.md:632-635 | 30+ commands are `println(x_run_command(arg))` with no `kg` argument. `/see` comment: "the list of feature atoms the substrate *would* receive" (5249). `/listen` prints `(heard '...')` and returns. Only `/rss`, `/converse`, `/dialog` receive `kg`. | 40k LOC of perception is a standalone toolbox. No claim of "the substrate sees/hears" is supported. | Either wire one modality end to end (labels -> atoms -> used in an answer) and measure it, or move the toolbox out of the core repo. | L | CONFIRMED |
| IO-03 | High | Security | TLS 1.3 client: unauthenticated by default; server Finished never verified; trust anchors are pinned dev-sandbox gateway keys | CE/src/io/transducers/tls13_client.nova:262-266, 712-721, 268-273, 736-746 | `_tls_strict()` returns 0 unless CE_TLS_STRICT set. At mtype==20 `expect = hmac_sha256(...)` is computed and then never compared ("mismatch is logged via status but we proceed" — no status is set). Fallback anchors: `_tls_pin_prod/_stag` "sandbox egress-gateway root CAs". | `/learn https://...` content can be substituted by any on-path party, and that content is ingested as knowledge. Strict mode trusts whoever holds the sandbox MITM gateway key unless CE_TLS_CA_BUNDLE is set. | Compare verify_data and abort on mismatch; make strict the default; remove the pinned gateway keys; or shell out to a vetted TLS library and say so. | M | CONFIRMED |
| IO-04 | High | Security | `/rss` fetches arbitrary `file://` paths and arbitrary IPs with no gate, whitelist or approval | CE/src/io/transducers/kg_rss_ingest.nova:677-727, 730-748; CE/examples/crossengin_chat.nova:7590; http_client.nova:357-369, 865-880 | `/rss` dispatch has no `_gate_or_prompt` (compare `/learn` at 7524). `_rss_fetch_file` opens any path. `http_get` accepts any dotted quad incl. 127.0.0.1 / 169.254.169.254. | Local-file read and SSRF into the KG from a chat command; bypasses the whitelist that `/learn` uses. | Route through the same whitelist + capability gate as `/learn`; restrict `file://` to a data directory. | S | CONFIRMED |
| IO-05 | High | Naming overstates function | "Effector safety gate" gates only the reply string; real side effects bypass it | CE/src/io/effectors/effector_gate.nova:86-104; CE/src/io/effectors/audio_speak.nova:126-129,161-186; CE/examples/crossengin_chat.nova:7538-7576 | `effector_speak` returns `text` or `""`. `/speak`, `/say`, `/listen`, `/clone`, `/denoise`... fork `/bin/sh`, write WAVs under /tmp, run espeak/aplay/arecord/whisper/python3 with no gate call. | The safety story ("single chokepoint every outward action passes through", effector_gate.nova header) is not true of the code. | Either route every fork/exec and file write through `effector_submit`, or reword the claim to "reply-text veto + audit log". | M | CONFIRMED |
| IO-06 | High | Fake/placeholder capability | Face detection, OCR, object detection, speaker ID, wake word, voice cloning are skeletons that cannot work on real data | image_face_detect.nova:10-19,117-122; image_ocr.nova:90-96,612-649; image_detector.nova:187,241; audio_speaker_id.nova:372-472; audio_wakeword.nova; effectors/audio_voice_clone.nova:47-60 | Face: 3 hand-set band thresholds "tuned against the SYNTHETIC face-pattern test fixture ... NOT calibrated for real photographs". OCR: matches its own built-in 8x8 glyphs. Detector: one HOG template + L2 threshold. Speaker ID / wake word: DTW against one stored MFCC sequence, tested on tones. Voice clone: copies mean F0 + formants into the formant synth. | Slash commands `/faces /ocr /detect /spk_recognize /wake /clone` exist and print results, which reads as capability. The source headers are honest; the command list and docs index are not. | Label these "structural demo" in `/help` and README, or remove from the live chat. | S | CONFIRMED |
| IO-07 | High | Testing | No real-world ground truth anywhere; zero media fixtures in repo | `git ls-files` has 0 .jpg/.png/.pgm/.wav/.y4m; CE/tests/unit/test_jpeg_decode.nova:582-592 | All 29 perception tests I inspected build inputs in memory. The single real-file JPEG test passes with `ce_check("pillow fixture absent (skipped)", 1)` when the file is missing — it cannot fail. | Accuracy on real images/audio is unknown for every module except JPEG/PNG (which I checked, below). | Commit 10-20 small real fixtures with reference outputs from a trusted library; make skipped tests report as skipped. | M | CONFIRMED |
| IO-08 | Medium | Security | File-ops "sandbox" is a string-prefix check; `..` escapes it | CE/src/io/effectors/effector_file_ops.nova:89-112 | Probe `$S/probes/ce_io/trav.nova`: `/tmp/ce_tool_x/../../etc/hostname` -> in_sandbox=1, read ok; `/tmp/ce_tool_/../ce_io_probe_escape.txt` written outside the prefix. | Arbitrary file read/write if the tool path is ever driven by a plan. Currently not reachable from any example entry point (import graph), hence Medium. | Reject paths containing `..` or resolve to a canonical path before the check. | S | CONFIRMED (executed) |
| IO-09 | Medium | Performance claim | BENCHMARKS.md headline numbers only partly reproduce; no external baseline | CE/BENCHMARKS.md:36-64; CE/examples/bench_simd_flow.nova; CE/examples/bench_detector_integral.nova | Re-ran: stereo u8 SIMD 6.21x (claim 5.94x) OK. LK mul-acc 1.13x, 1.24x in two runs, and one run 0.04x (claim 3.35x) NOT reproduced. Image SAD 91x (claim 107x) OK. HOG bench: `ERROR: undeclared callee: str_data` — does not compile with the current Nova, so "1.08x-2.15x" is unverifiable. | All speedups are Nova-SIMD vs Nova-scalar. No comparison with C/OpenCV, so nothing is known about absolute performance. | Fix the HOG bench; report medians of N runs; add one external reference (e.g. OpenCV StereoBM on the same input). | S | CONFIRMED (executed) |
| IO-10 | Medium | Correctness | HTTP client has no DNS resolver | CE/src/io/transducers/http_client.nova:82, 357-369 | `_http_dns_lookup` returns the host if it is a dotted quad, else looks in env `HTTP_DNS_HOST_TO_IP`, else `"dns unresolved"`. | "In-process HTTP client" cannot fetch a hostname unless the operator pre-supplies the IP (or another module resolves it). | Document, or implement a UDP DNS query. | M | CONFIRMED |
| IO-11 | Medium | Security | Weak-randomness fallbacks in channel crypto | CE/src/io/transducers/noise_xk.nova:444-454; secure_channel.nova:324-345 | Noise XK private scalar falls back to a 15-bit LCG seeded by `nanotime()` if `secure_random` returns short — silently. PSK-channel handshake nonce = nanotime + counter. | A failed getrandom yields a 32,768-value key space with no error. | Fail closed when `secure_random` fails. | S | CONFIRMED |
| IO-12 | Medium | Naming overstates function | "Pure-substrate output generation" is template slot-filling; "speak from reasoning" is a max-weight reverse lookup | CE/src/io/effectors/output_generation.nova (gen_best_pattern, gen_emit, gen_word_for_concept); CE/examples/crossengin_chat.nova:8250-8283 | Fallback path builds intent `[SEE see][TOPIC <word>]` or `[ACK okay]`, picks the pattern filling most slots, joins words with spaces. Most replies bypass it: "dispatched" full sentences are spoken directly (8240-8245). | Generated language is one or two fixed frames with one substituted word. | Describe as "template realiser". | S | CONFIRMED |
| IO-13 | Medium | Stub | MCP server and MCP effector return canned strings | CE/src/io/effectors/mcp_server_stdio.nova:362-366; effector_mcp.nova:14-46; effector_http_action.nova:39-43 | `tools/call` -> `row[MCPT_CANNED]` unescaped into JSON. HTTP action returns `canned` when `simulated == 1` (default). | External MCP clients see "tools" that do nothing. A `"` in a canned response breaks the JSON. | Label as protocol scaffold; JSON-escape. | S | CONFIRMED |
| IO-14 | Medium | Silent fake data | Helper scripts fabricate input and exit 0 | CE/scripts/audio_capture.sh:176-236; CE/scripts/image_to_pgm.sh:143-156; CE/scripts/gen_test_jpeg.py:24-33 | No mic -> silent WAV, exit 0. No converter -> 16x16 grey PGM, exit 0 (then `/see` reports features of the placeholder). No Pillow -> non-decodable JPEG stub. | A demo can "see" or "hear" without any real input and report success. | Exit non-zero, or make the Nova side print "placeholder input". | S | CONFIRMED |
| IO-15 | Low | Dead code | `stream_audio.nova` is imported by nothing but its own test | CE/src/io/transducers/stream_audio.nova (394 LOC) | Import-graph closure over `src/` and `examples/`: no importer. | The "daemon hears continuously" path does not exist. Also `effector_code_exec`, `effector_file_ops`, `effector_http_action` are not reachable from any example binary (only via `agent/tool_use.nova`, `parts/action/action_module.nova`, which no example imports). | Remove or wire. | S | CONFIRMED |
| IO-16 | Low | Naming | "Kalman + greedy Hungarian" is a scalar-variance filter + greedy nearest neighbour; "Wiener" is spectral subtraction; "sandboxed code execution" evaluates arithmetic | image_tracker.nova:211-286; audio_noise_reduce.nova:65-68; effector_code_exec.nova:75-79 | Read. `/track` "detections" are the centroid of pixels > 128 (image_tracker.nova:467). | Readers over-estimate capability. | Rename. | S | CONFIRMED |
| IO-17 | Low | Security | Minor shell/arg hygiene | effectors/audio_tts.nova:788,793; whisper_backend.nova:493-494; stream_unix_socket.nova (default /tmp/crossengin.sock) | `"paplay '" + path + "'"` with env-supplied path, unescaped (audio_speak.nova does escape). Fixed world-writable temp paths (/tmp/ce_whisper_out.json, /tmp/ce_speech.wav, /tmp/ce_input.wav). | Local symlink/quote issues on a shared host. | Use the existing quoting helper; use mkstemp-style names. | S | CONFIRMED |
| IO-18 | Low | Docs drift | Stale headers and "audit" docs that are build logs | transducers/README.md:9; effectors/README.md:11; image_sift.nova:7-12; tls13_client.nova:13-14; input_transducer.nova:35; CE/TLS_AUDIT.md:113; CE/scripts/gen_test_jpeg.py:7-8 | E.g. SIFT header says "ships ONLY piece (1)" but the file has descriptor + matcher; READMEs say STT/TTS deferred. The *_AUDIT.md files are roadmaps/changelogs written by the same process that wrote the code; none contains independent measurement. | The founder cannot use the docs to know the state. | Rename to *_NOTES.md; regenerate a one-page status table from code. | S | CONFIRMED |
| IO-19 | Low | Correctness | Corrupt JPEG scan data decodes "OK" with garbage pixels; Adler-32 not checked in zlib | jpeg_decode.nova (entropy path); deflate_decode.nova:121 | Probe `m_scan.jpg` (random scan bytes) -> `OK 16x16`. 288/400 mutated JPEGs returned OK. PNG is protected by CRC32. | Garbage in, labels out, no warning. Not a memory-safety issue. | Count decode errors/unknown codes and fail above a threshold. | S | CONFIRMED (executed) |

TODO/FIXME/HACK/XXX inventory in `src/io`: 9 grep hits, of which 5 are real TODOs (png_decode.nova:35,514,517; audio_melody.nova:40; visual_perception.nova:105 — the last one stale), the rest are "0.XXX" false positives.

## Things that are genuinely good (verified)

- **JPEG decoder is correct.** Five real libjpeg-encoded grayscale files (8x8 to 100x75, quality 80/95, optimised Huffman, non-multiple-of-8 sizes): max pixel difference 1, mean 0.21-0.30, vs Pillow's decode. CONFIRMED by execution (`$S/probes/ce_io/dec.nova`, `gen.py`, `cmp.py`).
- **PNG + inflate are bit-exact** on five real zlib-level-default PNGs (dynamic Huffman, filters). CONFIRMED.
- **Parser robustness is good.** 2,000 mutated inputs (400 each JPEG/PNG/Y4M/WAV/PGM: byte flips, truncation, 0xFFFF injection, random insertion) -> 0 crashes, 0 hangs, all exit 0 with an error string or a bounded decode. Hand-crafted cases all rejected gracefully: truncated JPEG, DHT counts 255, segment length past EOF, zero dimensions, PNG 2^31-1 dimensions, IHDR lying about size, inflate back-reference before start ("distance exceeds output history"), 50 MB zip bomb inside a 16x16 PNG ("copy exceeds 1MiB cap"), chunk length past EOF, PGM 100000x100000, PGM width overflow, Y4M 100000x100000, WAV data length 0x7ffffff0, WAV fmt length 0xfffffff0. Every decoder has explicit dimension and file-size caps (jpeg_decode.nova:160-176, png_decode.nova:128-134, deflate_decode.nova:144, image_pgm.nova:72-86, video_y4m.nova:85-91, audio_capture.nova:72).
- **Scope honesty inside source files.** image_face_detect, image_ocr, audio_noise_reduce, stt_seam, tls13_client all carry explicit "this will not work on real data / does not verify" notes. The overstatement is at the level of command names, doc titles and the mission framing, not the file headers.
- **SIMD paths are bit-identical to scalar** in the two benches that run (mismatch counters = 0).

## io module status

Legend — Complete?: Y = the named algorithm is implemented end to end; P = restricted/simplified variant; S = skeleton that cannot do the named job on real data. Ground truth: REAL = checked against an independent implementation on real files (by me; the repo itself has none); ANALYTIC = synthetic input with a mathematically known answer; SELF = only self-consistency/structural checks. Live path = reachable from `crossengin_chat` (C) / `crossengin_daemon` (D) / other example (name) / none.

| module | algorithm | LOC | complete? | ground-truth tested? | live path |
|---|---|---|---|---|---|
| jpeg_decode | baseline JPEG, grayscale only | 1598 | P (no colour, no progressive, <=512px) | REAL (mine): max diff 1 | C `/see` |
| png_decode | PNG 8-bit gray, non-interlaced | 760 | P | REAL (mine): exact | C `/see` |
| deflate_decode | RFC 1951 inflate | 934 | Y (no Adler-32) | REAL (mine): exact | C |
| image_pgm | PGM P5 parser + stats | 545 | Y | ANALYTIC | C, D |
| video_y4m | uncompressed Y4M 4:2:0 | 568 | Y (needs ffmpeg for real video) | ANALYTIC | C `/play` |
| image_sobel | Sobel | 323 | Y | ANALYTIC | C |
| image_canny | Canny | 517 | Y | ANALYTIC | C |
| image_harris | Harris corners | 427 | Y | ANALYTIC | C |
| image_sift | SIFT-like DoG + 128-D descriptor | 1253 | P (integer approximations, no sub-pixel) | ANALYTIC | C `/match_images` |
| image_orb | FAST + rotated BRIEF + Hamming | 1167 | Y | ANALYTIC | C `/orb_match` |
| image_hog | HOG | 1138 | Y (L1 magnitude) | ANALYTIC | C `/hog` |
| image_lbp | LBP histograms | 590 | Y | ANALYTIC | C `/lbp` |
| image_segmentation | k-means (I,x,y) | 722 | Y | ANALYTIC | C `/segment` |
| image_superpixels | SLIC | 996 | Y | ANALYTIC | C `/slic` |
| image_optical_flow | Lucas-Kanade (+pyramid, SIMD) | 2986 | Y | ANALYTIC (known shifts) | C `/flow*` |
| image_stereo | SAD block match + 4-path SGM | 2188 | Y / P (SGM simplified) | ANALYTIC (known shifts) | C `/depth*` |
| image_panorama | RANSAC homography + blend | 1085 | P (one pair) | ANALYTIC | C `/pano` |
| image_detector | HOG template match + NMS | 888 | S (no classifier) | SELF | C `/detect` |
| image_face_detect | 3 hand-set Haar bands | 759 | S | SELF (synthetic bands) | C `/faces`, D via lipsync |
| image_face_recognize | LBP gallery + chi-squared NN | 822 | S/P | SELF | C |
| image_ocr | glyph template match | 806 | S (own 8x8 font only) | SELF | C `/ocr` |
| image_tracker | const-velocity filter + greedy match | 628 | P | ANALYTIC | C `/track` |
| video_motion_vectors | block-matching SAD | 315 | Y | ANALYTIC | C `/play` |
| video_perception | per-frame labels + diff | 502 | Y | SELF | C `/play` |
| video_smooth | tracker over frame dir | 406 | P | SELF | C `/smooth` |
| visual_perception | decode + label strings | 800 | Y | SELF | C `/see` (prints only) |
| audio_capture | WAV parser + capture shell-out | 519 | Y | ANALYTIC + fuzz (mine) | C, D |
| audio_vad | energy + ZCR VAD | 678 | Y | ANALYTIC | C, D |
| audio_spectrogram | integer FFT/STFT | 750 | Y | ANALYTIC (sine bins) | C `/spec` |
| audio_mfcc | MFCC | 732 | Y (approximate log/sin) | SELF (no reference MFCC) | C `/mfcc` |
| audio_pitch | autocorrelation + YIN | 1425 | Y | ANALYTIC (sines) | C `/pitch*` |
| audio_melody | F0 -> MIDI notes | 603 | Y | ANALYTIC | C `/melody` |
| audio_psola | TD-PSOLA | 513 | Y | ANALYTIC | C `/pitch_shift` |
| audio_dsp | Schroeder reverb, gate, compressor | 622 | Y | SELF | C |
| audio_noise_reduce | spectral subtraction | 774 | Y | ANALYTIC (synthetic SNR) | C `/denoise` |
| audio_wakeword | MFCC + DTW single template | 705 | S/P | SELF (tones) | C |
| audio_speaker_id | MFCC + DTW gallery | 831 | S/P | SELF (tones) | C |
| audio_synth | 2-formant phoneme synth | 1223 | P | SELF | C, voice_* |
| audio_tts | dictionary+rules G2P -> synth | 829 | P (122-word dictionary) | SELF | C `/say`, voice_* |
| audio_voice_clone | F0+formant parameter transfer | 1010 | S/P | SELF | C `/clone` |
| audio_speak | espeak / synth / aplay | 253 | Y | SELF | C `/speak` |
| stt_seam | dispatcher to external STT | 885 | Y (as a dispatcher) | n/a | C `/listen`, voice_* |
| whisper_backend | exec whisper.cpp | 884 | Y (wrapper) | parser tests only | C, voice_* |
| vosk_backend | exec python3+vosk | 515 | Y (wrapper) | parser tests only | C, voice_* |
| stream_audio | poll capture -> STT -> event | 394 | Dead | SELF | none |
| stream_stdin / unix_socket / http | daemon input sources | 378/386/680 | Y / P / P | SELF | D |
| input_transducer | lowercase + trim | 105 | Y | SELF | C, D |
| http_client | HTTP/1.1 GET, no DNS | 1052 | P | SELF (loopback) | C, D |
| tls13_client | TLS 1.3 client | 838 | P (auth gaps, IO-03) | key-schedule vectors | C `/learn` |
| secure_channel | PSK ChaCha20-Poly1305 framing | 692 | P | SELF | C, D |
| noise_xk | Noise XK over MODP-2048 | 1293 | P | SELF | C, D, fed_* |
| kg_sync | TCP atom-event pub/sub | 1964 | Y | SELF (loopback) | C, D, kg_*, fed_* |
| kg_rss_ingest | RSS/Atom -> atoms | 904 | Y | SELF | C `/rss` |
| output_generation | template slot fill | 241 | Y | SELF | C, D |
| effector_gate | tier lookup + log | 137 | Y | SELF | C, D, spine |
| tool | tool record + success counter | 152 | Y | SELF | C |
| effector_mcp / mcp_server_stdio | canned-response MCP | 49/434 | Stub / P | SELF / none | C / mcp |
| effector_code_exec / file_ops / http_action | arithmetic eval / prefix-checked file IO / canned-or-fetch | 20/40/65 | Y / P / P | SELF | none |

Unit tests executed (all in `$S/CE`, `timeout 180 $S/NOVA/nova run tests/unit/<t>.nova`), all PASS:
test_jpeg_decode (82 checks), test_png_decode (44), test_orb (34), test_audio_pitch_yin (35), test_audio_noise_reduce (33),
test_slic (61), test_stt_seam (27), test_whisper_backend (46), test_effector_gate (23; 13.6 s), test_output_generation (14),
test_http_client (103), test_optical_flow (53), test_face_detect (36), test_image_ocr (40), test_audio_mfcc (41), test_video_y4m (34).
Passing here means "consistent with synthetic expectations", not "works on real data".

## External tools & pretrained models

| Dependency | Kind | Invoked from | How | Centrality |
|---|---|---|---|---|
| whisper.cpp binary + `ggml-tiny.en.bin` (OpenAI Whisper, transformer encoder-decoder, ~75 MB pretrained weights) | Pretrained neural network | whisper_backend.nova:407-427, 773-787; scripts/transcribe.sh:80-108 | fork + exec (direct argv), stdout captured via pipe | The only way the system recognises speech (first choice in auto-pick, stt_seam.nova:151-156) |
| `python3` + `vosk` pip package + Kaldi model dir (`am/final.mdl`, neural acoustic model) | Pretrained neural network + Python sidecar | vosk_backend.nova:204-232, 467-481; scripts/transcribe.sh:110-113 | fork + exec `python3 -c <inline script>` | Second-choice STT |
| `espeak` | Classical TTS program | effectors/audio_speak.nova:161-170 | `/bin/sh -c "espeak -w ..."` | Preferred over the in-house synth when present |
| `aplay`, `paplay` | Audio playback | audio_speak.nova:179-190; audio_tts.nova:787-795 | `/bin/sh -c` | Playback only |
| `parecord`, `arecord`, `sox` | Audio capture | scripts/audio_capture.sh:114-173, via audio_capture.nova:204-250 | `/bin/sh -c "bash scripts/audio_capture.sh"` | Only microphone path |
| ImageMagick `convert`/`magick`, `ffmpeg` | Image/video conversion | scripts/image_to_pgm.sh:98-140; scripts/video_to_y4m.sh:77-93 | Operator runs manually | Required for any colour image, any non-gray PNG/JPEG, any real video |
| Pillow (Python) | Test fixture generation | scripts/gen_test_jpeg.py | manual | Tests only |
| `curl` | HTTPS fallback | referenced http_client.nova:8-11 (scripts/learn.sh — outside my area) | n/a here | See learning reviewer |
| Arbitrary shell command from env `CE_AUDIO_CAPTURE_CMD` | Shell | stream_audio.nova:87-95 | `/bin/sh -c $ENV` | Dead code |

No OCR model, object-detection model or embedding model is used: those functions are hand-coded template matchers
(and for that reason do not work on real inputs, IO-06). No LLM API call exists in `src/io`. (The chat does register
`/ingest_llm` and `/ingest_ollama` commands — CE/examples/crossengin_chat.nova command table — outside this assignment;
flagging for the lead.)

Does "no transformers / no deep learning" survive? For the Nova source: yes, CONFIRMED — there is no neural network code in
`src/io`. For the running system's speech input: no, CONFIRMED — it is Whisper or a Kaldi neural model or nothing.
STT_AUDIT.md is candid that pure-Nova STT "doesn't fit this decade" and argues STT is a "modality bridge" outside cognition.
That is a defensible engineering position, but it should be stated on the front page, because the hard part of hearing is exactly the part being outsourced to deep learning.

## Perception→cognition coupling

What reaches the knowledge graph / substrate when media is processed (all CONFIRMED by reading the dispatch table at
CE/examples/crossengin_chat.nova:7538-7590 and the handlers):

| Input | Command | What is computed | What reaches the KG / reasoning |
|---|---|---|---|
| Image | `/see` | stats + detector counts -> label strings (`image_dim_small`, `image_dark`, `image_bucket_N`, `image_edge_dense`, `image_corners_few`, ...) (visual_perception.nova:418-520) | Nothing. Printed. Labels are cached in the seam object; `/fuse` can read the last label list and print a correlation line (chat:7641). |
| Image | `/hog /lbp /slic /segment /faces /detect /ocr /depth /flow /pano /orb_match /match_images /track /smooth` | the named routine | Nothing. Each is `println(...)`; `kg` is not an argument. |
| Video | `/play` | per-frame labels + motion + scene-change, formatted as "EV_MESSAGE-shaped" text lines | Nothing. Printed (chat:5287-5312); not posted to the event queue. |
| Audio | `/listen` | capture -> VAD -> external STT | Nothing. Prints `(heard '...')` (chat:5215-5231). The transcript is not fed to the reader. |
| Audio | `/pitch /mfcc /melody /spec /wake /spk_recognize /denoise ...` | the named routine | Nothing. Printed / WAV written. |
| Audio | `/converse`, `/dialog` (examples/voice_conversation.nova:451-520) | external STT -> match transcript against 3 question templates (what-is / how-many / list-all) -> KG query -> fixed English sentence -> formant TTS | Reads the KG; writes nothing. This is the only place perception output is used to select behaviour. |
| Web | `/rss` | XML tag scan | Yes — one atom per feed item (title/link text) with guid dedup. Text, not perception. |
| Text | stdin / unix socket / HTTP POST (daemon) | lowercase + trim | Yes — becomes the message event the reader processes. This is the real input path. |

Is there learned perception? No (CONFIRMED). Nothing in `src/io` fits parameters from data: thresholds are constants,
templates are single stored examples, the face "cascade" is hand-set, the glyph set is hard-coded. No mechanism maps
features to concepts by exposure. `src/agent/loop_perception.nova` contains no image/visual handling (grep: 0 hits).

Daemon-reachable io modules: effector_gate, output_generation, input_transducer, stream_stdin/unix_socket/http,
http_client, secure_channel, kg_sync, noise_xk, and (via `perception/lipsync.nova`) image_pgm, image_face_detect,
audio_capture, audio_vad. None of the feature extractors run in the daemon loop.

## Output generation (Q4)

- `gen_from_intent_with_slot` (output_generation.nova): intent = ordered (role, lemma) pairs -> each lemma interned as a word atom -> choose the syntax pattern with score `fillable*2000 + confidence (+1,000,000 if complete)` -> emit word forms joined by single spaces -> increment pattern/word counters. `gen_feedback` adds or subtracts 1 from those counters ("Hebbian plasticity").
- "Speak from reasoning" (`gen_word_for_concept`): for a concept id, scan every atom in the language KG and return the word atom whose cross-reference to that concept has the largest weight. Used at chat:8269 / daemon:678 to produce an intent `[SEE see] [TOPIC <word>]`; otherwise `[ACK okay]`.
- In the chat, that path is the fallback. If any router produced a `dispatched` string (a complete sentence built elsewhere), it is spoken verbatim (chat:8240-8248). So most of what the system says is produced by other modules' string builders, not by this generator.
- Voice answers are fixed sentences with a count or a name substituted (examples/voice_conversation.nova:355-420).

## Effectors (Q5)

What the code can do in the world: print text; write WAV/gallery files to operator- or env-chosen paths; fork `/bin/sh`
to run espeak/aplay/paplay/arecord-family, whisper.cpp, python3; open TCP sockets (HTTP GET, TLS, kg_sync, federation);
read arbitrary files via `/rss file://`. What gates it: `effector_submit` -> `safety_gate` = veto flag, halt flag, permission-tier
table lookup, plus a decision-log append. In the live chat only the reply text goes through it (`effector_speak_governed`,
veto = `soul_check_constitution(text)`); a separate `_gate_or_prompt` capability check guards `/learn`, `/load`, retract,
teach and federation sockets (chat:7506-7609) but not `/rss`, `/speak`, `/listen`, `/say` or any media command.
The tool backends that could write files or fetch URLs under a plan are not linked into any example binary.

## Drift statement (Q9)

Facts: `src/io` is 47,327 of the repository's ~190k Nova lines (about a quarter). First commit touching it 2026-05-25;
96.6% of its lines landed 2026-05-29..2026-06-03 (2,703 / 6,396 / 2,007 / 15,540 / 4,957 / 14,138 lines per day).
115 commits touch it. After 2026-06-12 it received ~1,200 lines in total, mostly MCP/TLS/tooling.
The mission is Moment-Signal Cognition: nodes, signals, moments, attribution, a knowledge graph. None of the 40
perception modules emits a node, signal or moment; none is consumed by the reasoning loops; none learns. They are a
well-made classical CV/DSP library written in the project's language, adjacent to the mission rather than part of it.
The parts of `src/io` that the cognitive loop actually depends on total roughly 2,500 lines: input_transducer,
the three stream sources, output_generation, effector_gate, tool, and the HTTP/TLS fetch path.

## Could not verify

- Accuracy of any CV/audio module on real photographs/speech/video (no fixtures; only JPEG/PNG decoders were ground-truthed).
- Whisper/Vosk paths end to end (not installed in the sandbox; only wrapper/parser tests ran).
- TLS interoperability against a live server (no network use); findings are from reading the handshake code.
- kg_sync / noise_xk protocol security beyond the RNG fallback (skimmed, 3,257 LOC).
- Line-by-line correctness of the ~30 "skimmed" algorithm modules; status rests on headers, function inventories, test inspection and 16 executed test files.
- HOG-detector benchmark numbers (bench does not compile against the current Nova build in `$S/NOVA`).
