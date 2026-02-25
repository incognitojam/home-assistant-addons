ARG BUILD_FROM
ARG OPENCODE_REPO=https://github.com/incognitojam/opencode
ARG OPENCODE_REF=dev

FROM --platform=$TARGETPLATFORM oven/bun:1.3.5-alpine AS builder
ARG OPENCODE_REPO
ARG OPENCODE_REF
ARG TARGETARCH

RUN apk add --no-cache build-base ca-certificates git python3

WORKDIR /src
RUN git clone --depth 1 --branch "${OPENCODE_REF}" "${OPENCODE_REPO}" .
RUN bun install --frozen-lockfile --ignore-scripts

RUN cat <<'EOF' > /src/build-opencode.ts
#!/usr/bin/env bun
import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"
import solidPlugin from "./packages/opencode/node_modules/@opentui/solid/scripts/solid-plugin"
import pkg from "./packages/opencode/package.json"
import { Script } from "@opencode-ai/script"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const repoRoot = __dirname
const opencodeDir = path.join(repoRoot, "packages", "opencode")

const archMap = {
  amd64: "x64",
  arm64: "arm64",
}
const targetArch = process.env.TARGETARCH
if (!targetArch || !(targetArch in archMap)) {
  throw new Error(`Unsupported TARGETARCH: ${targetArch ?? "undefined"}`)
}
const arch = archMap[targetArch as keyof typeof archMap]
const target = `linux-${arch}-musl`
const name = `${pkg.name}-${target}`
const outDir = "/out"

process.chdir(opencodeDir)
fs.mkdirSync(outDir, { recursive: true })

const parserWorker = fs.realpathSync(
  path.resolve(opencodeDir, "./node_modules/@opentui/core/parser.worker.js"),
)
const workerPath = "./src/cli/cmd/tui/worker.ts"
const workerRelativePath = path.relative(opencodeDir, parserWorker).replaceAll("\\", "/")

await Bun.build({
  conditions: ["browser"],
  tsconfig: "./tsconfig.json",
  plugins: [solidPlugin],
  sourcemap: "external",
  compile: {
    autoloadBunfig: false,
    autoloadDotenv: false,
    // @ts-ignore (bun types aren't up to date)
    autoloadTsconfig: true,
    autoloadPackageJson: true,
    target: name.replace(pkg.name, "bun") as any,
    outfile: path.join(outDir, "opencode"),
    execArgv: [`--user-agent=opencode/${Script.version}`, "--use-system-ca", "--"],
    windows: {},
  },
  entrypoints: ["./src/index.ts", parserWorker, workerPath],
  define: {
    OPENCODE_VERSION: `'${Script.version}'`,
    OTUI_TREE_SITTER_WORKER_PATH: "/$bunfs/root/" + workerRelativePath,
    OPENCODE_WORKER_PATH: workerPath,
    OPENCODE_CHANNEL: `'${Script.channel}'`,
    OPENCODE_LIBC: "'musl'",
  },
})
EOF

RUN TARGETARCH="${TARGETARCH}" bun /src/build-opencode.ts

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
COPY --from=builder /out/opencode /root/.opencode/bin/opencode
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
