#!/usr/bin/env bash
# Scenario III -- Ed25519 signing primitive (RFC 8032) end-to-end.
#
# Where this fits: CrossEngin's crypto stack already covers
# confidentiality (ChaCha20-Poly1305 AEAD), key agreement (Curve25519
# DH-256 + RFC 7919 G14 DH-2048), authenticated channels (Noise XK),
# and Byzantine-resilient federated aggregation (SecAgg). What was
# missing: a DIGITAL SIGNATURE primitive for snapshot attestation, KG
# provenance, and federation peer auth tokens. R14F's
# src/safety/ed25519.nova ships Ed25519 (the modern standard: 32-byte
# keys, 64-byte signatures, fast, well-analyzed).
#
# This scenario drives the public surface via a NOVA driver and
# asserts that:
#   * Keypair generation produces 32B seed + 32B pubkey.
#   * Signing a known message produces a 64-byte signature.
#   * Verify on the canonical (message, signature, pubkey) triple
#     returns 1.
#   * Tamper detection works on all three paths: a different message,
#     a flipped signature bit, and a substituted pubkey each cause
#     verify to return 0.
#   * RFC 8032 TEST 1 (empty message + the published sk) reproduces
#     the published 64-byte signature bit-exact.
#   * Sign latency on a 32-byte message is reported and assertively
#     under 30 s. (Expected: ~250-1000 ms on this sandbox; the brief
#     called out ~50-500 ms but bn256_modpow_ct currently dominates.)
#
# KNOWN LIMITATIONS:
#   * No external `nova` toolchain dependency check beyond the
#     standard NOVA_ROOT lookup; if the NOVA launcher isn't present
#     the script reports an explicit ERROR and FAILs (same convention
#     as scenario_gg_noise_kg.sh).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario III: Ed25519 signing (R14F)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_iii_ed25519"
    exit $?
fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_iii_drivers"
mkdir -p "$DRV_DIR"
OUT="/tmp/ce_int_iii_ed25519.out"

trap '
  rm -rf "$DRV_DIR" "$OUT"
' EXIT

# ---- driver: exercises every Ed25519 public surface --------------------
DRV_SRC="$DRV_DIR/driver.nova"
cat > "$DRV_SRC" <<'NOVA'
import "std/io"
import "../../../src/safety/ed25519.nova"

// String -> byte list (each char becomes one byte).
fn _bytes_from_str(s) {
    let out = list_new()
    let i = 0
    let n = len(s)
    while i < n {
        push(out, char_at(s, i))
        i = i + 1
    }
    return out
}

fn main() {
    // ---- 1. Random keypair generation ------------------------------
    let kp = ed25519_keygen()
    let seed = kp[0]
    let pk = kp[1]
    println("KEYGEN_SEED_LEN=" + int_to_str(len(seed)))
    println("KEYGEN_PK_LEN=" + int_to_str(len(pk)))

    // ---- 2. Sign a known message + measure latency -----------------
    let msg = _bytes_from_str("CrossEngin signed payload v1")
    let t0 = nanotime()
    let sig = ed25519_sign(msg, seed, pk)
    let t1 = nanotime()
    let sign_ns = t1 - t0
    let sign_ms = sign_ns / 1000000
    println("SIGN_LEN=" + int_to_str(len(sig)))
    println("SIGN_MS=" + int_to_str(sign_ms))

    // ---- 3. Verify the (msg, sig, pk) triple -----------------------
    let v = ed25519_verify(msg, sig, pk)
    println("VERIFY_CANONICAL=" + int_to_str(v))

    // ---- 4. Tamper: different message ------------------------------
    let msg_other = _bytes_from_str("CrossEngin signed payload v2")
    let v_msg = ed25519_verify(msg_other, sig, pk)
    println("VERIFY_TAMPER_MSG=" + int_to_str(v_msg))

    // ---- 5. Tamper: flip a bit in the signature --------------------
    let sig_bad = list_new()
    let i = 0
    while i < 64 {
        push(sig_bad, sig[i])
        i = i + 1
    }
    list_set(sig_bad, 17, int_xor(sig_bad[17], 1))
    let v_sig = ed25519_verify(msg, sig_bad, pk)
    println("VERIFY_TAMPER_SIG=" + int_to_str(v_sig))

    // ---- 6. Tamper: wrong pubkey (a second freshly generated one) --
    let kp2 = ed25519_keygen()
    let pk2 = kp2[1]
    let v_pk = ed25519_verify(msg, sig, pk2)
    println("VERIFY_TAMPER_PK=" + int_to_str(v_pk))

    // ---- 7. RFC 8032 TEST 1 reproduction ---------------------------
    let test1_sk = ed25519_hex_to_bytes("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    let test1_parts = _ed_derive_a_and_prefix(test1_sk)
    let test1_pk = _ed_pk_from_a(test1_parts[0])
    let test1_msg = list_new()
    let test1_sig = ed25519_sign(test1_msg, test1_sk, test1_pk)
    let test1_pk_hex = ed25519_bytes_to_hex(test1_pk)
    let test1_sig_hex = ed25519_bytes_to_hex(test1_sig)
    println("RFC8032_T1_PK=" + test1_pk_hex)
    println("RFC8032_T1_SIG=" + test1_sig_hex)
    let test1_v = ed25519_verify(test1_msg, test1_sig, test1_pk)
    println("RFC8032_T1_VERIFY=" + int_to_str(test1_v))

    exit(0)
}

main()
NOVA

# ---- run the driver ----------------------------------------------------
"$NOVA_BIN" run "$DRV_SRC" >"$OUT" 2>&1
RC=$?
OUT_TXT=$(cat "$OUT" 2>/dev/null || true)

assert_eq "$RC" "0" "driver exited 0"

# ---- assertion 1: keypair shape ----------------------------------------
SEED_LEN=$(echo "$OUT_TXT" | grep -oE 'KEYGEN_SEED_LEN=[0-9]+' | sed 's/KEYGEN_SEED_LEN=//' | head -1)
PK_LEN=$(echo "$OUT_TXT" | grep -oE 'KEYGEN_PK_LEN=[0-9]+' | sed 's/KEYGEN_PK_LEN=//' | head -1)
assert_eq "$SEED_LEN" "32" "keygen seed is 32 bytes"
assert_eq "$PK_LEN" "32" "keygen pubkey is 32 bytes"

# ---- assertion 2: signature shape ---------------------------------------
SIG_LEN=$(echo "$OUT_TXT" | grep -oE 'SIGN_LEN=[0-9]+' | sed 's/SIGN_LEN=//' | head -1)
assert_eq "$SIG_LEN" "64" "signature is 64 bytes"

# ---- assertion 3: canonical verify --------------------------------------
V_CAN=$(echo "$OUT_TXT" | grep -oE 'VERIFY_CANONICAL=[0-9]+' | sed 's/VERIFY_CANONICAL=//' | head -1)
assert_eq "$V_CAN" "1" "verify canonical (msg, sig, pk) returns 1"

# ---- assertion 4..6: tamper-detection -----------------------------------
V_MSG=$(echo "$OUT_TXT" | grep -oE 'VERIFY_TAMPER_MSG=[0-9]+' | sed 's/VERIFY_TAMPER_MSG=//' | head -1)
V_SIG=$(echo "$OUT_TXT" | grep -oE 'VERIFY_TAMPER_SIG=[0-9]+' | sed 's/VERIFY_TAMPER_SIG=//' | head -1)
V_PK=$(echo "$OUT_TXT" | grep -oE 'VERIFY_TAMPER_PK=[0-9]+' | sed 's/VERIFY_TAMPER_PK=//' | head -1)
assert_eq "$V_MSG" "0" "tamper detection: different message rejected"
assert_eq "$V_SIG" "0" "tamper detection: flipped signature bit rejected"
assert_eq "$V_PK" "0" "tamper detection: wrong pubkey rejected"

# ---- assertion 7: RFC 8032 TEST 1 reproduction --------------------------
RFC_PK=$(echo "$OUT_TXT" | grep -oE 'RFC8032_T1_PK=[0-9a-f]+' | sed 's/RFC8032_T1_PK=//' | head -1)
RFC_SIG=$(echo "$OUT_TXT" | grep -oE 'RFC8032_T1_SIG=[0-9a-f]+' | sed 's/RFC8032_T1_SIG=//' | head -1)
RFC_VERIFY=$(echo "$OUT_TXT" | grep -oE 'RFC8032_T1_VERIFY=[0-9]+' | sed 's/RFC8032_T1_VERIFY=//' | head -1)
assert_eq "$RFC_PK" "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a" \
    "RFC 8032 TEST 1: pubkey matches"
assert_eq "$RFC_SIG" "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b" \
    "RFC 8032 TEST 1: signature matches"
assert_eq "$RFC_VERIFY" "1" "RFC 8032 TEST 1: verify returns 1"

# ---- timing report + ceiling assertion ---------------------------------
SIGN_MS=$(echo "$OUT_TXT" | grep -oE 'SIGN_MS=[0-9]+' | sed 's/SIGN_MS=//' | head -1)
printf "  ${C_DIM}timing${C_RST}  ed25519_sign on 32B message: %s ms\n" "$SIGN_MS"
if [ "$SIGN_MS" -lt 30000 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  ed25519_sign latency under 30000ms ceiling (got %sms)\n" "$SIGN_MS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  ed25519_sign latency exceeded 30000ms (got %sms)\n" "$SIGN_MS"
fi

summary "scenario_iii_ed25519"
