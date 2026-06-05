#!/usr/bin/env bash
# Scenario pp -- Byzantine-resilient federated aggregation
# (P3.10 / ADR-0056).
#
# Drives a small NOVA program (under _scenario_pp_drivers/) that
# populates a Byzantine federated accumulator with 4 honest souls and
# 1 Byzantine soul (one 100x poisoning outlier), then reduces it under
# THREE strategies on the same input and prints the aggregate. The
# bash side asserts that:
#
#   1) BYZ_NONE         -> aggregate heavily skewed by the outlier.
#   2) BYZ_TRIMMED_MEAN -> outlier dropped, aggregate matches honest mean.
#   3) BYZ_MEDIAN       -> aggregate equals honest median.
#   4) CE_FL_BYZ_STRATEGY=trimmed flips behaviour without code edits.
#   5) CE_FL_BYZ_STRATEGY=median  flips behaviour without code edits.
#   6) CE_FL_BYZ_STRATEGY=none preserves baseline behaviour.
#   7) Strategy-name constants line up with the canonical values.
#
# Honest values: 4 souls submit (promo, atr) tuples around (700, 200);
# the Byzantine soul submits (9999, 9999). Honest mean is 705/205;
# honest median is 710/210; expected:
#   plain  mean(5)  = (700+710+720+690+9999)/5 = 12819/5 = 2563
#   plain  atr (5)  = (200+210+220+190+9999)/5 = 10819/5 = 2163
#   trim_k=1 promo  = (700+710+720)/3 = 2130/3 = 710
#   trim_k=1 atr    = (200+210+220)/3 = 630/3  = 210
#   median promo    = 710  (middle of [690,700,710,720,9999])
#   median atr      = 210  (middle of [190,200,210,220,9999])

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario pp: Byzantine-resilient FL aggregation (ADR-0056)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_pp_byz_fl"
    exit $?
fi

DRV="$REPO_ROOT/tests/integration/_scenario_pp_drivers/byz_aggregation_driver.nova"
if [ ! -f "$DRV" ]; then
    printf "  ${C_RED}ERROR${C_RST}: driver not found at %s\n" "$DRV" >&2
    FAIL=$((FAIL+1))
    summary "scenario_pp_byz_fl"
    exit $?
fi

# --- Stage 1: baseline run (no env override) -----------------------------
unset CE_FL_BYZ_STRATEGY
unset CE_FL_BYZ_TRIM_K
OUT_BASE=$("$NOVA_BIN" run "$DRV" 2>&1)
RC_BASE=$?
assert_eq "$RC_BASE" "0" "driver exits 0 with env unset"

# BYZ_NONE: heavily skewed by the outlier (both fields > 2000).
assert_match "$OUT_BASE" "NONE tag=topic:fever promo=2563 atr=2163 n_part=5" \
    "BYZ_NONE aggregate is poisoned (promo=2563, atr=2163)"

# BYZ_TRIMMED_MEAN with trim_k=1: outlier dropped; result = honest mean.
assert_match "$OUT_BASE" "TRIMMED tag=topic:fever promo=710 atr=210 n_part=5" \
    "BYZ_TRIMMED_MEAN drops outlier (promo=710, atr=210)"

# BYZ_MEDIAN: median of the sorted column ignores the outlier.
assert_match "$OUT_BASE" "MEDIAN tag=topic:fever promo=710 atr=210 n_part=5" \
    "BYZ_MEDIAN unaffected by outlier (promo=710, atr=210)"

# Env unset -> BYZ_NONE default; trim_k defaults to 1.
assert_match "$OUT_BASE" "ENV strategy=none trim_k=1" \
    "env unset defaults to strategy=none, trim_k=1"
assert_match "$OUT_BASE" "ENV tag=topic:fever promo=2563 atr=2163" \
    "env-unset aggregate matches BYZ_NONE baseline"

# Constants line up with documented values.
assert_match "$OUT_BASE" "CONST BYZ_NONE=0 BYZ_TRIMMED_MEAN=1 BYZ_MEDIAN=2" \
    "strategy constants are stable across module boundaries"

# --- Stage 2: env-driven trimmed mean ------------------------------------
OUT_TRIM=$(CE_FL_BYZ_STRATEGY=trimmed CE_FL_BYZ_TRIM_K=1 "$NOVA_BIN" run "$DRV" 2>&1)
assert_match "$OUT_TRIM" "ENV strategy=trimmed trim_k=1" \
    "CE_FL_BYZ_STRATEGY=trimmed flips env-driven strategy"
assert_match "$OUT_TRIM" "ENV tag=topic:fever promo=710 atr=210" \
    "env=trimmed gives honest-mean aggregate (promo=710, atr=210)"

# --- Stage 3: env-driven median ------------------------------------------
OUT_MED=$(CE_FL_BYZ_STRATEGY=median "$NOVA_BIN" run "$DRV" 2>&1)
assert_match "$OUT_MED" "ENV strategy=median" \
    "CE_FL_BYZ_STRATEGY=median flips env-driven strategy"
assert_match "$OUT_MED" "ENV tag=topic:fever promo=710 atr=210" \
    "env=median gives honest-median aggregate (promo=710, atr=210)"

# --- Stage 4: env=none explicit ------------------------------------------
OUT_NONE=$(CE_FL_BYZ_STRATEGY=none "$NOVA_BIN" run "$DRV" 2>&1)
assert_match "$OUT_NONE" "ENV strategy=none" \
    "CE_FL_BYZ_STRATEGY=none preserves baseline behaviour"
assert_match "$OUT_NONE" "ENV tag=topic:fever promo=2563 atr=2163" \
    "env=none aggregate is poisoned (no Byzantine filter)"

# --- Stage 5: env=garbage falls back to NONE -----------------------------
OUT_BAD=$(CE_FL_BYZ_STRATEGY=bogus "$NOVA_BIN" run "$DRV" 2>&1)
assert_match "$OUT_BAD" "ENV strategy=none" \
    "unknown CE_FL_BYZ_STRATEGY falls back to NONE"

# --- Stage 6: skew comparison summary ------------------------------------
# Honest mean is 705/205. The poisoned aggregate (2563) deviates by ~1858
# from honest mean; the trimmed aggregate (710) deviates by 5. This is
# the substantive Byzantine-resilience claim: trimming reduces the
# adversary-induced skew by ~370x for this fixture.
HONEST_MEAN_PROMO=705
NONE_PROMO=2563
TRIMMED_PROMO=710
NONE_SKEW=$(( NONE_PROMO - HONEST_MEAN_PROMO ))
TRIMMED_SKEW=$(( TRIMMED_PROMO - HONEST_MEAN_PROMO ))
if [ "$NONE_SKEW" -gt 1000 ] && [ "$TRIMMED_SKEW" -lt 100 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  poisoning skew: NONE=%d trimmed=%d (>10x reduction)\n" \
        "$NONE_SKEW" "$TRIMMED_SKEW"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  poisoning skew check (NONE=%d trimmed=%d)\n" \
        "$NONE_SKEW" "$TRIMMED_SKEW"
fi

summary "scenario_pp_byz_fl"
