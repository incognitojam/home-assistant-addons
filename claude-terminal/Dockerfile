ARG BUILD_FROM
FROM ${BUILD_FROM}

# Build arguments for Home Assistant CLI
ARG BUILD_ARCH
ARG TARGETARCH
ARG CLI_VERSION=4.43.0

# Map Docker's TARGETARCH to Home Assistant's architecture naming
# Docker TARGETARCH values: amd64, arm64, arm/v7, arm/v6
# Home Assistant naming: amd64, aarch64, armv7, armhf
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

# Install packages in a single layer to minimize image size
RUN apk add --no-cache \
    nodejs \
    npm \
    bash \
    curl \
    git \
    libgcc \
    libstdc++ \
    nano \
    ripgrep

# Install Claude Code using native installer
# Alpine/musl requires USE_BUILTIN_RIPGREP=0 with system ripgrep installed
ENV USE_BUILTIN_RIPGREP=0
ENV PATH="/root/.claude/local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && claude --version

# Install Home Assistant CLI
RUN HA_ARCH=$(cat /tmp/ha_arch) && \
    echo "Downloading ha CLI for architecture: $HA_ARCH" && \
    curl -Lso /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${CLI_VERSION}/ha_${HA_ARCH}" \
    && chmod a+x /usr/bin/ha \
    && rm /tmp/ha_arch

# Create directory for Claude configuration and set working directory
RUN mkdir -p /config/claude-config
WORKDIR /config

# Copy startup script, modular scripts, and Claude context documentation
COPY run.sh /run.sh
COPY scripts/ /opt/scripts/
COPY CLAUDE.md /opt/CLAUDE.md
RUN chmod +x /run.sh \
    && chmod +x /opt/scripts/*.sh \
    && chmod 644 /opt/CLAUDE.md

# Use exec form for better signal handling
CMD ["/run.sh"]