FROM ghcr.io/home-assistant/base:3.24-2026.06.1

ARG BUILD_FROM
ARG BUILD_ARCH
ARG BUILD_VERSION=0.2.0
ARG CLI_VERSION=5.2.0
ARG CODEX_RELEASE=0.147.0
ARG TARGETARCH
ARG TARGETVARIANT

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="amd64|aarch64"

# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash \
    bubblewrap \
    curl \
    git \
    jq \
    less \
    libgcc \
    libstdc++ \
    nano \
    ncurses \
    nodejs \
    npm \
    openssh-client \
    perl \
    ripgrep \
    sed \
    ttyd

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN npm install --global --prefix /usr/local --no-audit --no-fund "@openai/codex@${CODEX_RELEASE}" \
    && codex --version

ENV NPM_CONFIG_PREFIX="/data/npm" \
    PATH="/data/npm/bin:${PATH}"

RUN set -eux; \
    ha_arch="${BUILD_ARCH:-}"; \
    if [ -z "${ha_arch}" ]; then \
      case "${TARGETARCH}${TARGETVARIANT}" in \
        amd64) ha_arch="amd64" ;; \
        arm64*|aarch64) ha_arch="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}${TARGETVARIANT}" >&2; exit 1 ;; \
      esac; \
    fi; \
    case "${ha_arch}" in \
      amd64|aarch64) ;; \
      *) echo "Unsupported Home Assistant CLI architecture: ${ha_arch}" >&2; exit 1 ;; \
    esac; \
    curl -LfsSo /usr/bin/ha "https://github.com/home-assistant/cli/releases/download/${CLI_VERSION}/ha_${ha_arch}"; \
    chmod a+x /usr/bin/ha; \
    ha help >/dev/null

WORKDIR /config

COPY run.sh /run.sh
COPY AGENTS.md /opt/AGENTS.md
COPY codex-profile.sh /etc/profile.d/90-codex.sh
COPY codex-auth-launcher.sh /usr/local/bin/codex-auth-launcher
COPY reset-codex-version.sh /usr/local/bin/reset-codex-version
RUN chmod a+x \
        /run.sh \
        /usr/local/bin/codex-auth-launcher \
        /usr/local/bin/reset-codex-version \
    && chmod 644 /etc/profile.d/90-codex.sh /opt/AGENTS.md

CMD ["/run.sh"]
