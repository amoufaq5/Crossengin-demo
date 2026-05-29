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

.PHONY: all build test benchmark install integration clean check-nova help cross-windows

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

cross-windows: check-nova
	@mkdir -p $(BIN)
	@for src in $(SELFCHECK) $(SPINE) $(DAEMON) $(CHAT) $(KGSYNC_PUB) $(KGSYNC_SUB); do \
		if [ ! -f "$$src" ]; then continue; fi; \
		name=$$(basename "$$src" .nova); \
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
	@echo "  install     build the self-check, companion-spine, unified daemon, and kg-sync pub/sub into ./bin/"
	@echo "  integration run every end-to-end scenario + admin-command script in tests/integration/"
	@echo "  clean       remove build artifacts"
	@echo "  check-nova  verify the NOVA toolchain is reachable"
	@echo "Override the toolchain with: make NOVA_ROOT=/path/to/NOVA <target>"
