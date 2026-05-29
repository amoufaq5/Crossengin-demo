# Running CrossEngin on Windows

CrossEngin itself is OS-agnostic source, but the NOVA toolchain it compiles
with emits Linux x86-64 binaries (ELF) and uses raw Linux syscalls in its
runtime (see [`troubleshooting.md`](./troubleshooting.md) and `/home/user/NOVA/
src/runtime/syscall.nova`). A native Windows port would require a Win32
runtime layer that doesn't exist yet. So on Windows you run the **same Linux
build** inside one of two thin wrappers:

- **WSL2** — recommended; a real Linux kernel under Windows. Near-native speed.
- **Docker Desktop** — fallback if WSL2 is unavailable.

Both give you a working `bin/crossengin` in a few commands. Pick one.

---

## Option A — WSL2 (recommended)

Works on Windows 10 build 2004+ or any Windows 11. Needs admin rights for the
first-time install of WSL itself; after that, day-to-day use needs no admin.

### 1. Install WSL2 + Ubuntu

Open PowerShell **as Administrator** and run:

```powershell
wsl --install
```

That installs WSL2, sets it as the default WSL version, and pulls Ubuntu (the
default distro). Reboot when prompted. On the first launch of Ubuntu, you'll
be asked for a UNIX username and password — these are local to the WSL distro
and have nothing to do with your Windows account.

If `wsl --install` is unavailable (older Windows 10), do it manually:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
# Reboot, then:
wsl --set-default-version 2
# Then install Ubuntu from the Microsoft Store.
```

### 2. Install the build dependencies (inside WSL)

Open the Ubuntu shell (Start menu → "Ubuntu") and run:

```bash
sudo apt update
sudo apt install -y build-essential git
```

`build-essential` gives you `gcc`, `make`, GNU `as`, and GNU `ld` — the only
toolchain CrossEngin needs.

### 3. Clone and build NOVA

```bash
git clone https://github.com/amoufaq5/nova "$HOME/NOVA"
cd "$HOME/NOVA" && make
```

This produces `$HOME/NOVA/bin/nova` (the self-hosting compiler) and the
launcher script `$HOME/NOVA/nova`.

### 4. Clone and run CrossEngin

```bash
cd ~
git clone https://github.com/amoufaq5/Crossengin-demo
cd Crossengin-demo

make build                          # compile every module
make test                           # run all 87 unit suites
make install                        # build the three runnable artifacts

./bin/crossengin                    # the whole agent in one process
./bin/crossengin-selfcheck          # substrate kernel spine
./bin/crossengin-spine              # safety + IO + persistence spine
```

You should see `crossengin: OK` from the daemon. From here, the rest of
[`MANUAL.md`](../../MANUAL.md) applies unchanged.

### Optional polish (recommended for development)

- **VS Code** with the **"WSL"** extension lets you open the WSL filesystem
  directly: from the Ubuntu shell inside your repo, run `code .`. Edits land in
  the WSL filesystem (where they should — see the next bullet).
- **Keep source under WSL**, not under `/mnt/c/`. Cross-filesystem I/O between
  WSL and Windows-mounted `/mnt/c/` is significantly slower; `make build` on a
  Windows-mounted path can take minutes instead of seconds.
- **Access from Windows** (rare, e.g. to drop a file in): your WSL home is at
  `\\wsl$\Ubuntu\home\<user>\` in Explorer.

---

## Option B — Docker Desktop

If WSL2 is unavailable in your environment (some corporate policies disable
it), Docker Desktop on Windows runs Linux containers fine. The same Linux
commands apply inside any reasonable Linux image.

### 1. Install Docker Desktop

Download from <https://www.docker.com/products/docker-desktop> and enable the
Linux containers mode (the default).

### 2. Run an interactive Linux container

From PowerShell or cmd:

```powershell
docker run -it --rm -v ${PWD}:/work -w /work ubuntu:24.04 bash
```

That mounts your current Windows directory at `/work` inside the container.

### 3. Build and run (inside the container)

```bash
apt update && apt install -y build-essential git
git clone https://github.com/amoufaq5/nova /opt/NOVA
cd /opt/NOVA && make
export NOVA_ROOT=/opt/NOVA

git clone https://github.com/amoufaq5/Crossengin-demo
cd Crossengin-demo
make build && make test && make install
./bin/crossengin
```

Same `crossengin: OK` exits the container. (The container is ephemeral, so
commit a Dockerfile if you want it reproducible.)

---

## What does NOT work on Windows today

- **Running `bin/nova` or `bin/crossengin*` natively on Windows.** They are
  ELF Linux binaries with hand-written Linux syscalls in their runtime; they
  cannot load on Windows.
- **`make cross-windows` in the NOVA repo.** It cross-compiles a `nova.exe`
  via MinGW, but the resulting compiler's runtime still issues raw Linux
  `syscall` instructions. It will not work end-to-end without a real Win32
  runtime port (which is a NOVA enhancement, not a CrossEngin one).

Stick with WSL2 or Docker until that lands.

---

## Troubleshooting Windows-specific

- **`wsl --install` says "WSL 2 requires an update to its kernel component"** —
  follow the link Windows prints; download and run the WSL2 kernel update from
  Microsoft, then `wsl --set-default-version 2` and re-launch Ubuntu.
- **`make: command not found`** — you skipped `apt install build-essential`
  inside the WSL distro. WSL's Ubuntu starts minimal; install it explicitly.
- **`/home/user/NOVA/nova: not found`** — `$HOME` in WSL is `/home/<your_unix_user>`,
  not necessarily `/home/user/`. Use `"$HOME/NOVA"` literally, as in the guide,
  or pass an explicit `NOVA_ROOT=` to `make`.
- **Build is extremely slow** — your source is probably on `/mnt/c/...`
  (Windows-mounted). Move it under your WSL home (`~`), which lives on the WSL
  filesystem. 10-100x speedup is normal.
- **Permissions complaints when running `./bin/...` from PowerShell** — you're
  trying to launch a Linux binary from Windows. Launch it from inside WSL
  (`wsl ./bin/crossengin`) or from your Ubuntu shell directly.

See the general [`troubleshooting.md`](./troubleshooting.md) for non-platform
issues (NOVA's 16-key `map` cap, segfaults from undefined functions, etc.).
