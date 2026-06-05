#!/usr/bin/env bash
# migrate_snapshot -- one-shot v1 -> v2 (and later v2 -> v3 etc.) migration.
#
# Usage:    bash scripts/migrate_snapshot.sh OLD.snap NEW.snap
#
# Reads the snapshot at OLD.snap, applies the v1 -> v2 migration (if the
# file is at v1), and writes the migrated snapshot to NEW.snap. The
# heavy lifting lives in NOVA -- the shell wrapper just dispatches to
# `examples/migrate_snap.nova` and surfaces the report line.
#
# Output:
#   `migrated v1 -> v2 (123 -> 456 bytes)` on success
#   diagnostic line + non-zero exit on failure
#
# Exit codes:
#   0  migration succeeded (the report line carries the byte counts)
#   2  usage error / unreadable file / migration failed
#
# The NOVA toolchain location is controlled by NOVA_ROOT (default
# $HOME/NOVA), matching the rest of the build system.

set -uo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 OLD.snap NEW.snap" >&2
    exit 2
fi

OLD="$1"
NEW="$2"

if [ ! -r "$OLD" ]; then
    echo "migrate_snapshot: cannot read '$OLD'" >&2
    exit 2
fi

# Resolve to absolute paths so the NOVA helper works regardless of cwd
# (NOVA's CWD ends up wherever the toolchain compiles into; relative paths
# would resolve against that scratch dir instead of the caller's).
abspath() {
    local p="$1"
    if [ "${p#/}" != "$p" ]; then
        printf '%s' "$p"
    else
        printf '%s/%s' "$PWD" "$p"
    fi
}

OLD_ABS="$(abspath "$OLD")"
NEW_ABS="$(abspath "$NEW")"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

if [ ! -x "$NOVA" ]; then
    echo "migrate_snapshot: NOVA launcher not found at '$NOVA'; set NOVA_ROOT" >&2
    exit 2
fi

# Run the NOVA migration helper. The binary reads CE_MIGRATE_OLD /
# CE_MIGRATE_NEW from the environment (NOVA doesn't expose argc/argv to
# user programs -- env vars are how the rest of the codebase passes config,
# e.g. CE_SNAP_PATH, CE_DLOG_PATH).
NOVA_OUT="$(CE_MIGRATE_OLD="$OLD_ABS" CE_MIGRATE_NEW="$NEW_ABS" \
    "$NOVA" run "$REPO_ROOT/examples/migrate_snap.nova" 2>&1)"
RC=$?

# The first line of NOVA's stdout is the "Compiled: ..." prefix; drop it
# so the user sees only the program's own output. The migration report
# (or error message) is the last line.
echo "$NOVA_OUT" | grep -v '^Compiled:'

exit $RC
