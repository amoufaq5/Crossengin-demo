# Getting Started with CrossEngin

This guide walks new users from "I just cloned the repo" to "I can run
the REPL and the test suite," across three host platforms (Linux, Windows,
macOS) and explains the Vercel deployment pattern.

CrossEngin is a NOVA application that compiles to a single Linux x86_64
ELF binary. Where you can run a Linux ELF, you can run CrossEngin.
Where you can't (Vercel Edge Runtime, browser, native macOS Apple
Silicon), you wrap it.

## Section 1 -- Requirements at a glance

| Host                  | Status             | Notes                                            |
|-----------------------|--------------------|--------------------------------------------------|
| Linux x86_64 (native) | **Recommended**    | First-class. Run `bash scripts/bootstrap.sh`.    |
| Windows               | Supported via WSL2 | CrossEngin emits Linux ELF; you run it in WSL2.  |
| macOS Intel           | Supported via Docker | Run inside `ubuntu:24.04` container.           |
| macOS Apple Silicon   | Supported, performance-penalised | Docker + x86_64 emulation. Slower; see below. |
| Vercel                | **Not directly compatible** | Hybrid pattern: Vercel function proxies HTTPS to a Linux box running CrossEngin. |

Required tools (all platforms):
  - `gcc`, `make`, `gdb`, `objdump`, `git`.
  - A NOVA compiler checkout at a path you'll export as `$NOVA_ROOT`.
  - Optional: `whisper.cpp` for the voice STT path
    (`src/io/transducers/whisper_backend.nova`).

## Section 2 -- Install on Linux native

This is the first-class path; everything else is a wrapper around it.

### 2.1 Install system packages

On Ubuntu 22.04 / 24.04 or Debian:

```bash
sudo apt-get update
sudo apt-get install -y build-essential gcc make gdb binutils git
```

On Fedora / RHEL:

```bash
sudo dnf install -y gcc make gdb binutils git
```

### 2.2 Clone both repos side-by-side

CrossEngin consumes the NOVA toolchain from a sibling directory.

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/amoufaq5/NOVA.git
git clone https://github.com/amoufaq5/Crossengin-demo.git
```

### 2.3 Build the NOVA compiler

```bash
cd ~/src/NOVA
make           # builds stage1 -> stage2 -> stage3
make self-host # verifies stage2.s == stage3.s (bit-identical)
```

If `make self-host` fails, stop here -- a NOVA compiler regression must
be fixed before CrossEngin will build. File an issue against the NOVA
repo.

### 2.4 Point CrossEngin at NOVA

```bash
export NOVA_ROOT=$HOME/src/NOVA
# Add to ~/.bashrc or ~/.zshrc for persistence:
echo 'export NOVA_ROOT=$HOME/src/NOVA' >> ~/.bashrc
```

### 2.5 Bootstrap CrossEngin

```bash
cd ~/src/Crossengin-demo
bash scripts/bootstrap.sh
```

`bootstrap.sh` verifies your environment: NOVA at `$NOVA_ROOT`,
required system tools on PATH, optional STT backend availability.
If anything is missing, it prints a specific remedy.

### 2.6 Run the test suite

```bash
bash scripts/test.sh
```

You should see all 50+ test modules pass. A failure here means either
a NOVA regression (re-check `make self-host` in `$NOVA_ROOT`) or a
local environment issue.

### 2.7 Run the chat REPL

```bash
bash scripts/chat.sh
```

You're at the CrossEngin prompt. Type something. Exit with `:quit`.

After bootstrap, see [`docs/CHAT_USAGE.md`](./CHAT_USAGE.md) for the
comprehensive feature walkthrough -- admin commands, self-identification,
self-directed learning, persistence, troubleshooting. That is the document
to read next.

### 2.8 Optional -- voice STT

To enable the voice transducer (`src/io/transducers/whisper_backend.nova`):

```bash
cd /tmp && git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp && make
bash models/download-ggml-model.sh base.en
export WHISPER_CPP_ROOT=/tmp/whisper.cpp
```

Then `bash scripts/transcribe.sh path/to/audio.wav`.

## Section 3 -- Install on Windows (WSL2)

CrossEngin emits Linux ELF binaries. Windows native PE32+ is not a
runtime target. You run CrossEngin inside Windows Subsystem for Linux
(WSL2), which is a real Linux kernel + filesystem.

### 3.1 Install WSL2

From an **Administrator** PowerShell:

```powershell
wsl --install -d Ubuntu
```

This installs WSL2 with Ubuntu as the default distro. Reboot when
prompted. Ubuntu launches on first run; create your Linux user.

If WSL2 is already installed and you want a fresh Ubuntu:

```powershell
wsl --list --online
wsl --install -d Ubuntu-24.04
```

### 3.2 Inside WSL2 -- follow the Linux native steps

Open the Ubuntu app from the Start menu. You're now in a Linux shell.

```bash
# In the WSL2 shell:
sudo apt-get update && sudo apt-get install -y build-essential gdb git
mkdir -p ~/src && cd ~/src
git clone https://github.com/amoufaq5/NOVA.git
git clone https://github.com/amoufaq5/Crossengin-demo.git
cd NOVA && make && make self-host
export NOVA_ROOT=$HOME/src/NOVA
cd ~/src/Crossengin-demo
bash scripts/bootstrap.sh
bash scripts/test.sh
```

### 3.3 VS Code with WSL2

Install VS Code on Windows. Install the **Remote - WSL** extension
(`ms-vscode-remote.remote-wsl`). Then from your Ubuntu shell:

```bash
cd ~/src/Crossengin-demo
code .
```

VS Code opens with the repo, with the WSL2 backend doing all the work.
Terminal panels run inside Ubuntu; the editor runs on Windows.

For NOVA LSP / DAP wiring inside VS Code, see the NOVA repo's
`docs/IDE_SETUP.md`.

### 3.4 Honest notes

  - **Filesystem performance.** Keep your CrossEngin / NOVA checkouts
    inside the WSL2 filesystem (`~/src/...`), not on a Windows-mounted
    path (`/mnt/c/...`). Cross-filesystem builds are ~10x slower.
  - **Antivirus / Defender.** Some Windows AV scanners can throttle
    WSL2 disk I/O. Excluding `\\wsl$\Ubuntu\home\...` from real-time
    scanning helps if you see slow builds.

## Section 4 -- Install on macOS

CrossEngin does not target macOS natively. You run it inside a Linux
container or VM.

### 4.1 macOS (Intel) -- Docker Desktop

```bash
# Install Docker Desktop from https://www.docker.com/products/docker-desktop
# Then in Terminal:
cd ~/src && mkdir -p crossengin-work && cd crossengin-work
docker run -it -v "$PWD:/work" ubuntu:24.04 bash
# Inside the container, follow the Section 2 Linux native steps:
apt-get update && apt-get install -y build-essential gdb git
cd /work
git clone https://github.com/amoufaq5/NOVA.git
git clone https://github.com/amoufaq5/Crossengin-demo.git
cd NOVA && make && make self-host
export NOVA_ROOT=/work/NOVA
cd /work/Crossengin-demo && bash scripts/bootstrap.sh && bash scripts/test.sh
```

### 4.2 macOS (Apple Silicon, M1/M2/M3/M4)

CrossEngin is Linux x86_64 ELF. On Apple Silicon you must run an
x86_64 Linux container under emulation. Docker Desktop ships with
Rosetta 2 / QEMU support.

```bash
# Ensure Rosetta 2 is installed:
softwareupdate --install-rosetta --agree-to-license

# Enable "Use Rosetta for x86_64/amd64 emulation" in
# Docker Desktop -> Settings -> General.

# Pull an explicit amd64 image and run:
docker run --platform linux/amd64 -it -v "$PWD:/work" ubuntu:24.04 bash
```

Inside the container, follow Section 2.

**Honest note on Apple Silicon emulation cost.** Running x86_64
under emulation has a real performance penalty -- expect builds to
be 3-5x slower than on a native Intel Mac, and test runs to be 2-3x
slower. Acceptable for development; not appropriate for benchmarking.

**Alternative**: a full Linux VM via UTM (free) or Parallels (paid)
running Ubuntu 24.04 x86_64 emulated. Heavier setup, but ergonomics
are closer to a real Linux laptop once configured.

## Section 5 -- Vercel deployment pattern (hybrid)

**Vercel is not a direct deployment target for CrossEngin.** Vercel
runs Node.js / Edge Runtime; CrossEngin runs as a Linux ELF process
with raw socket access, mmap'd persistence, and a ~100Hz substrate
tick. None of these are available on Vercel functions.

The supported pattern is **Vercel-hosted frontend + Linux-hosted
CrossEngin behind HTTPS**:

```
[ Browser ] --HTTPS--> [ Vercel Edge Function /api/chat ]
                              |
                              | HTTPS proxy (server-to-server)
                              v
                       [ Linux VM running CrossEngin ]
                       e.g. Fly.io, Render, Hetzner, AWS, GCP
```

### 5.1 Sketch -- Vercel side

```typescript
// app/api/chat/route.ts (Next.js App Router)
export async function POST(req: Request) {
  const { message } = await req.json();
  const upstream = await fetch(process.env.CROSSENGIN_ENDPOINT + "/chat", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${process.env.CROSSENGIN_TOKEN}`,
    },
    body: JSON.stringify({ message }),
  });
  return new Response(upstream.body, { status: upstream.status });
}
```

Configure `CROSSENGIN_ENDPOINT` and `CROSSENGIN_TOKEN` in Vercel's
environment variables.

### 5.2 Sketch -- Linux side

  - Run CrossEngin behind an HTTPS reverse proxy (Caddy, nginx, Traefik).
  - The CrossEngin process listens on a localhost socket; the proxy
    handles TLS termination + bearer-token validation.
  - Persistence (`src/persistence/`) lives on the VM's local disk;
    back up to S3-compatible storage on a schedule.

### 5.3 Reference architecture -- `infra/vercel-proxy/`

R37F ships the complete scaffold under [`infra/vercel-proxy/`](../infra/vercel-proxy/):

```
infra/vercel-proxy/
  web/                     # Next.js 14 App Router project (deploys to Vercel)
    app/page.tsx           # streamed chat UI
    app/api/chat/route.ts  # POST handler; forwards to backend with Bearer token
    vercel.json            # function runtime + maxDuration pin
    .env.example           # CROSSENGIN_URL / CROSSENGIN_TOKEN reference
    README.md              # deploy steps for Vercel
  backend/                 # Python HTTP wrapper + Docker image
    server.py              # listens :8080, validates bearer, spawns bin/crossengin-chat
    Dockerfile             # ubuntu:24.04, builds NOVA + CrossEngin from source
    docker-compose.yml     # one-command local dev (./data:/data persistence)
    entrypoint.sh          # refuses to start without a real token
    README.md              # deploy recipes (Fly.io / Hetzner / Render)
  ARCHITECTURE.md          # end-to-end diagram + latency + cost model
  SECURITY.md              # threat model (token leakage, DoS, exposure, escape)
  tests/
    test_backend_health.py # /health 200 + /chat 401 smoke test
    test_chat_route.ts     # mocks fetch; validates request-shape pass-through
```

Quick-start (local dev, both halves on one laptop):

```bash
# Backend in one terminal:
cd infra/vercel-proxy/backend
docker-compose up --build     # http://localhost:8080 + ./data volume

# Frontend in another:
cd infra/vercel-proxy/web
cp .env.example .env.local
# edit .env.local: CROSSENGIN_URL=http://localhost:8080
#                  CROSSENGIN_TOKEN=local-dev-token
pnpm install
pnpm dev                      # http://localhost:3000
```

Production deploy (Vercel + a Linux backend):

```bash
# Provision the backend (Fly.io / Hetzner / Render -- see backend/README.md).
# Configure CROSSENGIN_TOKEN there; grab the public hostname.

cd infra/vercel-proxy/web
vercel link
vercel env add CROSSENGIN_URL production    # https://your-backend.example
vercel env add CROSSENGIN_TOKEN production  # paste the same value
vercel deploy --prod
```

Configuration env vars:

| Variable           | Side    | Default                | Purpose                                    |
|--------------------|---------|------------------------|--------------------------------------------|
| `CROSSENGIN_URL`   | Vercel  | (required)             | Backend base URL (HTTPS in prod).          |
| `CROSSENGIN_TOKEN` | both    | (required)             | Shared bearer; `openssl rand -hex 32`.     |
| `CE_BIN`           | backend | `bin/crossengin-chat`  | Binary to spawn (one-shot fallback set to `bin/crossengin`). |
| `CE_PORT`          | backend | `8080`                 | Listen port.                               |
| `CE_BIND`          | backend | `0.0.0.0`              | Listen interface (set `127.0.0.1` behind a reverse proxy). |
| `CE_MAX_SESSIONS`  | backend | `8`                    | LRU cap for per-session chat children.     |
| `CE_REQUEST_TIMEOUT_S` | backend | `30.0`             | Per-turn read timeout.                     |

For the end-to-end flow diagram, latency / cost models, and the
authentication-upgrade path (JWT + key rotation), see
[`infra/vercel-proxy/ARCHITECTURE.md`](../infra/vercel-proxy/ARCHITECTURE.md).
For threats + mitigations (token leakage, DoS, backend exposure,
container escape), see
[`infra/vercel-proxy/SECURITY.md`](../infra/vercel-proxy/SECURITY.md).

### 5.4 Honest notes on the hybrid pattern

  - **Cold starts.** Vercel functions have warm-start latencies of
    tens of milliseconds; CrossEngin on a small VM has request
    latencies dominated by the substrate tick (100Hz = 10ms minimum).
    Plan UX accordingly.
  - **No edge-locality.** CrossEngin runs on one Linux box; Vercel's
    edge points-of-presence will all hit that one box. Acceptable
    for personal companion use; not appropriate for global scale.
  - **CrossEngin v1 is single-user.** Multi-tenant deployment is a v2
    concern; the hybrid pattern is for the single-user case where
    Vercel is the convenience surface for a personal Linux companion.

## Section 6 -- Verifying your setup

After following Section 2 / 3 / 4 for your platform:

```bash
cd <wherever you cloned Crossengin-demo>

# Environment sanity check
bash scripts/crossengin-doctor.sh

# Full test suite (50+ modules; ~minutes)
bash scripts/test.sh

# Smoke test -- run an example
ls examples/                # see what's available
bash scripts/run.sh examples/<example_name>.nova
```

If `bash scripts/test.sh` reports "all green," you're in business.
Next step: read `docs/CONTRIBUTING.md` to learn the round-based
development model.

## Section 7 -- Where to go next

  - `docs/CONTRIBUTING.md` -- how rounds work, file-ownership
    discipline, stash protocol.
  - `docs/adr/` -- architecture decisions (start with
    `r36f-0004-substrate-not-pipeline.md` for the macro shape).
  - `ARCHITECTURE.md` -- system-level overview.
  - `MANUAL.md` -- end-user manual.
  - `NEXT_SESSION.md` -- what shipped in the latest rounds, what's
    next.
  - `FEDERATED_AUDIT.md` -- federation transport audit (huge file;
    skim for context).
  - NOVA repo `docs/LANGUAGE_REFERENCE.md` -- learn NOVA itself.
