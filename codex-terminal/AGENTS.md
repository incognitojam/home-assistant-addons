# Home Assistant Codex Environment

You are running inside the Codex for Home Assistant add-on container.

## Environment

- The working directory is `/config`, the Home Assistant configuration directory.
- `/config` is persistent and writable. Treat it as the user's live Home Assistant configuration.
- Codex state is stored in `/data/.codex`.
- The shell home directory is `/data/home`.
- The Home Assistant Supervisor token is available as `SUPERVISOR_TOKEN`.

## Available Tools

- `ha` is the Home Assistant CLI. Use `ha --help` to discover commands.
- `jq`, `rg`, `git`, `curl`, `nano`, and standard Alpine Linux shell tools are available.
- Home Assistant Core API requests should use `Authorization: Bearer ${SUPERVISOR_TOKEN}`.

## Working Rules

- Inspect existing configuration before editing it.
- Preserve user secrets. Do not print or expose values from `/config/secrets.yaml`.
- Prefer small, focused changes to Home Assistant YAML, scripts, automations, and custom components.
- Before restarting Home Assistant after configuration edits, run `ha core check` when practical.
- Before restarting the host machine, warn the user that the Codex session will be interrupted and that they will need to resume the session after the restart.
- For risky or broad changes, create a Home Assistant backup first with the `ha backups` commands.
- After changes, check relevant Home Assistant logs with `ha core logs` or `ha addons logs`.

## Important Paths

- `/config/configuration.yaml` - main Home Assistant configuration
- `/config/automations.yaml` - automations
- `/config/scripts.yaml` - scripts
- `/config/scenes.yaml` - scenes
- `/config/secrets.yaml` - secret values
- `/config/custom_components/` - custom integrations
- `/data/.codex/` - Codex state, authentication, sessions, logs, and skills

## API Examples

```bash
curl -s "http://supervisor/core/api/states" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" | jq
```

```bash
curl -s -X POST "http://supervisor/core/api/services/homeassistant/reload_core_config" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}'
```
