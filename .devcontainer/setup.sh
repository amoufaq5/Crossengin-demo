#!/usr/bin/env bash
# CrossEngin devcontainer setup -- runs once on Codespace / Dev Container create.
#
# Installs build dependencies, clones + builds the NOVA toolchain into
# $NOVA_ROOT (defaulting to ~/NOVA), then pre-builds every CrossEngin module so
# the first `make test` is just running tests, not also compiling. Idempotent:
# re-running skips work that's already done.

set -euo pipefail

log() { printf '\n>>> %s\n' "$*"; }

# 1. Toolchain. The base devcontainer image ships bash + git + sudo; we add
#    build-essential (GNU as / ld / make / gcc) which is everything NOVA needs.
if ! command -v make >/dev/null 2>&1 || ! command -v as >/dev/null 2>&1; then
    log "Installing build-essential (GNU as + ld + make + gcc) ..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential
fi

# 2. NOVA. Clone shallowly, then make (~1-2 minutes the first time).
NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
# Pinned to the same NOVA commit CI uses (.github/workflows/build-and-smoke.yml
# NOVA_REF) so dev containers build reproducibly. Override with NOVA_REF=<sha>.
NOVA_REF="${NOVA_REF:-4917f10b2e224f0a036f4fc92879a51feaf0f6a6}"
if [ ! -d "$NOVA_ROOT" ]; then
    log "Cloning NOVA ($NOVA_REF) into $NOVA_ROOT ..."
    git clone https://github.com/amoufaq5/NOVA "$NOVA_ROOT"
    git -C "$NOVA_ROOT" checkout -q "$NOVA_REF"
fi
if [ ! -x "$NOVA_ROOT/bin/nova" ]; then
    log "Building the NOVA compiler ..."
    (cd "$NOVA_ROOT" && make)
fi

# 3. CrossEngin. Pre-build every module so the next `make test` is instant.
log "Pre-building CrossEngin modules ..."
NOVA_ROOT="$NOVA_ROOT" make build

log "Setup complete."
cat <<'EOF'

CrossEngin is ready. Common next steps:

  make test                       # run all unit suites (86/86 pass)
  make install                    # build the runnable artifacts into ./bin/
  ./bin/crossengin                # the whole agent in one process
  ./scripts/chat.sh               # interactive chat REPL

See MANUAL.md for the full walkthrough; NEXT_SESSION.md for project status.

EOF
