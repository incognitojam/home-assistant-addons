# Home Assistant OpenCode Environment

You are running inside the **OpenCode** add-on for Home Assistant. This container provides access to Home Assistant configuration files and APIs.

## Environment Overview

- **Base OS**: Alpine Linux (Home Assistant base image)
- **Shell**: bash (with bashio helpers)
- **Container Runtime**: Home Assistant Supervisor
- **Persistent Storage**: `/config` and `/data`

## Key Paths

### `/config` - Home Assistant Configuration
- Main Home Assistant configuration directory
- Read/write access
- Common files:
  - `configuration.yaml`
  - `automations.yaml`
  - `scripts.yaml`
  - `secrets.yaml`
  - `custom_components/`

### `/config/opencode` - OpenCode Config + Agents
- OpenCode config lives here (`opencode.json`)
- Agent definitions can be placed in `/config/opencode/agents/`

### `/data` - Add-on Persistent Data
- Cache and state directories
- Survives container restarts

## Environment Variables

```bash
HOME=/data/home
XDG_CONFIG_HOME=/data/.config
XDG_CACHE_HOME=/data/.cache
XDG_STATE_HOME=/data/.local/state
OPENCODE_CONFIG_DIR=/config/opencode
SUPERVISOR_TOKEN=...    # Home Assistant API token (auto-injected)
HASSIO_TOKEN=...        # Legacy alias
```

## Home Assistant CLI

The `ha` command is available for Supervisor and Core management.

```bash
ha --help
ha core info
ha addons list
```

## Home Assistant APIs

### Supervisor API (No Auth Required)
```bash
curl -s http://supervisor/info
curl -s http://supervisor/addons
curl -s http://supervisor/backups
```

### Core API (Auth Required)
```bash
curl -s "http://supervisor/core/api/states" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}"

curl -s -X POST "http://supervisor/core/api/services/light/turn_on" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.living_room"}'
```

## Best Practices

- Create backups before major changes: `ha backups new`
- Validate config: `ha core check`
- Restart or reload as needed after edits

## Session Continuity

- Restarting the add-on, Supervisor, or host **terminates the active session**.
- Session history should persist and is typically resumable from the OpenCode web UI.
