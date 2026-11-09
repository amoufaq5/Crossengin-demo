#!/usr/bin/env bash
#
# scripts/bake_sample.sh — generate a committable sample agent bundle
# (Phase 5 pt3 lite).
#
# Phase 5 pt1 shipped /agent verify. To exercise its success path
# against committed content, the repo needs a signed bundle + the
# matching pubkey. This script produces both:
#
#   docs/samples/sample_agent.bundle  — signed bundle (text)
#   docs/samples/sample_agent.pub     — 32 raw bytes of the mother's
#                                       Ed25519 public key
#
# Verification:
#   CE_AGENT_VERIFY_PUBKEY_HEX="$(hexdump -ve '1/1 "%02x"' \
#       docs/samples/sample_agent.pub)" \
#     ./bin/crossengin-chat <<< "/agent verify docs/samples/sample_agent.bundle"
#
# Signature algorithm is standard Ed25519 over the bundle prefix
# (everything up to the newline before `#SIGNATURE`), matching
# src/factory/bake.nova:bake_verify_bundle's behaviour and
# src/persistence/bundle_signing.nova:bundle_pkg_verify.
#
# This script is idempotent: re-running regenerates the keypair and
# the bundle, so the committed artifacts rotate on demand.

set -uo pipefail

if ! command -v openssl >/dev/null 2>&1; then
    echo "error: openssl not on PATH" >&2
    exit 1
fi

OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/docs/samples"
mkdir -p "$OUT_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Generate an Ed25519 keypair (same openssl path as snap_keygen).
openssl genpkey -algorithm Ed25519 -out "$TMP/key.pem"

# 2. Extract the raw 32-byte public key.
openssl pkey -in "$TMP/key.pem" -pubout -outform DER -out "$TMP/pub.der"
tail -c 32 "$TMP/pub.der" > "$OUT_DIR/sample_agent.pub"
chmod 644 "$OUT_DIR/sample_agent.pub"

# 3. Write the bundle prefix with realistic header + section content.
#    The prefix is everything that gets signed; the #SIGNATURE +
#    #SIGNER-PK lines are appended AFTER signing.
cat > "$TMP/prefix.txt" <<'EOF'
#CROSSENGIN-CHILD-BUNDLE v1
#name sample-clinical-rx
#version 0.1.0
#domain clinical
#baked-at 1762800000
#mother-fingerprint sampleagentfingerprint0000000000000000000000000000000000000000000000
#PERSONA v1
alice calm empathic
bob clinical precise
#OWNERSHIP v1
operator@example.com
#POLICY v1
default_tier require_approval
read_tier allow
#PATTERN v1
#SKILL v1
clinical_lookup
drug_reference
#AGENT v1
sample-clinical-rx DESC=minimal-clinical-reference STYLE_PIN=calm LICENSE=CC-BY
#KG v1
atom1 fever
atom2 infection
atom3 symptom
EOF

# 4. CrossEngin's bundle_pkg_sign hashes the bundle bytes with SHA-256
#    first and signs the 32-byte digest with Ed25519 (see
#    src/persistence/bundle_signing.nova:66). Ed25519-PureEdDSA signs
#    the 32-byte digest AS the message. Replicate that path with
#    openssl: sha256 the prefix, then pkeyutl -sign -rawin on the
#    binary digest.
openssl dgst -sha256 -binary "$TMP/prefix.txt" > "$TMP/digest.bin"
openssl pkeyutl -sign -inkey "$TMP/key.pem" -rawin \
    -in "$TMP/digest.bin" \
    -out "$TMP/sig.bin"
SIG_HEX="$(od -An -vtx1 "$TMP/sig.bin" | tr -d ' \n')"

# 5. Public key as hex for the #SIGNER-PK trailer.
PK_HEX="$(od -An -vtx1 "$OUT_DIR/sample_agent.pub" | tr -d ' \n')"

# 6. Concatenate prefix + trailer.
cp "$TMP/prefix.txt" "$OUT_DIR/sample_agent.bundle"
{
    printf '#SIGNATURE %s\n' "$SIG_HEX"
    printf '#SIGNER-PK %s\n' "$PK_HEX"
} >> "$OUT_DIR/sample_agent.bundle"
chmod 644 "$OUT_DIR/sample_agent.bundle"

echo "wrote $OUT_DIR/sample_agent.bundle"
echo "wrote $OUT_DIR/sample_agent.pub"
echo
echo "sig_hex=$SIG_HEX"
echo "pk_hex=$PK_HEX"
echo
echo "Verify from the chat:"
echo "  export CE_AGENT_VERIFY_PUBKEY_HEX=\$(od -An -vtx1 $OUT_DIR/sample_agent.pub | tr -d ' \\n')"
echo "  ./bin/crossengin-chat <<< \"/agent verify $OUT_DIR/sample_agent.bundle\""
