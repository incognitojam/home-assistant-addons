# Codex for Home Assistant

A Home Assistant app that opens the OpenAI Codex CLI in a browser terminal.

## Features

- Codex CLI installed with the official standalone installer
- Pre-launch authentication picker for device code or API key sign-in
- Browser terminal through Home Assistant ingress
- Starts in `/config` with write access to Home Assistant configuration
- Persistent Codex state in `/data/.codex`
- Home Assistant `ha` CLI included
- Supports `amd64` and `aarch64`

See [DOCS.md](DOCS.md) for setup and usage details.
