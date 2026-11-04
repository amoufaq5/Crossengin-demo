#!/usr/bin/env bash
#
# scripts/snap_keygen.sh — generate an Ed25519 keypair for snapshot
# signing in the two file-raw-bytes shape merkle_signing.nova expects.
#
# Phase 1 pt2 wires verify-on-load:
#   /load calls snap_verify_signature(s) when CE_SNAPSHOT_VERIFY_PUBKEY
#   is set, refusing on tampered / missing signatures.
#
# To exercise the path, an operator needs a matched (priv, pub) pair.
# NOVA has src/safety/ed25519.nova's ed25519_keygen but that lives
# inside the chat binary. A shell helper is more ergonomic for ad-hoc
# testing: we lean on openssl's Ed25519 keygen + DER parsing to pull
# out the raw 32-byte seed and public key.
#
# Usage:
#   scripts/snap_keygen.sh <basepath>
#     Writes <basepath>.priv (32 raw bytes, chmod 600)
#     Writes <basepath>.pub  (32 raw bytes)
#
# Env paired with the snapshot flow:
#   CE_SNAPSHOT_SIGN_KEY=<basepath>.priv     set on /save to sign.
#   CE_SNAPSHOT_VERIFY_PUBKEY=<basepath>.pub set on /load to verify.
#   CE_SNAPSHOT_REQUIRE_SIGNATURE=1          strict mode.

set -uo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <basepath>" >&2
    exit 2
fi
BASE="$1"

if ! command -v openssl >/dev/null 2>&1; then
    echo "error: openssl not on PATH" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Generate an Ed25519 keypair in PEM.
openssl genpkey -algorithm Ed25519 -out "$TMP/key.pem"

# 2. Convert to DER.
openssl pkey -in "$TMP/key.pem" -outform DER -out "$TMP/key.der"
openssl pkey -in "$TMP/key.pem" -pubout -outform DER -out "$TMP/pub.der"

# 3. Extract the raw 32-byte seed. Ed25519 PKCS#8 DER ends with the
#    seed as the last 32 bytes of an OCTET STRING payload. In
#    practice this means the raw seed is the final 32 bytes of the
#    file — DER's trailing octets are the seed.
tail -c 32 "$TMP/key.der" > "$BASE.priv"
chmod 600 "$BASE.priv"

# 4. Extract the raw 32-byte public key (same positional logic;
#    SubjectPublicKeyInfo ends with the key's BIT STRING contents
#    which for Ed25519 is exactly 32 bytes).
tail -c 32 "$TMP/pub.der" > "$BASE.pub"
chmod 644 "$BASE.pub"

echo "wrote $BASE.priv (32 bytes, 0600)"
echo "wrote $BASE.pub  (32 bytes, 0644)"
echo
echo "To use:"
echo "  export CE_SNAPSHOT_SIGN_KEY=$BASE.priv       # sign on /save"
echo "  export CE_SNAPSHOT_VERIFY_PUBKEY=$BASE.pub   # verify on /load"
