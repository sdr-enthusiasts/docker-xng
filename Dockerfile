FROM rust:1.96.0-bookworm@sha256:19817ead3289c8c631c73df281e18b59b172f6a31f4f563290f69cddd06c30e9 AS rust

# xng links libSoapySDR dynamically, so it must be built against the exact
# SoapySDR the runtime image ships (the base image builds SoapySDR from the
# latest upstream tag, so its soname moves). Build on the runtime base image
# itself, with the Rust toolchain copied in from the pinned rust image.
FROM ghcr.io/sdr-enthusiasts/docker-baseimage:soapy-full AS builder

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
COPY --from=rust /usr/local/rustup /usr/local/rustup
COPY --from=rust /usr/local/cargo /usr/local/cargo

# Upstream git ref to build (branch, tag, or commit). Defaults to the
# upstream default branch; pin to a tag/commit for a reproducible build.
#
# TEMPORARILY pinned to perf/vdl2: the VDL2 performance work is not on master
# yet, and this image exists to test it on real hardware. Set XNG_REF back to
# "master" once it lands.
ARG XNG_REPO="https://github.com/airframesio/xng.git"
ARG XNG_REF="perf/vdl2"

WORKDIR /tmp
# hadolint ignore=DL3008,DL3003,SC1091
RUN set -x && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
    pkg-config \
    libssl-dev \
    libclang-dev \
    protobuf-compiler && \
    # Clone the requested ref. `--branch` accepts branches and tags; for a
    # bare commit SHA we fall back to a full clone + checkout.
    git clone "${XNG_REPO}" /tmp/xng && \
    cd /tmp/xng && \
    git checkout "${XNG_REF}" && \
    # Record what we actually built, for version/change tracking.
    git rev-parse HEAD > /CONTAINER_VERSION && \
    cat /CONTAINER_VERSION

WORKDIR /tmp/xng
RUN cargo build --release --bin xng

FROM ghcr.io/sdr-enthusiasts/docker-baseimage:soapy-full

# Session 1 uses these UNSUFFIXED vars. Additional sessions are defined by
# appending an index: XNG_MODE_2, XNG_SERIAL_2, XNG_CHANNELS_2, … (sessions
# are numbered consecutively from 1; gaps fail at startup). Per-session vars
# are: SDR, DRIVER, SERIAL, BIASTEE, MODE, GAIN, SAMPLE_RATE, CENTER,
# CHANNELS, RECEIVER_POS, DEMOD_EFFORT. The XNG_OUTPUTS / feed / dashboard
# vars below are global (one set per station, unsuffixed only).
#
# XNG_STATION_ID is intentionally NOT defaulted — the container fails fast
# unless the operator sets it.
ENV XNG_CONFIG="" \
    XNG_MODE="acars" \
    XNG_DRIVER="rtlsdr" \
    XNG_SERIAL="" \
    XNG_BIASTEE="false" \
    XNG_SDR="" \
    XNG_GAIN="" \
    XNG_SAMPLE_RATE="" \
    XNG_CENTER="" \
    XNG_CHANNELS="" \
    XNG_RECEIVER_POS="" \
    XNG_DEMOD_EFFORT="" \
    XNG_FEED_AIRFRAMES="false" \
    XNG_JSON="false" \
    XNG_JSONL="" \
    XNG_UDP="" \
    XNG_ZMQ="" \
    XNG_METRICS="" \
    XNG_HTTP="0.0.0.0:8080" \
    XNG_SBS="" \
    XNG_BEAST="" \
    XNG_NMEA_TCP="" \
    XNG_NMEA_UDP="" \
    XNG_MQTT="" \
    XNG_MQTT_TOPIC="" \
    XNG_VERBOSE="" \
    XNG_DECODE_THREADS=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs /
# hadolint ignore=DL3008,DL3003,SC1091
RUN set -x && \
    KEPT_PACKAGES=() && \
    TEMP_PACKAGES=() && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    "${KEPT_PACKAGES[@]}" \
    "${TEMP_PACKAGES[@]}"\
    && \
    # clean up
    apt-get remove -y "${TEMP_PACKAGES[@]}" && \
    apt-get autoremove -y && \
    rm -rf /src/* /tmp/* /var/lib/apt/lists/*

COPY --from=builder /tmp/xng/target/release/xng /opt/xng
COPY --from=builder /CONTAINER_VERSION /CONTAINER_VERSION

# Add healthcheck
HEALTHCHECK --start-period=3600s --interval=600s CMD /scripts/healthcheck.sh
