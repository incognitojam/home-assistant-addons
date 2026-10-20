# Home Assistant add-on environment

You are running inside the Claude Code add-on for Home Assistant. The add-on rewrites this file on every start; put lasting instructions in `/config/CLAUDE.md` or `~/.claude/CLAUDE.md` instead.

## Where you are

- `/config` is the user's live Home Assistant configuration, and the working directory. Edits take effect on the running system.
- `/data` is the add-on's private persistent storage (`HOME=/data/home`). Everything else in the container is reset when the add-on restarts or updates.
- The container is Alpine Linux (musl) running as root. `apk add` works, but packages are lost on restart.
- `python3` has only the standard library: no pip and no PyYAML. Use `jq` for JSON and `sqlite3` for SQLite.
- A `/config/AGENTS.md` that describes Codex belongs to the separate Codex add-on. Its paths, such as `/data/.codex`, do not exist in this container.

## Reaching Home Assistant

- The `ha` CLI talks to the Supervisor: `ha core info`, `ha core logs`, `ha core check`, `ha backups new --name <name>`. Run `ha <command> --help` for details.
- The Core REST API is at `http://supervisor/core/api`, authenticated with `$SUPERVISOR_TOKEN`:

  ```bash
  curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/states/sun.sun | jq
  curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/services/automation/reload
  ```

- The Supervisor API is at `http://supervisor/` with the same token. This add-on has the manager role, so it can stop, restart and reconfigure Home Assistant and other add-ons.

## Making changes safely

- Read the existing configuration before editing it, and keep changes small.
- Before a broad or risky change, create a backup with `ha backups new --name <name>`.
- After editing YAML, run `ha core check` before reloading or restarting.
- Prefer reloading to restarting. Most domains have a reload service, such as `automation.reload`, `script.reload`, `scene.reload`, or `homeassistant.reload_all`. Restart Core (`ha core restart`) only when a change requires it, and ask the user first.
- Before restarting Core, check that nothing else is in progress, such as a running Supervisor job (`ha jobs info`).
- Do not edit files under `/config/.storage/` while Home Assistant is running. Home Assistant owns them and overwrites manual edits. Use the UI or the API instead.
- After a change, check `ha core logs` for new errors.

## Protecting context and secrets

- Do not print `/config/secrets.yaml` or any token values. Refer to secrets by name with `!secret <name>`.
- Do not read large files whole. Search `home-assistant.log` and other logs with `rg` or `tail`.
- The recorder database `/config/home-assistant_v2.db` can be several gigabytes, and Home Assistant writes to it continuously. Query it with `sqlite3 -readonly` and use `LIMIT`. Never modify it.
