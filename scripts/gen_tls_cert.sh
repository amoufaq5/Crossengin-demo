#!/usr/bin/env bash
#
# scripts/gen_tls_cert.sh -- Generate a self-signed TLS certificate for
# a CrossEngin TLS sidecar (R54.1, ADR-0105 §Transport TLS).
#
# For LOCAL / SMALL-TEAM deployments where you want the wire encrypted
# but don't need a public-CA-signed certificate. Clients will need to
# either trust the generated cert explicitly (`--cacert <path>` for curl,
# `NODE_EXTRA_CA_CERTS=<path>` for Node, etc.) OR skip verification
# (only OK when you know the endpoint out-of-band).
#
# For PUBLIC / MULTI-USER deployments use Let's Encrypt (certbot) or a
# real CA + intermediate; this script is scaffolding, not a policy.
#
# Usage:
#   scripts/gen_tls_cert.sh [--dir DIR] [--host HOST] [--days N]
#
# Defaults:
#   --dir   ~/.crossengin/tls
#   --host  127.0.0.1 (bound to the SAN of the cert)
#   --days  365
#
# Writes:
#   $DIR/server.key   ed25519 or RSA private key (mode 0600)
#   $DIR/server.pem   PEM certificate (mode 0644)
#   $DIR/server-and-key.pem   concatenated (stunnel wants this shape)
#
# Requires openssl (1.1.1+ recommended; ed25519 needs 1.1.1+).

set -uo pipefail

DIR="${HOME}/.crossengin/tls"
HOST="127.0.0.1"
DAYS=365

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)  DIR="$2";  shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --days) DAYS="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,29p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl not on PATH. Install with your OS's package manager." >&2
    exit 1
fi

mkdir -p "$DIR"
chmod 700 "$DIR"

KEY="$DIR/server.key"
CERT="$DIR/server.pem"
BUNDLE="$DIR/server-and-key.pem"

# Prefer ed25519 (small, fast); fall back to RSA-2048 if openssl is too
# old. Every stunnel + nginx + curl since ~2020 handles both.
if openssl genpkey -algorithm ed25519 -out "$KEY" 2>/dev/null; then
    ALG="ed25519"
else
    openssl genrsa -out "$KEY" 2048 2>/dev/null || {
        echo "ERROR: openssl couldn't mint any key type." >&2
        exit 1
    }
    ALG="rsa-2048"
fi
chmod 600 "$KEY"

# Build a config file with a real SAN (subjectAltName). Modern clients
# refuse certs whose CN-only value doesn't have a matching SAN.
CONF=$(mktemp)
trap 'rm -f "$CONF"' EXIT

# If HOST looks like a dotted-quad, emit an IP: SAN entry; else a DNS:.
if printf '%s' "$HOST" | grep -qE '^[0-9]+(\.[0-9]+){3}$'; then
    SAN="IP:$HOST"
else
    SAN="DNS:$HOST"
fi

cat > "$CONF" <<EOF
[req]
distinguished_name = dn
prompt             = no
req_extensions     = v3_req
x509_extensions    = v3_req

[dn]
CN = crossengin-tls-sidecar

[v3_req]
subjectAltName     = $SAN, IP:127.0.0.1
keyUsage           = critical, digitalSignature, keyEncipherment
extendedKeyUsage   = serverAuth
basicConstraints   = critical, CA:FALSE
EOF

openssl req -new -x509 -key "$KEY" -out "$CERT" \
    -days "$DAYS" -config "$CONF" -extensions v3_req \
    >/dev/null 2>&1 || {
    echo "ERROR: openssl x509 mint failed." >&2
    exit 1
}
chmod 644 "$CERT"

# stunnel wants a single file with cert + key together.
cat "$CERT" "$KEY" > "$BUNDLE"
chmod 600 "$BUNDLE"

# Print a fingerprint clients can pin (SHA-256). Older openssl prints
# "SHA256 Fingerprint="; newer prints "sha256 Fingerprint=" -- match
# either.
FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 \
    | sed -E 's/^[Ss][Hh][Aa]256 Fingerprint=//')

cat <<EOF
=== CrossEngin TLS cert generated ($ALG, $DAYS days) ===
directory:  $DIR
key:        $KEY        (mode 0600)
cert:       $CERT       (mode 0644)
bundle:     $BUNDLE     (mode 0600, cert+key concatenated -- stunnel)
host:       $HOST       (SAN: $SAN + IP:127.0.0.1)
sha256:     $FP

Next steps:
  1. Configure your sidecar. Reference confs are in:
       infra/tls/stunnel.rpc.conf.example
       infra/tls/nginx.rpc.conf.example
  2. Start the daemon on loopback with capability enforcement:
       CE_RPC_REQUIRE_TOKEN=1 \\
       CE_RPC_ADMIN_TOKEN_FILE=~/.crossengin/admin.token \\
       scripts/rpc_daemon.sh
  3. Start the sidecar (stunnel points at $BUNDLE).
  4. Client connects to https://$HOST:9977 with:
       curl --cacert $CERT https://$HOST:9977/...
     or pins the SHA-256 fingerprint above.

For public deployments use certbot (Let's Encrypt) or a real CA
instead -- this script generates a SELF-SIGNED cert; clients that
don't trust it explicitly will refuse the connection.
EOF
