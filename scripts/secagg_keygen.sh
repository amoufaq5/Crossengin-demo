#!/usr/bin/env bash
# CrossEngin: make a SecAgg v4 soul identity key (A2.1).
#
# Usage: scripts/secagg_keygen.sh <basepath> <soul-id> <soul-name>
#
# Writes an Ed25519 key in snapshot-key format:
#   <basepath>.priv   32-byte raw seed, mode 0600  -> CE_SECAGG_ID_KEY
#   <basepath>.pub    32-byte raw public key, mode 0644
# and prints the roster line for this soul plus a fingerprint to compare out
# of band. The roster file (CE_SECAGG_ROSTER) starts with the line
#   crossengin-secagg-roster v1
# followed by one printed roster line per soul, ids ascending
# (src/learning/sa_roster.nova).
#
# Safety: umask 077; refuses to overwrite or follow an existing file or
# symlink at either path; writes with noclobber; checks the DER layout that
# openssl produced before extracting the raw bytes.
#
# Exit: 0 ok, 1 failure, 2 bad usage.
set -uo pipefail
umask 077

usage() { echo "usage: $0 <basepath> <soul-id 0..4294967295> <soul-name [A-Za-z0-9_-]{1,64}>" >&2; exit 2; }
[ "$#" -eq 3 ] || usage
BASE="$1"; ID="$2"; NAME="$3"
[ -n "$BASE" ] || usage

case "$ID" in ''|*[!0-9]*) echo "error: soul id must be a decimal number" >&2; exit 2;; esac
if [ "${#ID}" -gt 1 ] && [ "${ID:0:1}" = "0" ]; then echo "error: soul id must not have leading zeros" >&2; exit 2; fi
if [ "${#ID}" -gt 10 ] || [ "$ID" -gt 4294967295 ]; then echo "error: soul id must be at most 4294967295" >&2; exit 2; fi
case "$NAME" in ''|*[!A-Za-z0-9_-]*) echo "error: soul name must be 1-64 of A-Z a-z 0-9 _ -" >&2; exit 2;; esac
[ "${#NAME}" -le 64 ] || { echo "error: soul name must be at most 64 characters" >&2; exit 2; }

for f in "$BASE.priv" "$BASE.pub"; do
  if [ -e "$f" ] || [ -L "$f" ]; then echo "error: $f already exists; refusing to overwrite" >&2; exit 1; fi
done

command -v openssl >/dev/null 2>&1 || { echo "error: openssl is not on PATH" >&2; exit 1; }
TMP="$(mktemp -d)" || { echo "error: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

openssl genpkey -algorithm ed25519 -outform DER -out "$TMP/k.der" 2>/dev/null \
  || { echo "error: openssl cannot generate Ed25519 keys" >&2; exit 1; }
openssl pkey -inform DER -in "$TMP/k.der" -pubout -outform DER -out "$TMP/p.der" 2>/dev/null \
  || { echo "error: openssl could not derive the public key" >&2; exit 1; }

hex() { od -An -vtx1 "$1" | tr -d ' \n'; }
KH="$(hex "$TMP/k.der")"; PH="$(hex "$TMP/p.der")"
# PKCS#8 Ed25519 = 16-byte prefix + 32-byte seed; SPKI = 12-byte prefix + 32-byte key.
if [ "${#KH}" -ne 96 ] || [ "${KH:0:32}" != "302e020100300506032b657004220420" ]; then
  echo "error: unexpected private key encoding from openssl" >&2; exit 1
fi
if [ "${#PH}" -ne 88 ] || [ "${PH:0:24}" != "302a300506032b6570032100" ]; then
  echo "error: unexpected public key encoding from openssl" >&2; exit 1
fi

set -C   # noclobber: '>' fails if the file (or a symlink) appeared meanwhile
if ! tail -c 32 "$TMP/k.der" > "$BASE.priv"; then
  echo "error: cannot create $BASE.priv" >&2; exit 1
fi
if ! tail -c 32 "$TMP/p.der" > "$BASE.pub"; then
  echo "error: cannot create $BASE.pub" >&2; rm -f "$BASE.priv"; exit 1
fi
chmod 600 "$BASE.priv"
chmod 644 "$BASE.pub"

PK="${PH:24}"
FP="$(sha256sum "$BASE.pub" | cut -c1-64)"
echo "private key: $BASE.priv  (export CE_SECAGG_ID_KEY=$BASE.priv)"
echo "public key:  $BASE.pub"
echo "roster line: $ID $NAME $PK"
echo "key fingerprint (sha256 of the public key): $FP"
