#!/usr/bin/env bash
# R12A — Production SIMD wiring benchmark.
#
# Compares scalar vs SIMD inner-loop wallclock for:
#   1. stereo SAD path (R7E stereo_disparity / stereo_disparity_simd)
#   2. optical-flow LK accumulators (R10D lk_optical_flow /
#      lk_optical_flow_simd)
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
# Speedup ratio is reported as scalar_ns / simd_ns. R11D's SAD micro-
# benchmark showed 335-450x on the SIMD primitive itself; the realized
# end-to-end speedup is lower because per-pixel staging + byte-store
# overhead competes with the SIMD inner loop's win.
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
    let scalar_mean = 0
    if scalar_valid_count > 0 { scalar_mean = scalar_mean_sum / scalar_valid_count }
    print("  scalar mean disparity:  ")
    print_int(scalar_mean)
    println("")
    print("  SIMD   mean disparity:  ")
    print_int(mean_simd)
    println("")
    print("  SIMD   density (milli): ")
    print_int(dens_simd)
    println("")
    print("  bit-mismatched pixels:  ")
    print_int(mism)
    println("")
    if mism > 0 {
        println("FAIL: scalar vs SIMD disparity disagree at pixel level")
        exit(1)
    }
    print("  scalar wallclock (ns):  ")
    print_int(scalar_ns)
    println("")
    print("  SIMD   wallclock (ns):  ")
    print_int(simd_ns)
    println("")
    if simd_ns > 0 {
        let ratio_x100 = int_div(int_mul(scalar_ns, 100), simd_ns)
        let whole = int_div(ratio_x100, 100)
        let frac  = ratio_x100 % 100
        print("  speedup: ~")
        print_int(whole)
        print(".")
        if frac < 10 { print("0") }
        print_int(frac)
        println("x")
    } else {
        println("  SIMD wallclock 0 -- below resolution")
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
    println("=== R12A optical-flow LK benchmark ===")
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

    let mm_sc = lk_flow_mean_magnitude(r_sc)
    let mm_sd = lk_flow_mean_magnitude(r_sd)
    let vc_sc = lk_flow_valid_count(r_sc)
    let vc_sd = lk_flow_valid_count(r_sd)

    print("  scalar mean magnitude: ")
    print_int(mm_sc)
    println("")
    print("  SIMD   mean magnitude: ")
    print_int(mm_sd)
    println("")
    print("  scalar valid pixels:   ")
    print_int(vc_sc)
    println("")
    print("  SIMD   valid pixels:   ")
    print_int(vc_sd)
    println("")
    if mm_sc != mm_sd {
        println("FAIL: scalar vs SIMD mean magnitude disagree")
        exit(1)
    }
    if vc_sc != vc_sd {
        println("FAIL: scalar vs SIMD valid count disagree")
        exit(1)
    }
    print("  scalar wallclock (ns): ")
    print_int(scalar_ns)
    println("")
    print("  SIMD   wallclock (ns): ")
    print_int(simd_ns)
    println("")
    if simd_ns > 0 {
        let ratio_x100 = int_div(int_mul(scalar_ns, 100), simd_ns)
        let whole = int_div(ratio_x100, 100)
        let frac  = ratio_x100 % 100
        print("  speedup: ~")
        print_int(whole)
        print(".")
        if frac < 10 { print("0") }
        print_int(frac)
        println("x")
    } else {
        println("  SIMD wallclock 0 -- below resolution")
    }
}

main()
NOVA_EOF

echo ""
echo "=== R12A: optical-flow LK bench (256x256, ws=5) ==="
$NOVA run "$BENCH_FLOW"

echo ""
echo "=== R12A SIMD production bench: complete ==="
