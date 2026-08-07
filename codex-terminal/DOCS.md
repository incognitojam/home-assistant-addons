# Codex for Home Assistant

Codex for Home Assistant provides a browser terminal that launches the OpenAI Codex CLI inside Home Assistant.

## First Run

Open the app from the Home Assistant sidebar. Codex starts in `/config`, so it can inspect and edit your Home Assistant configuration files.

On first launch, the app checks whether Codex is already authenticated. If not, it shows a terminal picker with two options:

- Sign in with Device Code
- Provide your own API key

The browser-based ChatGPT sign-in option is intentionally not shown because it does not work reliably from the app's remote terminal environment. After authentication succeeds, Codex starts automatically.

## Persistence

Codex state is stored in `/data/.codex`, including authentication, configuration, logs, sessions, plugins, and skills. Home Assistant includes `/data` in app backups unless you exclude it in a future app release.

The shell home directory and XDG directories are also stored under `/data` so command history and CLI state survive restarts.

The app includes a pinned, image-owned Codex version as a reliable fallback. Opt-in npm updates and their package metadata are installed under `/data/npm`, so they take precedence over the bundled version and survive app image upgrades.

## Codex Updates

Codex does not update automatically during app startup. Codex provides its own self-update command, which detects the npm installation and installs the latest release into the persistent npm prefix.

From the Codex terminal, prefix the command with `!` to run it in the local shell:

```text
!codex update
```

Approve access to `/data/npm` if prompted. After the update succeeds, exit and reopen Codex to use the new version. From a regular container shell, the equivalent command is `codex update` without the `!` prefix.

To remove the persistent override and return to the version bundled with the current app image, run:

```text
!reset-codex-version
```

Then exit and reopen Codex. Node.js and npm are included in the app and use `/data/npm` as the global npm prefix. Other npm-installed CLI tools in the app can use the same persistent location without mixing executable packages into Codex state. The native updater is documented in the [official Codex developer commands reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli#codex-update).

## Home Assistant Access

The app starts in `/config` with write access to the Home Assistant configuration directory.

The Home Assistant CLI is installed as `ha`. The app also has Supervisor API and Home Assistant Core API access so CLI commands can interact with the local Home Assistant instance.

## Codex Instructions

The container includes a bundled `AGENTS.md` with Home Assistant-specific context, important paths, available tools, and safe editing expectations. On launch, the app installs it to `/config/AGENTS.md` so Codex loads it as project guidance for the Home Assistant configuration directory.

If `/config/AGENTS.md` already exists and has local edits, the app leaves it unchanged. Future bundled updates replace the file only when the existing file still matches a previously installed bundled copy.

## Terminal

The web terminal is served by `ttyd` and is available through Home Assistant ingress. The direct host port is disabled by default because ingress is the normal authenticated entry point. For local development, you can explicitly map container port `7681/tcp` to a host port in the app network settings.

## Architectures

This app supports:

- `amd64`
- `aarch64`

Other architectures are not included because the Codex npm package supports Linux x64 and arm64 binaries.

## Security Notes

Codex can edit files in `/config` and can run commands inside this app container. Only run tasks you trust and review changes before restarting Home Assistant.

Codex credentials are stored in the app's persistent `/data/.codex` directory and are included in Home Assistant backups.

Do not expose the direct web terminal port on untrusted networks. When direct port mapping is enabled, requests go to `ttyd` without Home Assistant ingress checks.
