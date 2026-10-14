# Claude Code for Home Assistant

## Getting started

1. In Home Assistant, open **Settings → Apps → App Store** (called **Add-ons** on older versions).
2. Open the three-dot menu, choose **Repositories**, and add `https://github.com/incognitojam/home-assistant-addons`.
3. Install **Claude Code**, start it, and select **OPEN WEB UI** or its sidebar panel.
4. Follow Claude's onboarding and sign-in prompts in the terminal, opening the login link in your browser when asked. Authentication is handled by Claude itself.

The terminal starts in `/config` and launches Claude by default. The add-on gives Claude Home Assistant-specific context and includes the Home Assistant CLI. To use a plain shell, disable `auto_launch_claude`, save, restart the add-on, and choose **Drop to bash shell**.

## Options

Set these in the add-on's **Configuration** tab, then save and restart:

| Option | Default | Behaviour |
|--------|---------|-----------|
| `auto_launch_claude` | `true` | Launch Claude whenever a terminal opens. When disabled, show the session picker. |
| `auto_update_claude` | `true` | Enable Claude's native background updater; a downloaded version takes effect on the next Claude launch. Disabling sets `DISABLE_AUTOUPDATER=1`; it does not roll back a version already installed in persistent storage. |
| `permission_mode` | `auto` | Set Claude's `permissions.defaultMode` at add-on startup for automatic, picker, and manual launches. Choose `auto`, `acceptEdits`, `default`, or `plan`. |

Permission modes: `auto` uses an AI classifier to approve or deny actions; `acceptEdits` automatically accepts file edits; `default` prompts before risky actions; `plan` is read-only planning. The add-on opts into auto mode, and availability depends on your Claude account/model. Use `default` if you prefer to approve actions yourself. **Shift+Tab** changes modes within a session.

## Session picker and shell

With auto-launch disabled, the picker offers:

- **New interactive session (default)** — starts `claude`.
- **Continue most recent conversation (-c)** — runs `claude -c` for the current directory.
- **Resume from conversation list (-r)** — runs `claude -r` to select a saved conversation.
- **Custom Claude command (manual flags)** — enter arguments only, such as `--help`.
- **Drop to bash shell** — use the terminal without starting Claude.
- **Exit** — ends the terminal session.

From the shell, run `claude` for an interactive session, `claude --help` for CLI options, or `ha --help` for Home Assistant management commands.

## Network and security

Use the sidebar panel or **OPEN WEB UI** through Home Assistant ingress, protected by your Home Assistant login. No host port is required.

The optional `7681/tcp` host port in **Network** settings is disabled by default. Enabling it exposes an **unauthenticated root terminal**, including your HA configuration and the add-on's manager-level Supervisor access; Claude sign-in does not protect the terminal. Existing installations keep saved ports across updates: clear any `7681/tcp` host port, save, and restart to disable direct access.

Claude can read and change your live HA configuration and use HA APIs. Back up before major edits, review proposed changes, and avoid putting secrets into prompts unnecessarily.

## Persistent data

- `/config` is your **live Home Assistant configuration**, mounted read/write, and the terminal's working directory.
- `/data/home` is the persistent terminal home. Claude credentials, settings, and conversation data live under `/data/home/.claude`; onboarding and global configuration live in `/data/home/.claude.json`.
- Claude's runtime launcher and native updates use `/data/home/.local`. Authentication and installed updates survive add-on restarts through the `/data` volume.

## Home Assistant examples

Ask these in an interactive Claude session:

- “Review my motion-light automation and suggest how to limit it to after sunset.”
- “Explain the YAML validation error in my configuration and propose a minimal fix.”
- “Help me draft a template sensor that averages these temperature entities.”
- “Read this integration error and suggest diagnostic steps before changing anything.”

Review edits before applying them. From the shell, `ha core check` validates HA configuration; use `ha core logs` to inspect Core errors.

## Troubleshooting

- **Terminal will not load:** check that the add-on is running and inspect its **Logs** tab. Use ingress; a host port is unnecessary.
- **Sign-in or API errors:** follow Claude's login prompts and check internet connectivity. From the shell, `claude auth --help` shows the installed CLI's authentication commands. Authentication belongs to Claude, not a separate add-on helper.
- **Unexpected permission mode:** confirm the option, save, and restart; inspect the add-on logs for the selected mode or a settings-write warning. Startup reapplies the configured default.
- **Claude version does not change:** check `auto_update_claude` and the startup log. The native updater runs in the background; an update takes effect on the next Claude launch.

For add-on problems, use the [repository issue tracker](https://github.com/incognitojam/home-assistant-addons/issues). Include relevant logs without credentials or tokens.
