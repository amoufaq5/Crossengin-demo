#!/usr/bin/env bash
# Scenario GGGG -- R21D: integral histogram of gradients accelerator
# for the R14D HOG dense descriptor.
#
# The scalar HOG pipeline (R14D) accumulates each pixel's magnitude
# directly into its owning cell's histogram during the gradient pass.
# The integral-histogram variant precomputes a (W * H * NUM_BINS)
# cumulative-magnitude buffer once, then recovers any cell's per-bin
# total in 4 lookups regardless of cell size. R21D's contract is
# BIT-IDENTICAL output: hog_compute_integral must produce exactly the
# same descriptor as hog_compute on every fixture, with the integer
# arithmetic reordering-safe (no precision-loss surprises).
#
# This scenario builds a standalone NOVA driver that:
#   * synthesizes a 32x32 vertical-edge fixture in-memory
#   * computes hog_compute_default + hog_compute_integral_default
#   * asserts the two descriptors are bit-identical (every element)
#   * times each path's wall-clock for a high iteration count
#   * synthesizes a 64x128 Dalal-Triggs canonical window
#   * times scalar vs integral on the canonical window
#   * reports per-path elapsed seconds + the integer ratio
#   * exits 0 iff every internal assertion held
#
# We use the standalone NOVA-driver pattern (mirrors scenario_aaaa
# and scenario_dddd) because the chat does not (yet) expose the
# integral path as a slash command -- the integral path is opt-in via
# CE_HOG_INTEGRAL and routed through hog_compute_integral_default,
# while the chat /hog command still calls hog_compute_default per
# R21D's "default-off until validated" policy.
#
# Assertions (~10):
#   1. NOVA toolchain present (pre-flight).
#   2. Driver compiles cleanly.
#   3. Driver exits 0.
#   4. 32x32 vedge: scalar descriptor length printed (324).
#   5. 32x32 vedge: integral descriptor length printed (324).
#   6. 32x32 vedge: BIT-IDENTICAL flag printed (=1).
#   7. 32x32 vedge: scalar and integral paths both produced
#      dominant_bin=0 (horizontal gradient).
#   8. 64x128 bench: scalar descriptor length 3780 printed.
#   9. 64x128 bench: integral descriptor length 3780 printed.
#  10. 64x128 bench: BIT-IDENTICAL on the canonical window.
#  11. Bench iteration count >= MIN_ITERS printed (sanity for the
#      timing measurements).
#  12. Reported speedup ratio is parseable as an integer.

. "$(dirname "$0")/_lib.sh"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    exit 2
fi

it_section "scenario GGGG: R21D integral-histogram HOG accelerator (bit-identical + bench)"

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_gggg_drivers"
mkdir -p "$DRV_DIR"
DRV_SRC="$DRV_DIR/hog_integral_drv.nova"
DRV_OUT="/tmp/ce_int_gggg_hog_integral.out"
trap '
  if [ "${CE_GGGG_KEEP:-0}" = "0" ]; then
    rm -rf "$DRV_DIR" "$DRV_OUT"
  fi
' EXIT

# Sanity that the toolchain is functional before authoring the driver.
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  NOVA toolchain present at %s\n" "$NOVA_BIN"

# ---- author the driver -----------------------------------------------------
#
# The driver uses simple int arithmetic + the two HOG entry points. It
# prints labeled lines the bash script greps for; the print contract
# is documented inline so anyone reading the source can reproduce it.

cat > "$DRV_SRC" <<'NOVA'
import "../../../src/io/transducers/image_hog.nova"

// ---- fixtures (mirror tests/unit/test_hog_integral.nova) ----------------

fn _vedge_fix(w, h, low, high) {
    let area = w * h
    let buf = alloc(area + 1)
    let half = w / 2
    let y = 0
    while y < h {
        let row_off = y * w
        let x = 0
        while x < w {
            let v = low
            if x >= half { v = high }
            store8(buf + row_off + x, v)
            x = x + 1
        }
        y = y + 1
    }
    store8(buf + area, 0)
    return buf
}

fn _hedge_fix(w, h, low, high) {
    let area = w * h
    let buf = alloc(area + 1)
    let half = h / 2
    let y = 0
    while y < h {
        let row_off = y * w
        let v = low
        if y >= half { v = high }
        let x = 0
        while x < w {
            store8(buf + row_off + x, v)
            x = x + 1
        }
        y = y + 1
    }
    store8(buf + area, 0)
    return buf
}

// _identical: walks two descriptor lists. Prints DIFF_AT k for the
// first mismatch (so the bash script can report a meaningful failure
// signature), or BIT_IDENTICAL=1 on a full match.
fn _identical(label, a, b) {
    let na = len(a)
    let nb = len(b)
    if na != nb {
        println(label + " LENGTH_MISMATCH a=" + int_to_str(na) + " b=" + int_to_str(nb))
        return 0
    }
    let k = 0
    let first = 0 - 1
    while k < na {
        if a[k] != b[k] {
            if first < 0 { first = k }
        }
        k = k + 1
    }
    if first < 0 {
        println(label + " BIT_IDENTICAL=1")
        return 1
    }
    println(label + " DIFF_AT k=" + int_to_str(first)
            + " a=" + int_to_str(a[first])
            + " b=" + int_to_str(b[first]))
    return 0
}

// ---- bench surface --------------------------------------------------------
//
// NOVA's time() builtin has 1-second resolution. We run each path
// ITERS_32 times on the 32x32 fixture and ITERS_64 times on the
// 64x128 fixture (smaller ITERS_64 because the larger image is
// proportionally slower; total wall-clock targets ~3-5s per path so
// the ratio is stable).

// Iterations sized so each path spans >= 2 wall-clock seconds at the
// expected throughput. NOVA's time() is 1-second resolution, so we
// need both paths to clear several seconds to get a stable ratio.
// Empirically the 32x32 scalar path is sub-millisecond per iteration
// so 20000 iterations targets ~5-10 seconds; the 64x128 path is
// ~20x slower per iteration, so 1000 iterations targets the same
// wall-clock budget.
let ITERS_32 = 20000
let ITERS_64 = 1000

fn bench_path_scalar_32(buf, iters) {
    let i = 0
    let last_dom = 0
    let last_desc_len = 0
    while i < iters {
        let r = hog_compute_default(buf, 32, 32)
        last_dom = hog_result_dominant_bin(r)
        last_desc_len = len(hog_descriptor(r))
        i = i + 1
    }
    let out = list_new()
    push(out, last_dom)
    push(out, last_desc_len)
    return out
}

fn bench_path_integral_32(buf, iters) {
    let i = 0
    let last_dom = 0
    let last_desc_len = 0
    while i < iters {
        let r = hog_compute_integral_default(buf, 32, 32)
        last_dom = hog_result_dominant_bin(r)
        last_desc_len = len(hog_descriptor(r))
        i = i + 1
    }
    let out = list_new()
    push(out, last_dom)
    push(out, last_desc_len)
    return out
}

fn bench_path_scalar_64(buf, iters) {
    let i = 0
    let last_dom = 0
    let last_desc_len = 0
    while i < iters {
        let r = hog_compute_default(buf, 64, 128)
        last_dom = hog_result_dominant_bin(r)
        last_desc_len = len(hog_descriptor(r))
        i = i + 1
    }
    let out = list_new()
    push(out, last_dom)
    push(out, last_desc_len)
    return out
}

fn bench_path_integral_64(buf, iters) {
    let i = 0
    let last_dom = 0
    let last_desc_len = 0
    while i < iters {
        let r = hog_compute_integral_default(buf, 64, 128)
        last_dom = hog_result_dominant_bin(r)
        last_desc_len = len(hog_descriptor(r))
        i = i + 1
    }
    let out = list_new()
    push(out, last_dom)
    push(out, last_desc_len)
    return out
}

fn safe_div(a, b) {
    if b <= 0 { return 0 }
    return a / b
}

fn main() {
    println("DRV scenario_gggg: HOG integral-histogram accelerator")

    // ---- stage 1: bit-identical 32x32 vedge --------------------------
    let buf_v = _vedge_fix(32, 32, 0, 255)
    let r_s = hog_compute_default(buf_v, 32, 32)
    let r_i = hog_compute_integral_default(buf_v, 32, 32)
    println("DRV vedge32 scalar_desc_len=" + int_to_str(len(hog_descriptor(r_s))))
    println("DRV vedge32 integral_desc_len=" + int_to_str(len(hog_descriptor(r_i))))
    println("DRV vedge32 scalar_dominant_bin=" + int_to_str(hog_result_dominant_bin(r_s)))
    println("DRV vedge32 integral_dominant_bin=" + int_to_str(hog_result_dominant_bin(r_i)))
    let ok_v = _identical("DRV vedge32", hog_descriptor(r_s), hog_descriptor(r_i))

    // ---- stage 2: bit-identical 32x32 hedge --------------------------
    let buf_h = _hedge_fix(32, 32, 0, 255)
    let r_s_h = hog_compute_default(buf_h, 32, 32)
    let r_i_h = hog_compute_integral_default(buf_h, 32, 32)
    let ok_h = _identical("DRV hedge32", hog_descriptor(r_s_h), hog_descriptor(r_i_h))

    // ---- stage 3: bit-identical 64x128 Dalal-Triggs ------------------
    let buf_dt = _vedge_fix(64, 128, 0, 255)
    let r_s_dt = hog_compute_default(buf_dt, 64, 128)
    let r_i_dt = hog_compute_integral_default(buf_dt, 64, 128)
    println("DRV vedge64x128 scalar_desc_len=" + int_to_str(len(hog_descriptor(r_s_dt))))
    println("DRV vedge64x128 integral_desc_len=" + int_to_str(len(hog_descriptor(r_i_dt))))
    let ok_dt = _identical("DRV vedge64x128", hog_descriptor(r_s_dt), hog_descriptor(r_i_dt))

    // ---- stage 4: bench 32x32 ----------------------------------------
    println("DRV bench32 iters=" + int_to_str(ITERS_32))
    let t0 = time()
    let _s32 = bench_path_scalar_32(buf_v, ITERS_32)
    let t1 = time()
    let e_s32 = t1 - t0
    let t2 = time()
    let _i32 = bench_path_integral_32(buf_v, ITERS_32)
    let t3 = time()
    let e_i32 = t3 - t2
    println("DRV bench32 scalar_elapsed_s=" + int_to_str(e_s32))
    println("DRV bench32 integral_elapsed_s=" + int_to_str(e_i32))
    // Speedup expressed in milli-units (scalar_ms / integral_ms scaled
    // up so we can keep integer math). When integral wins, ratio > 1000;
    // when scalar wins, ratio < 1000.
    let scalar_milli_32 = e_s32 * 1000
    let ratio_milli_32 = safe_div(scalar_milli_32, e_i32)
    println("DRV bench32 speedup_milli=" + int_to_str(ratio_milli_32))

    // ---- stage 5: bench 64x128 ---------------------------------------
    println("DRV bench64x128 iters=" + int_to_str(ITERS_64))
    let t4 = time()
    let _s64 = bench_path_scalar_64(buf_dt, ITERS_64)
    let t5 = time()
    let e_s64 = t5 - t4
    let t6 = time()
    let _i64 = bench_path_integral_64(buf_dt, ITERS_64)
    let t7 = time()
    let e_i64 = t7 - t6
    println("DRV bench64x128 scalar_elapsed_s=" + int_to_str(e_s64))
    println("DRV bench64x128 integral_elapsed_s=" + int_to_str(e_i64))
    let scalar_milli_64 = e_s64 * 1000
    let ratio_milli_64 = safe_div(scalar_milli_64, e_i64)
    println("DRV bench64x128 speedup_milli=" + int_to_str(ratio_milli_64))

    // ---- final tally -------------------------------------------------
    let all_ok = 1
    if ok_v == 0  { all_ok = 0 }
    if ok_h == 0  { all_ok = 0 }
    if ok_dt == 0 { all_ok = 0 }
    println("DRV summary all_ok=" + int_to_str(all_ok))
    if all_ok == 0 {
        exit(1)
    }
    exit(0)
}

main()
NOVA

# 2. Compile driver.
if "$NOVA_BIN" build "$DRV_SRC" -o "$DRV_DIR/drv.bin" >/tmp/ce_gggg_compile.log 2>&1; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  driver compiles cleanly\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  driver did not compile\n"
    sed 's/^/        /' /tmp/ce_gggg_compile.log
    summary "scenario_gggg_hog_integral"
    exit
fi

# 3. Run driver.
"$DRV_DIR/drv.bin" >"$DRV_OUT" 2>&1
RC=$?
if [ $RC -eq 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  driver exits 0\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  driver exit code %d\n" "$RC"
    sed 's/^/        /' "$DRV_OUT"
    summary "scenario_gggg_hog_integral"
    exit
fi

OUT="$(cat "$DRV_OUT")"

# Stream the driver's output to the operator (for traceability).
printf "%s.... driver output ....%s\n" "$C_DIM" "$C_RST"
echo "$OUT" | sed 's/^/    /'
printf "%s.......................%s\n" "$C_DIM" "$C_RST"

# 4-5. 32x32 vedge descriptor lengths.
assert_match "$OUT" "DRV vedge32 scalar_desc_len=324" \
    "32x32 vedge scalar descriptor length = 324"
assert_match "$OUT" "DRV vedge32 integral_desc_len=324" \
    "32x32 vedge integral descriptor length = 324"

# 6. 32x32 vedge BIT-IDENTICAL flag.
assert_match "$OUT" "DRV vedge32 BIT_IDENTICAL=1" \
    "32x32 vedge: integral and scalar descriptors are bit-identical"

# 7. 32x32 vedge dominant_bin agreement at 0.
assert_match "$OUT" "DRV vedge32 scalar_dominant_bin=0" \
    "32x32 vedge scalar dominant_bin = 0 (horizontal gradient)"
assert_match "$OUT" "DRV vedge32 integral_dominant_bin=0" \
    "32x32 vedge integral dominant_bin = 0 (matches scalar)"

# 8. 32x32 hedge BIT-IDENTICAL.
assert_match "$OUT" "DRV hedge32 BIT_IDENTICAL=1" \
    "32x32 hedge: integral and scalar descriptors are bit-identical"

# 9-10. 64x128 Dalal-Triggs bit-identical.
assert_match "$OUT" "DRV vedge64x128 scalar_desc_len=3780" \
    "64x128 vedge scalar descriptor length = 3780"
assert_match "$OUT" "DRV vedge64x128 integral_desc_len=3780" \
    "64x128 vedge integral descriptor length = 3780"
assert_match "$OUT" "DRV vedge64x128 BIT_IDENTICAL=1" \
    "64x128 vedge (Dalal-Triggs window): integral and scalar bit-identical"

# 11. Bench iter count is sane.
assert_match "$OUT" "DRV bench32 iters=20000" \
    "32x32 bench iteration count = 20000"
assert_match "$OUT" "DRV bench64x128 iters=1000" \
    "64x128 bench iteration count = 1000"

# 12. Speedup ratio extractable as an integer (the driver formats the
# ratio with integer string conversion, so a regex check is enough).
# We don't HARD-ASSERT integral > scalar here because:
#   - NOVA's time() has 1-second resolution and short benchmarks can
#     round to zero, making the ratio uninformative.
#   - On the 32x32 fixture the build overhead can win or lose against
#     the saved per-cell loop work depending on iteration shape.
# We DO assert the path PRINTED a parseable integer in the speedup line,
# so the operator can read the actual ratio off the trace above.
assert_match "$OUT" "DRV bench32 speedup_milli=[0-9]+" \
    "32x32 bench speedup ratio printed as integer milli-units"
assert_match "$OUT" "DRV bench64x128 speedup_milli=[0-9]+" \
    "64x128 bench speedup ratio printed as integer milli-units"

# 13. all_ok summary.
assert_match "$OUT" "DRV summary all_ok=1" \
    "driver all_ok summary = 1 (every bit-identical check passed)"

summary "scenario_gggg_hog_integral"
