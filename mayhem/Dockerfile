# syntax=docker/dockerfile:1.7
# Commit image for the XLS parser fuzz targets: builds on the org C/C++ base. XLS's own Bazel build is not
# used; mayhem/build.sh compiles an IR-parser + DSLX-frontend slice with CMake against third-party deps
# that mayhem/install-deps.sh builds from pinned, checksummed tarballs into /opt/toolchains/xlsdeps.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# Third-party deps, built once as root (network is available at image build time only).
USER root
COPY mayhem/install-deps.sh /tmp/install-deps.sh
RUN bash /tmp/install-deps.sh && rm -f /tmp/install-deps.sh && chmod -R a+rX /opt/toolchains/xlsdeps

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
