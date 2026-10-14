# Home Assistant add-on environment

You are running inside the Codex add-on for Home Assistant. Put project instructions in `/config/AGENTS.md`; local edits to this global file are preserved.

## Where you are

- `/config` is the working directory and the user's live Home Assistant configuration.
- `/data` is private persistent storage (`HOME=/data/home`, `CODEX_HOME=/data/.codex`); other container paths reset on restart.
- The container is Alpine Linux (musl) running as root; `apk add` packages are lost on restart.
- Global npm packages and opt-in Codex updates persist in `/data/npm`.
- `/config/CLAUDE.md` belongs to the separate Claude add-on; its private paths do not apply here.

## Reaching Home Assistant

- Use `ha <command> --help` for CLI details: `ha core info`, `ha core logs`, `ha core check`, `ha backups new --name <name>`.
- Core REST API: `http://supervisor/core/api`. Supervisor API: `http://supervisor/`. Both require `Authorization: Bearer $SUPERVISOR_TOKEN`. The manager role allows control of Home Assistant and other add-ons.

## Making changes safely

- Read existing configuration and keep changes small.
- Before a broad or risky change, create a backup with `ha backups new --name <name>`.
- After editing YAML, run `ha core check` before reloading or restarting.
- Prefer domain reload services (for example `automation.reload`) to `ha core restart`. Tell the user before restarting Core.
- Use the UI or API for `/config/.storage/`; Home Assistant overwrites manual edits.
- After a change, check `ha core logs` for new errors.
- Before restarting the host, warn the user that this session will be interrupted and must be resumed afterward.

## Protecting context and secrets

- Do not print `/config/secrets.yaml` or any token values. Refer to secrets by name with `!secret <name>`.
- Search logs with `rg` or `tail`; do not read large files whole.
- Home Assistant continuously writes `/config/home-assistant_v2.db`. Never modify it or read it whole.
