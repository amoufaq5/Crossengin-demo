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

.PHONY: all build test benchmark install clean check-nova help

all: build

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

clean:
	rm -rf $(BIN) /tmp/ce_build_check.bin /tmp/ce_build.log /tmp/ce_install.log
	@echo "clean: done"

help:
	@echo "CrossEngin make targets:"
	@echo "  build      compile every implemented NOVA module under src/"
	@echo "  test       compile and run every unit test under tests/unit/"
	@echo "  benchmark  run every benchmark under tests/benchmark/"
	@echo "  install    build the self-check, companion-spine, and unified daemon into ./bin/"
	@echo "  clean      remove build artifacts"
	@echo "  check-nova verify the NOVA toolchain is reachable"
	@echo "Override the toolchain with: make NOVA_ROOT=/path/to/NOVA <target>"
