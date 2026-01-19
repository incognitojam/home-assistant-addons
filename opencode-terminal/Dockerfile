ARG BUILD_FROM
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

RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

RUN HA_ARCH=$(cat /tmp/ha_arch) && \
    echo "Downloading ha CLI for architecture: $HA_ARCH" && \
    curl -Lso /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${CLI_VERSION}/ha_${HA_ARCH}" \
    && chmod a+x /usr/bin/ha \
    && rm /tmp/ha_arch

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
