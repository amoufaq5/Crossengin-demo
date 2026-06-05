# CrossEngin backend image -- HTTP wrapper around the Linux ELF chat surface.
#
# Build:  docker build -t crossengin-backend:dev .
# Run:    docker run --rm -p 8080:8080 -e CROSSENGIN_TOKEN=... crossengin-backend:dev
#
# Pinned to ubuntu:24.04 to match docs/GETTING_STARTED.md Section 2 -- this is
# the first-class supported host for the NOVA toolchain + CrossEngin build.
FROM ubuntu:24.04

# Avoid prompts during apt installs in CI builds.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1

# Build deps + a Python interpreter for the HTTP wrapper.
# - build-essential pulls in gcc + make + binutils (the GNU as/ld the
#   bootstrap.sh script checks for).
# - gdb / objdump are not strictly required for runtime but bootstrap.sh
#   verifies they exist; keeping them in the image keeps that script's
#   diagnostics meaningful.
# - python3 powers server.py.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        binutils \
        gdb \
        git \
        ca-certificates \
        python3 \
 && rm -rf /var/lib/apt/lists/*

# --- Build NOVA + CrossEngin ----------------------------------------------
# Both repos are cloned side-by-side per scripts/bootstrap.sh's contract.
# Override either ref at build time:
#   docker build --build-arg NOVA_REF=main --build-arg CROSSENGIN_REF=v0.1 .
ARG NOVA_REPO=https://github.com/amoufaq5/NOVA.git
ARG NOVA_REF=main
ARG CROSSENGIN_REPO=https://github.com/amoufaq5/Crossengin-demo.git
ARG CROSSENGIN_REF=main

ENV CE_REPO_ROOT=/opt/crossengin/repo \
    NOVA_ROOT=/opt/crossengin/NOVA

RUN mkdir -p /opt/crossengin \
 && git clone --depth=1 --branch "$NOVA_REF" "$NOVA_REPO" "$NOVA_ROOT" \
 && git clone --depth=1 --branch "$CROSSENGIN_REF" "$CROSSENGIN_REPO" "$CE_REPO_ROOT"

# Build the NOVA toolchain. self-host verifies stage2.s == stage3.s.
# A failure here is a NOVA regression -- the image cannot be safely shipped.
RUN cd "$NOVA_ROOT" \
 && make \
 && make self-host

# Bootstrap + install CrossEngin. bootstrap.sh validates the host environment
# (gcc/as/ld/make/gdb on PATH; NOVA at $NOVA_ROOT). After bootstrap, the
# Makefile target `make install` produces bin/crossengin* binaries.
RUN cd "$CE_REPO_ROOT" \
 && bash scripts/bootstrap.sh \
 && make install

# --- Wrapper layer --------------------------------------------------------
COPY server.py /opt/crossengin/server.py
COPY entrypoint.sh /opt/crossengin/entrypoint.sh
RUN chmod +x /opt/crossengin/entrypoint.sh

# Persistence -- the Linux backend keeps cognitive state on local disk
# (decision log, KG snapshots). Mount a volume here for durable data.
RUN mkdir -p /data
ENV CE_DATA_DIR=/data
VOLUME ["/data"]

EXPOSE 8080

# Container-level healthcheck -- separate from the load-balancer probe in
# docker-compose / Fly. Hits the wrapper's /health endpoint which does NOT
# require auth.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request,sys; \
        r=urllib.request.urlopen('http://127.0.0.1:8080/health',timeout=3); \
        sys.exit(0 if r.status==200 else 1)" || exit 1

ENTRYPOINT ["/opt/crossengin/entrypoint.sh"]
