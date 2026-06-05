# CrossEngin devcontainer

Push-button setup for GitHub Codespaces or local VS Code with the **Dev
Containers** extension.

On creation, `setup.sh` runs once and:
1. Installs `build-essential` (GNU `as`, `ld`, `make`, `gcc`) via apt.
2. Clones the [NOVA](https://github.com/amoufaq5/nova) toolchain into `~/NOVA`
   (a shallow clone) and runs `make` there (~1-2 min, builds `bin/nova`).
3. Pre-builds every CrossEngin module so the next `make test` is just tests.

After that the workflow is exactly what [`MANUAL.md`](../MANUAL.md) describes:

```sh
make test                       # run all unit suites
make install                    # build bin/crossengin, bin/crossengin-spine, bin/crossengin-selfcheck
./bin/crossengin                # the whole agent in one process
./scripts/chat.sh               # interactive chat
```

`NOVA_ROOT` is set in `devcontainer.json`'s `remoteEnv` so `make` finds the
toolchain automatically. To move the toolchain elsewhere, change both the env
var in `devcontainer.json` and the default in `setup.sh`.

## Why a devcontainer?

CrossEngin needs Linux x86-64 (NOVA emits ELF and uses raw Linux syscalls in
its runtime — see [`docs/runbook/windows.md`](../docs/runbook/windows.md) for
the why). Codespaces and Dev Containers give you a Linux environment in one
click from any host (Windows, macOS, ChromeOS), with no local install beyond
VS Code itself (or a browser, for Codespaces).
