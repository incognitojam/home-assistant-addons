# OpenCode for Home Assistant

A web-based OpenCode interface that runs inside Home Assistant with access to your `/config` directory and HA APIs.

## Features

- **OpenCode Web UI**: Runs `opencode web` on a fixed port for ingress
- **Configurable Auth**: Optional username/password protection
- **Home Assistant Integration**: Access HA APIs and `/config` files
- **Multi-Arch**: `amd64` and `aarch64`

## Installation

1. Add this repository to your Home Assistant add-on store.
2. Install the **OpenCode** add-on.
3. Start the add-on and open the Web UI.

## Configuration

Options in the add-on config:

- `server_port` (default `4096`)
- `server_hostname` (default `0.0.0.0`)
- `server_username` (optional)
- `server_password` (optional, recommended)

Example:

```yaml
server_port: 4096
server_hostname: 0.0.0.0
server_username: opencode
server_password: your-strong-password
```

## Notes

- OpenCode config/agents live in `/config/opencode` inside Home Assistant.
- The add-on includes the Home Assistant CLI (`ha`).
- If you leave `server_password` empty, the web UI is unsecured.

## License

MIT (see `LICENSE` in the repo root).
