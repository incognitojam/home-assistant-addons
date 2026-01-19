ARG BUILD_FROM
ARG OPENCODE_REPO=https://github.com/sst/opencode
ARG OPENCODE_REF=main

FROM golang:1.24-alpine AS builder
ARG OPENCODE_REPO
ARG OPENCODE_REF

RUN apk add --no-cache git ca-certificates

WORKDIR /build
RUN git clone --depth 1 --branch "${OPENCODE_REF}" "${OPENCODE_REPO}" . \
    && go build -o opencode ./cmd/opencode

FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG TARGETARCH
ARG CLI_VERSION=4.43.0

RUN if [ -z "$BUILD_ARCH" ]; then \
        case "$TARGETARCH" in \
            amd64) export HA_ARCH=amd64 ;; \
            arm64) export HA_ARCH=aarch64 ;; \
            arm/v7) export HA_ARCH=armv7 ;; \
            arm*) export HA_ARCH=armhf ;; \
            *) echo "Unknown architecture: $TARGETARCH" && exit 1 ;; \
        esac; \
        echo "$HA_ARCH" > /tmp/ha_arch; \
    else \
        echo "$BUILD_ARCH" > /tmp/ha_arch; \
    fi

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    libgcc \
    libstdc++

ENV PATH="/root/.opencode/bin:${PATH}"

RUN mkdir -p /root/.opencode/bin
COPY --from=builder /build/opencode /root/.opencode/bin/opencode
RUN chmod +x /root/.opencode/bin/opencode

RUN HA_ARCH=$(cat /tmp/ha_arch) && \
    echo "Downloading ha CLI for architecture: $HA_ARCH" && \
    curl -Lso /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${CLI_VERSION}/ha_${HA_ARCH}" \
    && chmod a+x /usr/bin/ha \
    && rm /tmp/ha_arch

COPY run.sh /run.sh
COPY AGENTS.md /opt/AGENTS.md
RUN chmod +x /run.sh \
    && chmod 644 /opt/AGENTS.md

CMD ["/run.sh"]
