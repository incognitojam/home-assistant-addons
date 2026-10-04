# Codex for Home Assistant

A Home Assistant app that opens the OpenAI Codex CLI in a browser terminal.

## Features

- Pinned Codex CLI fallback installed with npm
- Opt-in Codex updates that persist across app image upgrades
- Pre-launch authentication picker for device code or API key sign-in
- Browser terminal through Home Assistant ingress
- Starts in `/config` with write access to Home Assistant configuration
- Bundled `AGENTS.md` guidance for Home Assistant-aware Codex sessions
- Persistent Codex state in `/data/.codex`
- Home Assistant `ha` CLI included
- Supports `amd64` and `aarch64`

See [DOCS.md](DOCS.md) for setup and usage details.

## Development

CI builds both supported architectures and tests actual Codex daemon startup, version reporting, and shutdown. The test uses a disposable container with empty state, no network access, and no credentials or model requests.

Run the same test locally after building the image:

```bash
docker build --build-arg BUILD_ARCH=aarch64 -t local/codex-terminal:test codex-terminal
docker run --rm --interactive --network none \
  --entrypoint /bin/bash \
  --env HOME=/data/home \
  --env CODEX_HOME=/data/.codex \
  --env CODEX_SQLITE_HOME=/data/.codex \
  local/codex-terminal:test -s < codex-terminal/tests/daemon-startup.sh
```

Use `BUILD_ARCH=amd64` when building on an x86-64 host.
