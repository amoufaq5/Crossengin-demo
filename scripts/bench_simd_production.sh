#!/usr/bin/env bash
# R12A/R13A/R15A/R17C -- Production SIMD wiring benchmark.
#
# Compares scalar vs SIMD inner-loop wallclock for:
#   1. stereo SAD path: scalar reference, R12A/R13A i32 SIMD
#      (stereo_disparity_simd), and R15A u8 raw-byte SIMD
#      (_stereo_disparity_u8_simd_inner via R14B simd_sad_u8).
#   2. optical-flow LK accumulators: R10D scalar (lk_optical_flow),
#      R12A i32 SIMD (lk_optical_flow_simd), and R17C u8 packed-scan
#      (_lk_optical_flow_u8_simd_inner -- pack via memcpy_raw + scan
#      contiguous packed buffer, accumulators stay scalar because
#      simd_sad_u8 is a SAD primitive not a signed mul-acc).
#
# Both bench sources are generated here so the script stands alone; the
# generated NOVA programs live under examples/ for reproducibility +
# git-diffable timing changes.
#
# Headline measure: stereo SAD + optical-flow LK end-to-end on 256x256
# (the stereo MAX_DIM cap). win_size=7 max_disp=16 for stereo keeps
# wallclock under a minute on typical x86-64 hosts; optical-flow uses
# the R10D default win_size=5.
#
# Speedup ratio is reported as scalar_ns / SIMD_ns. R11D's SAD micro-
# benchmark showed 335-450x on the SIMD primitive itself; the realized
# end-to-end speedup is lower because per-pixel staging + byte-store
# overhead competes with the SIMD inner loop's win. R15A's u8 path
# eliminates the byte->i32 staging (one byte per pixel into a packed
# buffer vs four bytes per pixel into an i32 lane), targeting the
# 3-4x absolute speedup R13A's i32 path plateaued at 1.93x absolute.
#
# Skips cleanly if the NOVA compiler is missing.

set -euo pipefail
cd "$(dirname "$0")/.."

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
if [ ! -x "$NOVA" ]; then
    echo "(skip: nova compiler missing at $NOVA -- set NOVA_ROOT)"
    exit 0
fi

mkdir -p examples
BENCH_STEREO=examples/bench_simd_stereo.nova
BENCH_FLOW=examples/bench_simd_flow.nova

# ---------- stereo SAD bench ----------------------------------------------

cat > "$BENCH_STEREO" <<'NOVA_EOF'
// R12A stereo SAD benchmark -- 256x256 textured pair, ws=7, max_disp=16.
// Runs the scalar and SIMD disparity paths back-to-back, asserts
// bit-identical output, reports wallclock for both + speedup ratio.
import "std/io"
import "../src/io/transducers/image_stereo.nova"

fn b_textured(w, h) {
    let area = int_mul(w, h)
    let buf = alloc(area + 1)
    let y = 0
    while y < h {
        let row_off = int_mul(y, w)
        let x = 0
        while x < w {
            let v = int_add(int_mul(x, 37), int_mul(y, 13))
            let q = v / 256
            v = int_sub(v, int_mul(q, 256))
            store8(buf + row_off + x, v)
            x = x + 1
        }
        y = y + 1
    }
    store8(buf + area, 0)
    return buf
}

fn b_shift_left(src, w, h, shift) {
    let area = int_mul(w, h)
    let buf = alloc(area + 1)
    let y = 0
    while y < h {
        let row_off = int_mul(y, w)
        let x = 0
        while x < w {
            let sx = int_add(x, shift)
            let v = 0
            if sx < w { v = load8(src + row_off + sx) }
            store8(buf + row_off + x, v)
            x = x + 1
        }
        y = y + 1
    }
    store8(buf + area, 0)
    return buf
}

fn main() {
    let W = 256
    let H = 256
    let WS = 7
    let MD = 16
    println("=== R12A stereo SAD benchmark ===")
    print("  size: ")
    print_int(W)
    print("x")
    print_int(H)
    print("  win_size: ")
    print_int(WS)
    print("  max_disp: ")
    print_int(MD)
    println("")

    let lft = b_textured(W, H)
    let rgt = b_shift_left(lft, W, H, 4)

    // Warm-up.
    let _w = stereo_disparity_simd(lft, rgt, W, H, WS, MD)

    let t0 = nanotime()
    let r_simd = stereo_disparity_simd(lft, rgt, W, H, WS, MD)
    let t1 = nanotime()
    let simd_ns = int_sub(t1, t0)
    let mean_simd = stereo_result_mean(r_simd)
    let dens_simd = stereo_result_density(r_simd)

    // R15A: u8 raw-byte SIMD path. _stereo_disparity_u8_simd_inner is
    // called by stereo_disparity_u8_simd when CE_STEREO_U8_SIMD=on; we
    // call it directly here so the bench reports the u8 path's cost
    // regardless of how the caller's env is configured. Bypasses the
    // dispatch + input validation -- inputs are well-formed.
    let area_u8 = int_mul(W, H)
    let half_u8 = WS / 2
    let _wu8 = _stereo_disparity_u8_simd_inner(lft, rgt, W, H, WS, MD, area_u8, half_u8)
    let t0_u8 = nanotime()
    let r_u8 = _stereo_disparity_u8_simd_inner(lft, rgt, W, H, WS, MD, area_u8, half_u8)
    let t1_u8 = nanotime()
    let u8_ns = int_sub(t1_u8, t0_u8)
    let mean_u8 = stereo_result_mean(r_u8)
    let dens_u8 = stereo_result_density(r_u8)

    // Scalar reference inline -- uses stereo_sad_block (canonical
    // scalar SAD). Pre-R12A stereo_disparity inner loop.
    let area = int_mul(W, H)
    let half = WS / 2
    let map = alloc(area + 1)
    let zi = 0
    while zi < area {
        store8(map + zi, 0)
        zi = int_add(zi, 1)
    }
    store8(map + area, 0)
    let scalar_mean_sum = 0
    let scalar_valid_count = 0
    let t2 = nanotime()
    let y = half
    let y_max = int_sub(H, half)
    while y < y_max {
        let row_off = int_mul(y, W)
        let x = half
        let x_max = int_sub(W, half)
        while x < x_max {
            let local_max_d = MD
            let cap = int_sub(x, half)
            if local_max_d > cap { local_max_d = cap }
            if local_max_d < 0   { local_max_d = 0 }
            let best_sad = -1
            let best_d   = 0
            let d = 0
            while d <= local_max_d {
                let sad = stereo_sad_block(lft, rgt, W, x, int_sub(x, d), y, WS)
                if best_sad < 0 {
                    best_sad = sad
                    best_d   = d
                } else {
                    if sad < best_sad {
                        best_sad = sad
                        best_d   = d
                    }
                }
                d = int_add(d, 1)
            }
            store8(map + int_add(row_off, x), best_d)
            scalar_valid_count = int_add(scalar_valid_count, 1)
            scalar_mean_sum = int_add(scalar_mean_sum, best_d)
            x = int_add(x, 1)
        }
        y = int_add(y, 1)
    }
    let t3 = nanotime()
    let scalar_ns = int_sub(t3, t2)

    let mism = 0
    let mi = 0
    let m_simd = stereo_result_map(r_simd)
    while mi < area {
        if load8(map + mi) != load8(m_simd + mi) { mism = int_add(mism, 1) }
        mi = int_add(mi, 1)
    }
    // R15A: also assert u8 SIMD bit-identical to scalar.
    let mism_u8 = 0
    let mu8 = 0
    let m_u8 = stereo_result_map(r_u8)
    while mu8 < area {
        if load8(map + mu8) != load8(m_u8 + mu8) { mism_u8 = int_add(mism_u8, 1) }
        mu8 = int_add(mu8, 1)
    }
    let scalar_mean = 0
    if scalar_valid_count > 0 { scalar_mean = scalar_mean_sum / scalar_valid_count }
    print("  scalar  mean disparity:  ")
    print_int(scalar_mean)
    println("")
    print("  i32SIMD mean disparity:  ")
    print_int(mean_simd)
    println("")
    print("  u8 SIMD mean disparity:  ")
    print_int(mean_u8)
    println("")
    print("  u8 SIMD density (milli): ")
    print_int(dens_u8)
    println("")
    print("  i32 vs scalar mismatch:  ")
    print_int(mism)
    println("")
    print("  u8  vs scalar mismatch:  ")
    print_int(mism_u8)
    println("")
    if mism > 0 {
        println("FAIL: scalar vs i32 SIMD disparity disagree at pixel level")
        exit(1)
    }
    if mism_u8 > 0 {
        println("FAIL: scalar vs u8 SIMD disparity disagree at pixel level")
        exit(1)
    }
    print("  scalar  wallclock (ns):  ")
    print_int(scalar_ns)
    println("")
    print("  i32SIMD wallclock (ns):  ")
    print_int(simd_ns)
    println("")
    print("  u8 SIMD wallclock (ns):  ")
    print_int(u8_ns)
    println("")
    if simd_ns > 0 {
        let ratio_x100 = int_div(int_mul(scalar_ns, 100), simd_ns)
        let whole = int_div(ratio_x100, 100)
        let frac  = ratio_x100 % 100
        print("  i32 SIMD speedup vs scalar: ~")
        print_int(whole)
        print(".")
        if frac < 10 { print("0") }
        print_int(frac)
        println("x")
    }
    if u8_ns > 0 {
        let ratio_u8_x100 = int_div(int_mul(scalar_ns, 100), u8_ns)
        let whole_u8 = int_div(ratio_u8_x100, 100)
        let frac_u8  = ratio_u8_x100 % 100
        print("  u8  SIMD speedup vs scalar: ~")
        print_int(whole_u8)
        print(".")
        if frac_u8 < 10 { print("0") }
        print_int(frac_u8)
        println("x")
        // R15A target: 3-4x absolute (vs the R13A 1.93x i32 ceiling).
        let rel_x100 = int_div(int_mul(simd_ns, 100), u8_ns)
        let whole_r = int_div(rel_x100, 100)
        let frac_r  = rel_x100 % 100
        print("  u8 SIMD speedup vs i32 SIMD: ~")
        print_int(whole_r)
        print(".")
        if frac_r < 10 { print("0") }
        print_int(frac_r)
        println("x")
    } else {
        println("  u8 SIMD wallclock 0 -- below resolution")
    }
}

main()
NOVA_EOF

echo "=== R12A: stereo SAD bench (256x256, ws=7, max_disp=16) ==="
$NOVA run "$BENCH_STEREO"

# ---------- optical-flow LK bench -----------------------------------------

cat > "$BENCH_FLOW" <<'NOVA_EOF'
// R12A optical-flow LK benchmark -- 256x256 smooth-quadratic prev / shifted next.
import "std/io"
import "../src/io/transducers/image_optical_flow.nova"

fn b_smooth(w, h) {
    let area = int_mul(w, h)
    let buf = alloc(area + 1)
    let y = 0
    while y < h {
        let row_off = int_mul(y, w)
        let x = 0
        while x < w {
            let xx = int_mul(x, x)
            let yy = int_mul(y, y)
            let v = int_add(xx, int_mul(3, yy)) / 8
            if v > 255 { v = 255 }
            store8(buf + row_off + x, v)
            x = x + 1
        }
        y = y + 1
    }
    store8(buf + area, 0)
    return buf
}

fn b_shift_right(src, w, h, shift) {
    let area = int_mul(w, h)
    let buf = alloc(area + 1)
    let y = 0
    while y < h {
        let row_off = int_mul(y, w)
        let x = 0
        while x < w {
            let sx = int_sub(x, shift)
            let v = 0
            if sx >= 0 {
                if sx < w { v = load8(src + row_off + sx) }
            }
            store8(buf + row_off + x, v)
            x = x + 1
        }
        y = y + 1
    }
    store8(buf + area, 0)
    return buf
}

fn main() {
    let W = 256
    let H = 256
    let WS = 5
    println("=== R12A/R17C optical-flow LK benchmark ===")
    print("  size: ")
    print_int(W)
    print("x")
    print_int(H)
    print("  win_size: ")
    print_int(WS)
    println("")

    let prev = b_smooth(W, H)
    let next = b_shift_right(prev, W, H, 2)

    let _w = lk_optical_flow_simd(prev, next, W, H, WS)

    let t0 = nanotime()
    let r_sc = lk_optical_flow(prev, next, W, H, WS)
    let t1 = nanotime()
    let scalar_ns = int_sub(t1, t0)

    let t2 = nanotime()
    let r_sd = lk_optical_flow_simd(prev, next, W, H, WS)
    let t3 = nanotime()
    let simd_ns = int_sub(t3, t2)

    // R17C: u8 packed-scan SIMD path. _lk_optical_flow_u8_simd_inner
    // is called by lk_optical_flow_u8_simd when CE_LK_U8_SIMD=on; we
    // call it directly here so the bench reports the u8 path's cost
    // regardless of env state. Bypasses dispatch + validation -- inputs
    // are well-formed by construction. Mirrors R15A's stereo u8 bench.
    let half_u8 = WS / 2
    let pad_u8  = int_add(half_u8, 1)
    let area_u8 = int_mul(W, H)
    let _wu8 = _lk_optical_flow_u8_simd_inner(prev, next, W, H, WS,
                                               half_u8, pad_u8, area_u8)
    let t4 = nanotime()
    let r_u8 = _lk_optical_flow_u8_simd_inner(prev, next, W, H, WS,
                                               half_u8, pad_u8, area_u8)
    let t5 = nanotime()
    let u8_ns = int_sub(t5, t4)

    // R17C: also time the lk_image_sad_residual_u8 helper -- canonical
    // pyramidal-LK convergence metric (Σ|next - prev| over full image).
    // This is the PURE-SIMD path: rows ARE contiguous, so simd_sad_u8
    // is called per-row with no packing. Compare to scalar Σ|a-b|.
    let t6 = nanotime()
    let sad_sc = 0
    let ix = 0
    let area_resid = int_mul(W, H)
    while ix < area_resid {
        let pv = load8(int_add(prev, ix))
        let nv = load8(int_add(next, ix))
        let dv = int_sub(nv, pv)
        if dv < 0 { dv = 0 - dv }
        sad_sc = int_add(sad_sc, dv)
        ix = int_add(ix, 1)
    }
    let t7 = nanotime()
    let sad_scalar_ns = int_sub(t7, t6)
    let t8 = nanotime()
    let sad_simd = lk_image_sad_residual_u8(prev, next, W, H)
    let t9 = nanotime()
    let sad_simd_ns = int_sub(t9, t8)

    let mm_sc = lk_flow_mean_magnitude(r_sc)
    let mm_sd = lk_flow_mean_magnitude(r_sd)
    let mm_u8 = lk_flow_mean_magnitude(r_u8)
    let vc_sc = lk_flow_valid_count(r_sc)
    let vc_sd = lk_flow_valid_count(r_sd)
    let vc_u8 = lk_flow_valid_count(r_u8)

    print("  scalar  mean magnitude: ")
    print_int(mm_sc)
    println("")
    print("  i32SIMD mean magnitude: ")
    print_int(mm_sd)
    println("")
    print("  u8 SIMD mean magnitude: ")
    print_int(mm_u8)
    println("")
    print("  scalar  valid pixels:   ")
    print_int(vc_sc)
    println("")
    print("  i32SIMD valid pixels:   ")
    print_int(vc_sd)
    println("")
    print("  u8 SIMD valid pixels:   ")
    print_int(vc_u8)
    println("")
    if mm_sc != mm_sd {
        println("FAIL: scalar vs i32 SIMD mean magnitude disagree")
        exit(1)
    }
    if vc_sc != vc_sd {
        println("FAIL: scalar vs i32 SIMD valid count disagree")
        exit(1)
    }
    if mm_sc != mm_u8 {
        println("FAIL: scalar vs u8 SIMD mean magnitude disagree")
        exit(1)
    }
    if vc_sc != vc_u8 {
        println("FAIL: scalar vs u8 SIMD valid count disagree")
        exit(1)
    }
    if sad_sc != sad_simd {
        println("FAIL: scalar vs SIMD image-SAD residual disagree")
        exit(1)
    }
    print("  scalar  wallclock (ns): ")
    print_int(scalar_ns)
    println("")
    print("  i32SIMD wallclock (ns): ")
    print_int(simd_ns)
    println("")
    print("  u8 SIMD wallclock (ns): ")
    print_int(u8_ns)
    println("")
    if simd_ns > 0 {
        let ratio_x100 = int_div(int_mul(scalar_ns, 100), simd_ns)
        let whole = int_div(ratio_x100, 100)
        let frac  = ratio_x100 % 100
        print("  i32 SIMD speedup vs scalar: ~")
        print_int(whole)
        print(".")
        if frac < 10 { print("0") }
        print_int(frac)
        println("x")
    } else {
        println("  i32 SIMD wallclock 0 -- below resolution")
    }
    if u8_ns > 0 {
        let ratio_u8_x100 = int_div(int_mul(scalar_ns, 100), u8_ns)
        let whole_u8 = int_div(ratio_u8_x100, 100)
        let frac_u8  = ratio_u8_x100 % 100
        print("  u8  SIMD speedup vs scalar: ~")
        print_int(whole_u8)
        print(".")
        if frac_u8 < 10 { print("0") }
        print_int(frac_u8)
        println("x")
        if simd_ns > 0 {
            let rel_x100 = int_div(int_mul(simd_ns, 100), u8_ns)
            let whole_r = int_div(rel_x100, 100)
            let frac_r  = rel_x100 % 100
            print("  u8 SIMD speedup vs i32 SIMD: ~")
            print_int(whole_r)
            print(".")
            if frac_r < 10 { print("0") }
            print_int(frac_r)
            println("x")
        }
    } else {
        println("  u8 SIMD wallclock 0 -- below resolution")
    }
    // R17C: image-SAD residual diagnostic.
    print("  image SAD scalar (ns):  ")
    print_int(sad_scalar_ns)
    println("")
    print("  image SAD u8 SIMD (ns): ")
    print_int(sad_simd_ns)
    println("")
    if sad_simd_ns > 0 {
        let rsx = int_div(int_mul(sad_scalar_ns, 100), sad_simd_ns)
        let rsw = int_div(rsx, 100)
        let rsf = rsx % 100
        print("  image SAD u8 SIMD vs scalar: ~")
        print_int(rsw)
        print(".")
        if rsf < 10 { print("0") }
        print_int(rsf)
        println("x")
    }
    print("  image SAD residual (both same): ")
    print_int(sad_simd)
    println("")
    println("HONEST NOTE: LK inner-loop ix*it / iy*it cross-products do")
    println("NOT vectorize via simd_sad_u8 (signed mul-acc, not SAD).")
    println("R17C's u8 path's win is packed-scan locality on It reads;")
    println("the pure-SAD image-residual diagnostic IS fully vectorized.")
}

main()
NOVA_EOF

echo ""
echo "=== R12A/R17C: optical-flow LK bench (256x256, ws=5) ==="
$NOVA run "$BENCH_FLOW"

echo ""
echo "=== R12A/R15A/R17C SIMD production bench: complete ==="
