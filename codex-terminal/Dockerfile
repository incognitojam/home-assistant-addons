FROM ghcr.io/home-assistant/base:3.22-2026.03.1

ARG BUILD_FROM
ARG BUILD_ARCH
ARG BUILD_VERSION=0.1.5
ARG CLI_VERSION=4.43.0
ARG CODEX_RELEASE=0.141.0
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
    openssh-client \
    perl \
    ripgrep \
    sed \
    ttyd

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV PATH="/root/.local/bin:${PATH}"

RUN curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_RELEASE="${CODEX_RELEASE}" CODEX_NON_INTERACTIVE=1 sh \
    && CODEX_BIN="$(command -v codex)" \
    && ln -sf "${CODEX_BIN}" /usr/local/bin/codex \
    && codex --version

RUN set -eux; \
    ha_arch="${BUILD_ARCH:-}"; \
    if [[ -z "${ha_arch}" ]]; then \
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
COPY codex-auth-launcher.sh /usr/local/bin/codex-auth-launcher
RUN chmod a+x /run.sh /usr/local/bin/codex-auth-launcher \
    && chmod 644 /opt/AGENTS.md

CMD ["/run.sh"]
