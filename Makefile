# CrossEngin build system.
#
# CrossEngin is written in NOVA and compiled with the NOVA self-hosting
# toolchain in a sibling checkout. Override the toolchain location with:
#     make NOVA_ROOT=/path/to/NOVA <target>
#
# Targets:
#   build      compile every implemented NOVA module under src/ (no .pending)
#   test       compile and run every unit test under tests/unit/
#   benchmark  run every benchmark under tests/benchmark/ and report metrics
#   install    build the substrate self-check binary into ./bin/
#   clean      remove build artifacts
#   check-nova verify the NOVA toolchain is reachable
#   help       list targets

NOVA_ROOT ?= $(HOME)/NOVA
NOVA      := $(NOVA_ROOT)/nova
BIN       := bin

SRC_MODULES := $(shell find src -name '*.nova' ! -name '*.pending' 2>/dev/null | sort)
UNIT_TESTS  := $(shell find tests/unit -name '*.nova' 2>/dev/null | sort)
BENCHMARKS  := $(shell find tests/benchmark -name '*.nova' 2>/dev/null | sort)
SELFCHECK   := examples/kernel_selfcheck.nova
SPINE       := examples/companion_spine.nova
DAEMON      := examples/crossengin_daemon.nova
CHAT        := examples/crossengin_chat.nova
KGSYNC_PUB  := examples/crossengin_kg_publisher.nova
KGSYNC_SUB  := examples/crossengin_kg_subscriber.nova
FED_COORD   := examples/crossengin_fed_coordinator.nova

.PHONY: all build test benchmark coverage lint-ints install integration clean check-nova help cross-windows smoke-windows-ce

all: build

# Cross-compile CrossEngin's main entry points for Windows. Requires the
# mingw-w64 toolchain (x86_64-w64-mingw32-as, x86_64-w64-mingw32-ld). NOVA
# must already be built so $(NOVA_ROOT)/bin/nova exists -- the Linux nova
# binary is used to cross-emit windows assembly. Call the compiler directly
# (the `nova` wrapper script doesn't forward --target=).
WIN_AS       = x86_64-w64-mingw32-as
WIN_LD       = x86_64-w64-mingw32-ld
WIN_LIB      = -L/usr/x86_64-w64-mingw32/lib -lkernel32 -lws2_32
NOVA_COMPILE = $(NOVA_ROOT)/bin/nova

# (source path, output exe stem) pairs. The exe stem matches the Linux
# `make install` naming so docs/runbooks/scripts can use one set of names
# (e.g. `bin/crossengin-selfcheck{,.exe}`).
#   kernel_selfcheck.nova            -> crossengin-selfcheck.exe
#   companion_spine.nova             -> crossengin-spine.exe
#   crossengin_daemon.nova           -> crossengin.exe          (the unified agent)
#   crossengin_chat.nova             -> crossengin-chat.exe
#   crossengin_kg_publisher.nova     -> crossengin-kg-publisher.exe
#   crossengin_kg_subscriber.nova    -> crossengin-kg-subscriber.exe
#   crossengin_fed_coordinator.nova  -> crossengin-fed-coordinator.exe
CROSS_WIN_PAIRS = \
	$(SELFCHECK)::crossengin-selfcheck \
	$(SPINE)::crossengin-spine \
	$(DAEMON)::crossengin \
	$(CHAT)::crossengin-chat \
	$(KGSYNC_PUB)::crossengin-kg-publisher \
	$(KGSYNC_SUB)::crossengin-kg-subscriber \
	$(FED_COORD)::crossengin-fed-coordinator

cross-windows: check-nova
	@mkdir -p $(BIN)
	@for pair in $(CROSS_WIN_PAIRS); do \
		src=$${pair%::*}; \
		name=$${pair##*::}; \
		if [ ! -f "$$src" ]; then \
			printf '  cross-compile %-50s SKIP (source missing)\n' "$$src"; \
			continue; \
		fi; \
		printf '  cross-compile %-50s ' "$$src"; \
		if "$(NOVA_COMPILE)" "$$src" --target=windows --nova-root="$(NOVA_ROOT)" -o "$(BIN)/$$name.s" >/tmp/ce_win.log 2>&1; then \
			$(WIN_AS) -o "$(BIN)/$$name.o" "$(BIN)/$$name.s" 2>>/tmp/ce_win.log && \
			$(WIN_LD) -o "$(BIN)/$$name.exe" "$(BIN)/$$name.o" $(WIN_LIB) 2>>/tmp/ce_win.log && \
			echo "OK -> $(BIN)/$$name.exe" || { echo "LINK FAIL"; sed 's/^/      /' /tmp/ce_win.log; exit 1; }; \
		else \
			echo "COMPILE FAIL"; sed 's/^/      /' /tmp/ce_win.log; exit 1; \
		fi; \
	done
	@echo "cross-windows: done. Run under wine with"
	@echo "  XDG_RUNTIME_DIR=/tmp/xdg-runtime wine $(BIN)/<name>.exe"

# Run a functional smoke for each cross-compiled .exe under Wine. Requires
# `cross-windows` already built the artifacts and `wine` is on PATH. The
# tests are scoped narrowly -- they confirm each binary BOOTS, runs the
# happy path, and exits cleanly. Deeper assertions live in
# tests/integration/ (Linux only).
#
# WSL/Wine assumptions:
#   - WINEDEBUG=-all          quiets the per-process startup chatter
#   - XDG_RUNTIME_DIR points at a writable dir (Wine on a CI sandbox can
#     refuse to start if /run/user/<uid> is unwritable)
#   - The publisher must start FIRST (it listens), then the subscriber dials
#
# Each step prints PASS/FAIL/SKIP. Failing tests do not abort the run --
# the goal is a TRUTH REPORT, not a green check. The summary line at the
# end reflects the actual count.
smoke-windows-ce:
	@if ! command -v wine >/dev/null 2>&1; then \
		echo "smoke-windows-ce: SKIP (wine not installed)"; exit 0; \
	fi
	@mkdir -p $${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}
	@chmod 700 $${XDG_RUNTIME_DIR:-/tmp/xdg-runtime} 2>/dev/null || true
	@pass=0; fail=0; failures=""; \
	export XDG_RUNTIME_DIR=$${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}; \
	export WINEDEBUG=-all; \
	check() { name="$$1"; cond="$$2"; \
		if [ $$cond -eq 1 ]; then echo "  PASS  $$name"; pass=$$((pass+1)); \
		else echo "  FAIL  $$name"; fail=$$((fail+1)); failures="$$failures $$name"; fi; }; \
	echo "=== smoke-windows-ce: 7 functional Wine smokes ==="; \
	\
	echo "--- selfcheck ---"; \
	if [ -f $(BIN)/crossengin-selfcheck.exe ]; then \
		out=$$(timeout 30 wine $(BIN)/crossengin-selfcheck.exe 2>&1 | tail -3); \
		echo "$$out" | sed 's/^/    /'; \
		if echo "$$out" | grep -q "substrate self-check: OK"; then check "selfcheck prints OK" 1; else check "selfcheck prints OK" 0; fi; \
	else echo "    SKIP (binary missing)"; fail=$$((fail+1)); failures="$$failures selfcheck-missing"; fi; \
	\
	echo "--- spine ---"; \
	if [ -f $(BIN)/crossengin-spine.exe ]; then \
		out=$$(timeout 30 wine $(BIN)/crossengin-spine.exe 2>&1 | tail -3); \
		echo "$$out" | sed 's/^/    /'; \
		if echo "$$out" | grep -q "companion spine: OK"; then check "spine prints OK" 1; else check "spine prints OK" 0; fi; \
	else echo "    SKIP (binary missing)"; fail=$$((fail+1)); failures="$$failures spine-missing"; fi; \
	\
	echo "--- daemon ---"; \
	if [ -f $(BIN)/crossengin.exe ]; then \
		rm -f /tmp/crossengin.default.snap /tmp/crossengin.default.dlog; \
		out=$$(timeout 60 wine $(BIN)/crossengin.exe 2>&1 | tail -3); \
		echo "$$out" | sed 's/^/    /'; \
		if echo "$$out" | grep -q "crossengin: OK"; then check "daemon prints OK" 1; else check "daemon prints OK" 0; fi; \
	else echo "    SKIP (binary missing)"; fail=$$((fail+1)); failures="$$failures daemon-missing"; fi; \
	\
	echo "--- chat (/quit) ---"; \
	if [ -f $(BIN)/crossengin-chat.exe ]; then \
		rm -f /tmp/crossengin.default.snap /tmp/crossengin.default.dlog; \
		rc=0; printf '/quit\n' | timeout 30 wine $(BIN)/crossengin-chat.exe >/tmp/ce_smoke_chat.out 2>&1 || rc=$$?; \
		tail -3 /tmp/ce_smoke_chat.out | sed 's/^/    /'; \
		if [ $$rc -eq 0 ] || [ $$rc -eq 1 ]; then check "chat exits cleanly on /quit (rc=$$rc)" 1; \
		else check "chat exits cleanly on /quit (rc=$$rc)" 0; fi; \
	else echo "    SKIP (binary missing)"; fail=$$((fail+1)); failures="$$failures chat-missing"; fi; \
	\
	echo "--- kg pub/sub pipeline ---"; \
	if [ -f $(BIN)/crossengin-kg-publisher.exe ] && [ -f $(BIN)/crossengin-kg-subscriber.exe ]; then \
		port=$$(( 31000 + RANDOM % 1000 )); \
		rm -f /tmp/ce_smoke_pub.out /tmp/ce_smoke_sub.out; \
		( CE_KGSYNC_PORT=$$port printf 'foo\nbar\nbye\n' | timeout 30 wine $(BIN)/crossengin-kg-publisher.exe >/tmp/ce_smoke_pub.out 2>&1 ) & PUB=$$!; \
		sleep 4; \
		CE_KGSYNC_HOST=127.0.0.1 CE_KGSYNC_PORT=$$port timeout 30 wine $(BIN)/crossengin-kg-subscriber.exe </dev/null >/tmp/ce_smoke_sub.out 2>&1; \
		wait $$PUB 2>/dev/null; \
		echo "    pub tail:"; tail -3 /tmp/ce_smoke_pub.out | sed 's/^/      /'; \
		echo "    sub tail:"; tail -3 /tmp/ce_smoke_sub.out | sed 's/^/      /'; \
		if grep -q "recv .* foo" /tmp/ce_smoke_sub.out; then check "subscriber received foo" 1; else check "subscriber received foo" 0; fi; \
		if grep -q "recv .* bar" /tmp/ce_smoke_sub.out; then check "subscriber received bar" 1; else check "subscriber received bar" 0; fi; \
	else echo "    SKIP (binary missing)"; fail=$$((fail+1)); failures="$$failures kgsync-missing"; fi; \
	\
	echo "--- fed-coordinator ---"; \
	if [ -f $(BIN)/crossengin-fed-coordinator.exe ]; then \
		port=$$(( 32000 + RANDOM % 1000 )); \
		rm -f /tmp/ce_smoke_coord.out; \
		( CE_FED_PORT=$$port CE_FED_BIND=127.0.0.1 CE_FED_SOULS=1 CE_FED_MAX_ROUNDS=1 timeout 30 wine $(BIN)/crossengin-fed-coordinator.exe >/tmp/ce_smoke_coord.out 2>&1 ) & COORD=$$!; \
		sleep 4; \
		python3 scripts/fed_smoke_client.py 127.0.0.1 $$port >/tmp/ce_smoke_coord_client.out 2>&1 || true; \
		wait $$COORD 2>/dev/null; \
		tail -6 /tmp/ce_smoke_coord.out | sed 's/^/    /'; \
		if grep -q "fed-coord: listening" /tmp/ce_smoke_coord.out; then check "coordinator entered listen state" 1; else check "coordinator entered listen state" 0; fi; \
		if grep -q "fed-coord: JOIN soul=" /tmp/ce_smoke_coord.out; then check "coordinator saw a JOIN" 1; else check "coordinator saw a JOIN" 0; fi; \
	else echo "    SKIP (binary missing)"; fail=$$((fail+1)); failures="$$failures fed-coord-missing"; fi; \
	\
	echo ""; \
	echo "=== smoke-windows-ce: $$pass passed, $$fail failed ==="; \
	if [ $$fail -ne 0 ]; then echo "    failures:$$failures"; exit 1; fi

check-nova:
	@test -x "$(NOVA)" || { \
	  echo "ERROR: NOVA launcher not found at '$(NOVA)'."; \
	  echo "Build NOVA first (cd \$$NOVA_ROOT && make), or set NOVA_ROOT=/path/to/NOVA."; \
	  exit 1; }
	@echo "NOVA toolchain: $(NOVA)"

build: check-nova
	@if [ -z "$(SRC_MODULES)" ]; then echo "build: no implemented modules under src/ yet."; exit 0; fi
	@ok=1; for m in $(SRC_MODULES); do \
	  printf '  compile %-40s ' "$$m"; \
	  if "$(NOVA)" build "$$m" -o /tmp/ce_build_check.bin >/tmp/ce_build.log 2>&1; then \
	    echo "OK"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_build.log; ok=0; \
	  fi; \
	done; \
	rm -f /tmp/ce_build_check.bin; \
	if [ $$ok -eq 1 ]; then echo "build: all $(words $(SRC_MODULES)) module(s) compiled."; else echo "build: FAILED"; exit 1; fi

test: check-nova
	@NOVA_ROOT="$(NOVA_ROOT)" bash scripts/test.sh

# Static module-coverage report: every src/ module must be reachable through
# the import graph from some tests/unit/ test. No NOVA toolchain required.
# Fails (exit 1) if any module is uncovered. (NL_AND_COVERAGE C2.)
coverage:
	@bash scripts/coverage.sh

# Static guard against NOVA codegen bug #11: flag large integer literals used as
# raw operands of multiplication/bitwise ops (use int_* or annotate // int-safe).
# Fails (exit 1) on any unguarded finding. No NOVA toolchain required. (ADR-0066.)
lint-ints:
	@python3 scripts/int_safety_lint.py

benchmark: check-nova
	@if [ -z "$(BENCHMARKS)" ]; then echo "benchmark: no benchmarks under tests/benchmark/ yet."; exit 0; fi
	@for b in $(BENCHMARKS); do \
	  echo "--- $$b ---"; \
	  "$(NOVA)" run "$$b" 2>&1 | grep -v '^Compiled:'; \
	done

install: build
	@mkdir -p $(BIN)
	@if [ -f "$(SELFCHECK)" ]; then \
	  printf '  build %s ... ' "$(SELFCHECK)"; \
	  if "$(NOVA)" build "$(SELFCHECK)" -o "$(BIN)/crossengin-selfcheck" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin-selfcheck"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	else \
	  echo "install: $(SELFCHECK) not present; nothing to install yet."; \
	fi
	@if [ -f "$(SPINE)" ]; then \
	  printf '  build %s ... ' "$(SPINE)"; \
	  if "$(NOVA)" build "$(SPINE)" -o "$(BIN)/crossengin-spine" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin-spine"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	fi
	@if [ -f "$(DAEMON)" ]; then \
	  printf '  build %s ... ' "$(DAEMON)"; \
	  if "$(NOVA)" build "$(DAEMON)" -o "$(BIN)/crossengin" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	fi
	@if [ -f "$(CHAT)" ]; then \
	  printf '  build %s ... ' "$(CHAT)"; \
	  if "$(NOVA)" build "$(CHAT)" -o "$(BIN)/crossengin-chat" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin-chat"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	fi
	@if [ -f "$(KGSYNC_PUB)" ]; then \
	  printf '  build %s ... ' "$(KGSYNC_PUB)"; \
	  if "$(NOVA)" build "$(KGSYNC_PUB)" -o "$(BIN)/crossengin-kg-publisher" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin-kg-publisher"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	fi
	@if [ -f "$(KGSYNC_SUB)" ]; then \
	  printf '  build %s ... ' "$(KGSYNC_SUB)"; \
	  if "$(NOVA)" build "$(KGSYNC_SUB)" -o "$(BIN)/crossengin-kg-subscriber" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin-kg-subscriber"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	fi
	@if [ -f "$(FED_COORD)" ]; then \
	  printf '  build %s ... ' "$(FED_COORD)"; \
	  if "$(NOVA)" build "$(FED_COORD)" -o "$(BIN)/crossengin-fed-coordinator" >/tmp/ce_install.log 2>&1; then \
	    echo "OK -> $(BIN)/crossengin-fed-coordinator"; \
	  else \
	    echo "FAIL"; sed 's/^/      /' /tmp/ce_install.log; exit 1; \
	  fi; \
	fi

integration: install
	@scripts="$$(find tests/integration -maxdepth 1 -name '*.sh' ! -name '_*' 2>/dev/null | sort)"; \
	if [ -z "$$scripts" ]; then \
	    echo "integration: no scripts under tests/integration/"; exit 0; \
	fi; \
	failed=0; \
	for t in $$scripts; do \
	    echo "==> $$t"; \
	    if ! bash "$$t"; then \
	        echo "integration: FAILED -- $$t"; \
	        failed=1; \
	    fi; \
	done; \
	if [ $$failed -ne 0 ]; then exit 1; fi; \
	echo "=== all integration tests passed ==="

clean:
	rm -rf $(BIN) /tmp/ce_build_check.bin /tmp/ce_build.log /tmp/ce_install.log
	@echo "clean: done"

help:
	@echo "CrossEngin make targets:"
	@echo "  build       compile every implemented NOVA module under src/"
	@echo "  test        compile and run every unit test under tests/unit/"
	@echo "  benchmark   run every benchmark under tests/benchmark/"
	@echo "  coverage    report module-level unit-test coverage (static)"
	@echo "  lint-ints   flag large-literal arithmetic at risk of codegen bug #11"
	@echo "  install     build the self-check, companion-spine, unified daemon, kg-sync pub/sub, and fed-coordinator into ./bin/"
	@echo "  integration run every end-to-end scenario + admin-command script in tests/integration/"
	@echo "  clean       remove build artifacts"
	@echo "  check-nova  verify the NOVA toolchain is reachable"
	@echo "Override the toolchain with: make NOVA_ROOT=/path/to/NOVA <target>"
