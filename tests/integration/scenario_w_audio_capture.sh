#!/usr/bin/env bash
# Scenario W -- P2.5 cont. real microphone capture end-to-end.
#
# Exercises the audio-input half of the modality bridge that landed in
# this session: scripts/audio_capture.sh + src/io/transducers/audio_capture.nova
# + the CE_AUDIO_CAPTURE_CMD=auto path wired into stream_audio.nova. The
# scenario has two halves:
#
#   PART 1 -- the bash shim alone. Run scripts/audio_capture.sh against
#             /tmp/ce_scenario_w_capture.wav for 1 second and verify:
#               * the script exits 0 (silent fallback OR real capture)
#               * the produced file is a valid canonical RIFF/WAVE/PCM WAV
#                 (magic bytes "RIFF" / "WAVE" / "fmt " / "data" in place)
#               * the WAV is 16-bit signed mono at 16 kHz
#               * the file size matches the 44-byte header + 1s * 16000 Hz
#                 * 2 bytes/sample = 32044 bytes (silent fallback) OR is
#                 plausibly close (real parecord/arecord may pad differently)
#
#   PART 2 -- end-to-end stream_audio with CE_AUDIO_CAPTURE_CMD=auto. A
#             tiny on-the-fly NOVA driver constructs a stream_audio state,
#             calls init_from_env (which resolves the "auto" sentinel and
#             flips SA_USE_AUTO=1), invokes stream_audio_poll(s, hs), and
#             asserts:
#               * captures_total ticked to 1 (the auto path ran)
#               * use_auto == 1 (env-resolution wired the auto sentinel)
#               * the WAV at the seam's resolved path exists
#               * audio_capture_to_pcm parses the produced WAV cleanly --
#                 sample_rate == 16000 (silent fallback) AND samples list
#                 is non-empty
#               * an EV_MESSAGE round-trips through the scheduler when a
#                 non-placeholder transcript is posted (the silent-WAV /
#                 no-STT-backend case produces a "[stt..." placeholder
#                 which stream_audio_poll correctly DROPS; the EV_MESSAGE
#                 emit-path is exercised here via a direct hs_post_event
#                 in the driver to prove the scheduler wiring intact)
#
# Sandbox shape: this CI/container has NO microphone hardware (no /dev/snd,
# no PulseAudio socket, no parecord/arecord/sox installed). The silent-WAV
# fallback path is therefore what runs. A real Linux desktop with PulseAudio
# would exercise the parecord branch and produce real captured audio --
# every assertion below still holds because the header layout is identical.
#
# Pre-conditions: the NOVA toolchain at $NOVA_ROOT/nova.
# Side-effects: writes /tmp/ce_scenario_w_capture.wav,
#               /tmp/ce_scenario_w_driver.out, and the driver source under
#               tests/integration/_scenario_w_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario W: P2.5 cont. microphone capture (auto path)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_w_audio_capture"
    exit $?
fi

CAP_WAV="/tmp/ce_scenario_w_capture.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_w_drivers"
DRV_SRC="$DRV_DIR/auto_path_driver.nova"
DRV_OUT="/tmp/ce_scenario_w_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$CAP_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Detect what backend will actually run -- informational only, used in
# the summary line so a reader can see whether the silent fallback fired
# or a real microphone got captured.
DETECTED_BACKEND="silent-fallback"
if command -v parecord >/dev/null 2>&1 && [ -d /dev/snd -o -n "${PULSE_SERVER:-}" ]; then
    DETECTED_BACKEND="parecord"
elif command -v arecord >/dev/null 2>&1 && [ -d /dev/snd ]; then
    DETECTED_BACKEND="arecord"
elif command -v sox >/dev/null 2>&1 && [ -d /dev/snd ]; then
    DETECTED_BACKEND="sox"
fi
printf "  ${C_DIM}(detected capture backend: %s)${C_RST}\n" "$DETECTED_BACKEND"

# ===========================================================================
# PART 1 -- the bash shim alone
# ===========================================================================

# Clean any stale capture from a prior run.
rm -f "$CAP_WAV"

# Run the shim for 1 second of capture. ALWAYS exits 0 (silent fallback
# OR real capture).
SCRIPT_OUT=$(bash "$REPO_ROOT/scripts/audio_capture.sh" "$CAP_WAV" 1 2>&1)
SCRIPT_RC=$?

assert_eq "$SCRIPT_RC" "0" "audio_capture.sh exits 0 (silent fallback or real)"
assert_match "$SCRIPT_OUT" "$CAP_WAV" \
    "audio_capture.sh prints the destination path"
assert_file_exists "$CAP_WAV" "audio_capture.sh produced the WAV file"

# Header magic-byte checks. Use od + awk to grab the 4-byte chunks at
# offsets 0, 8, 12, 36 -- the four canonical PCM-WAV markers.
HDR_RIFF=$(dd if="$CAP_WAV" bs=1 count=4 status=none 2>/dev/null)
HDR_WAVE=$(dd if="$CAP_WAV" bs=1 count=4 skip=8 status=none 2>/dev/null)
HDR_FMT=$( dd if="$CAP_WAV" bs=1 count=4 skip=12 status=none 2>/dev/null)
HDR_DATA=$(dd if="$CAP_WAV" bs=1 count=4 skip=36 status=none 2>/dev/null)

assert_eq "$HDR_RIFF" "RIFF" "WAV header has 'RIFF' magic at offset 0"
assert_eq "$HDR_WAVE" "WAVE" "WAV header has 'WAVE' magic at offset 8"
assert_eq "$HDR_FMT"  "fmt " "WAV header has 'fmt ' chunk id at offset 12"
assert_eq "$HDR_DATA" "data" "WAV header has 'data' chunk id at offset 36"

# Sample-rate / format / channel checks via Python (one-shot, no
# per-byte shell loop). Skips Part-1 numeric checks if python3 is absent.
if command -v python3 >/dev/null 2>&1; then
    PYOUT=$(python3 - "$CAP_WAV" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f: d = f.read()
print("size=" + str(len(d)))
print("audio_format=" + str(struct.unpack('<H', d[20:22])[0]))
print("channels="     + str(struct.unpack('<H', d[22:24])[0]))
print("sample_rate="  + str(struct.unpack('<I', d[24:28])[0]))
print("bits="         + str(struct.unpack('<H', d[34:36])[0]))
print("data_size="    + str(struct.unpack('<I', d[40:44])[0]))
PY
)
    assert_match "$PYOUT" "audio_format=1" \
        "WAV audio_format = 1 (PCM)"
    assert_match "$PYOUT" "channels=1" \
        "WAV is mono (1 channel)"
    assert_match "$PYOUT" "sample_rate=16000" \
        "WAV sample_rate = 16000 Hz"
    assert_match "$PYOUT" "bits=16" \
        "WAV is 16-bit"

    # File-size sanity. Silent-fallback path produces exactly 44 +
    # 16000 * 2 = 32044 bytes. Real backends may pad differently; we
    # accept anything >= 1000 bytes (a tiny actual capture).
    SIZE_BYTES=$(stat -c %s "$CAP_WAV" 2>/dev/null || stat -f %z "$CAP_WAV" 2>/dev/null || echo 0)
    if [ "$SIZE_BYTES" -ge 1000 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  WAV size %d bytes (>= 1000 -- non-trivial capture)\n" "$SIZE_BYTES"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  WAV is suspiciously small: %d bytes\n" "$SIZE_BYTES"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  python3 not installed -- WAV numeric field checks skipped\n"
fi

# ===========================================================================
# PART 2 -- end-to-end stream_audio with CE_AUDIO_CAPTURE_CMD=auto
# ===========================================================================

# Emit the NOVA driver. The leading underscore on _scenario_w_drivers/
# means the Makefile's integration glob (! -name '_*') skips it, and
# the find under src/ already only walks src/.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated stream_audio driver for scenario_w_audio_capture.sh.
//
// Constructs a stream_audio state, drives the env-gated init_from_env
// path with CE_AUDIO_CAPTURE_CMD=auto + CE_STT_BACKEND=stub set in the
// inherited env, invokes stream_audio_poll(s, hs) once with the tick
// counter forced past its interval, then asserts on the introspection
// surface AND the audio_capture_to_pcm parser. Also exercises the
// EV_MESSAGE post-path directly (since the silent-WAV / no-STT-backend
// case produces a "[stt..." placeholder which stream_audio_poll
// correctly DROPS; we need a separate non-placeholder post to prove
// the scheduler wiring is intact).
import "../../../src/io/transducers/stream_audio.nova"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/scheduler/hybrid_scheduler.nova"
import "../../../src/substrate/part_lifecycle.nova"

fn _mk_hs() {
    let reg = part_registry_new()
    registry_spawn_fixed(reg, 8, 1)
    return hs_new(reg)
}

fn _bool_or_die(label, cond) {
    if cond {
        println("scenario_w: PASS  " + label)
    } else {
        println("scenario_w: FAIL  " + label)
    }
}

fn main() {
    let s = stream_audio_new()
    let hs = _mk_hs()

    // 1. init_from_env should resolve the "auto" token via the inherited
    //    process env (CE_AUDIO_CAPTURE_CMD=auto, CE_STT_BACKEND=stub).
    let ok = stream_audio_init_from_env(s)
    _bool_or_die("init_from_env returned 1", ok == 1)
    _bool_or_die("enabled flag set", stream_audio_enabled(s) == 1)
    _bool_or_die("use_auto resolved", stream_audio_use_auto(s) == 1)
    // The seam's resolved wav path should match the env's
    // CE_AUDIO_INPUT_PATH.
    _bool_or_die("wav_path resolved to expected fixture",
                 str_eq(stream_audio_wav_path(s),
                        "/tmp/ce_scenario_w_capture.wav") == 1)

    // 2. Force initialized + bypass the tick-counter gate so the poll
    //    actually fires on the first call. The seam constructor's
    //    SA_TICK_COUNTER == 0; setting interval = 1 means tc + 1 = 1 ==
    //    poll_interval -> NOT less than -> fires.
    stream_audio_test_set_enabled(s, 1)
    stream_audio_test_set_interval(s, 1)

    // 3. Run the poll. The auto path forks scripts/audio_capture.sh which
    //    writes /tmp/ce_scenario_w_capture.wav (real audio or silent
    //    fallback). The transcribe seam then runs the stub backend
    //    against the WAV -> "[stt unavailable]" -> stream_audio_poll
    //    drops the placeholder; n posted = 0 is EXPECTED in the
    //    silent-fallback sandbox.
    let n_posted = stream_audio_poll(s, hs)
    _bool_or_die("captures_total advanced to 1",
                 stream_audio_captures_total(s) == 1)
    // n_posted = 0 in the sealed sandbox (placeholder dropped); we
    // don't fail if a real STT backend exists and posts 1.
    _bool_or_die("poll completed without crash (n_posted in {0,1})",
                 n_posted >= 0 && n_posted <= 1)

    // 4. The WAV file the auto path produced must be parseable by the
    //    pure-NOVA WAV reader. sample_rate must be 16000 Hz (canonical
    //    capture rate), and samples list non-empty.
    let r = audio_capture_to_pcm(stream_audio_wav_path(s))
    let pcm = audio_capture_pcm_samples(r)
    let sr  = audio_capture_pcm_rate(r)
    _bool_or_die("WAV parser yielded sample_rate=16000", sr == 16000)
    _bool_or_die("WAV parser yielded non-empty samples", len(pcm) > 0)

    // 5. Prove the EV_MESSAGE post-path is wired by directly posting
    //    a non-placeholder transcript through hs_post_event (the same
    //    path stream_audio_poll uses when a real backend returns a
    //    real transcript). This isolates the scheduler wiring from
    //    the STT backend gap.
    let norm = transduce_text("scenario w synthetic transcript")
    hs_post_event(hs, EV_MESSAGE, norm)
    let ev = evq_drain(hs[HS_EVENTS])
    _bool_or_die("EV_MESSAGE round-tripped through scheduler",
                 ev != 0 && event_kind(ev) == EV_MESSAGE)
    _bool_or_die("event payload matches normalized transcript",
                 str_eq(event_payload(ev),
                        "scenario w synthetic transcript") == 1)

    println("scenario_w: driver completed")
}

main()
NOVA

# Run the driver with the env vars the auto path needs. CE_AUDIO_INPUT_PATH
# pins the WAV to the path Part 1 already verified; CE_AUDIO_CAPTURE_CMD=auto
# triggers the audio_capture_record route; CE_AUDIO_CAPTURE_SCRIPT supplies
# the ABSOLUTE script path so the NOVA driver's cwd (`nova run` sets a tmp
# build dir) doesn't shadow the repo-relative default; CE_STT_BACKEND=stub
# keeps the seam deterministic (no fork to scripts/transcribe.sh -- that's
# the stt_seam test's domain).
rm -f "$CAP_WAV"
CE_AUDIO_CAPTURE_CMD=auto \
CE_STT_BACKEND=stub \
CE_AUDIO_INPUT_PATH="$CAP_WAV" \
CE_AUDIO_CAPTURE_SCRIPT="$REPO_ROOT/scripts/audio_capture.sh" \
"$NOVA_BIN" run "$DRV_SRC" > "$DRV_OUT" 2>&1
DRIVER_RC=$?

if [ "$DRIVER_RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  driver exited non-zero (rc=%d). Output:\n" "$DRIVER_RC"
    sed 's/^/        /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_w_audio_capture"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")

# Each PASS line in the driver maps to one assertion here.
assert_match "$DRV_TXT" "scenario_w: PASS  init_from_env returned 1" \
    "driver: init_from_env returns 1 with CE_AUDIO_CAPTURE_CMD=auto"
assert_match "$DRV_TXT" "scenario_w: PASS  enabled flag set" \
    "driver: stream_audio enabled after init"
assert_match "$DRV_TXT" "scenario_w: PASS  use_auto resolved" \
    "driver: use_auto = 1 when env says 'auto'"
assert_match "$DRV_TXT" "scenario_w: PASS  wav_path resolved to expected fixture" \
    "driver: wav_path matches CE_AUDIO_INPUT_PATH"
assert_match "$DRV_TXT" "scenario_w: PASS  captures_total advanced to 1" \
    "driver: poll() ran the auto-capture path"
assert_match "$DRV_TXT" "scenario_w: PASS  WAV parser yielded sample_rate=16000" \
    "driver: pure-NOVA WAV parser decodes 16 kHz"
assert_match "$DRV_TXT" "scenario_w: PASS  WAV parser yielded non-empty samples" \
    "driver: pure-NOVA WAV parser returns non-empty samples"
assert_match "$DRV_TXT" "scenario_w: PASS  EV_MESSAGE round-tripped through scheduler" \
    "driver: EV_MESSAGE post-path is wired (stream_audio -> hs -> evq)"
assert_match "$DRV_TXT" "scenario_w: PASS  event payload matches normalized transcript" \
    "driver: event payload preserved through transduce_text"
assert_match "$DRV_TXT" "scenario_w: driver completed" \
    "driver: completed without crash"

# Negative check: no FAIL line should appear in the driver output.
assert_nomatch "$DRV_TXT" "scenario_w: FAIL" \
    "driver: no FAIL lines emitted"

summary "scenario_w_audio_capture"
