# AGENTS.md

This repository is a Home Assistant add-on repository (`repository.yaml`) with two add-ons. Each serves a ttyd web terminal through Home Assistant ingress on port 7681 and starts a coding agent in `/config`:

- `claude-terminal/` runs Anthropic's Claude Code, installed with the native installer.
- `codex-terminal/` runs OpenAI's Codex CLI, installed from npm.

## Layout

Both add-ons have `config.yaml` (Supervisor manifest, options and defaults), `Dockerfile`, `run.sh` (startup), `DOCS.md` (the documentation Home Assistant shows), `README.md`, `CHANGELOG.md` and `translations/en.yaml` (option names and descriptions).

- `claude-terminal/`
  - `build.yaml` lists the per-arch base images.
  - `scripts/` contains the session picker and the build-time ttyd index patch that adds mobile input hints.
  - `tests/` contains the Playwright end-to-end tests.
  - The options are `auto_launch_claude`, `auto_update_claude` and `permission_mode`.
- `codex-terminal/`
  - The `Dockerfile` pins its own multi-arch base image, the Codex release (`CODEX_RELEASE`) and `BUILD_VERSION`.
  - `codex-auth-launcher.sh` is the login menu shown before Codex starts.
  - `codex-defaults.toml` becomes `/etc/codex/config.toml`.
  - `reset-codex-version.sh` removes a user-installed Codex override.
  - `tests/` contains the daemon and approval-default checks that CI runs.
  - It has no options.

At runtime, `/config` is the user's live Home Assistant configuration (read-write) and `/data` is the add-on's private persistent storage. `HOME` is `/data/home`, and everything outside `/data` and `/config` is reset when the add-on restarts or updates. Both add-ons have `hassio_role: manager` and the pinned `ha` CLI (`CLI_VERSION`).

Each add-on ships a context file for the agent that runs inside it. These files are written for end users' Home Assistant sessions, so don't follow them as instructions for working on this repository. One example is `codex-terminal/AGENTS.md`, which is installed as `/config/AGENTS.md`.

## Build and run locally

Use Docker; on macOS, OrbStack provides `docker`. For claude-terminal, build with the base image for your host's architecture (`aarch64-base` on Apple Silicon, `amd64-base` on Intel/AMD) so it runs natively:

```bash
docker build --build-arg BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.22 -t local/claude-terminal:test ./claude-terminal
docker run -d --name claude-dev -p 127.0.0.1:7681:7681 \
  -e AUTO_LAUNCH_CLAUDE=false -e AUTO_UPDATE_CLAUDE=false -e PERMISSION_MODE=default \
  -v "$PWD/config/claude-data:/data" -v "$PWD/config/ha:/config" local/claude-terminal:test

docker build -t local/codex-terminal:test ./codex-terminal   # ignores BUILD_FROM
docker run -d --name codex-dev -p 127.0.0.1:7682:7681 \
  -v "$PWD/config/codex-data:/data" -v "$PWD/config/ha:/config" local/codex-terminal:test
```

`config/` is git-ignored. Open http://localhost:7681 and check `docker logs <name>`. There is no Supervisor locally, so `ha` commands, `http://supervisor/...` calls and `bashio::config` all fail. claude-terminal reads its options through `get_addon_option` in `run.sh`: an environment override (`AUTO_LAUNCH_CLAUDE=true|false`, `AUTO_UPDATE_CLAUDE=true|false`, `PERMISSION_MODE=default|acceptEdits|auto|plan`) takes precedence, otherwise the default applies. If an override is unset, the log shows harmless "Failed to get addon config" errors.

To lint the Dockerfiles, run the same hadolint version as CI:

```bash
docker run --rm -i ghcr.io/hadolint/hadolint:v2.15.1 < claude-terminal/Dockerfile
```

## End-to-end tests (claude-terminal)

The Playwright tests in `claude-terminal/tests/` start their own container from a built image, on a free port, and remove it afterwards. They drive the web terminal directly, through an ingress-like proxy under `/api/hassio_ingress/<token>/`, and under phone emulation.

```bash
npm --prefix claude-terminal/tests ci
npm --prefix claude-terminal/tests run install-browsers   # Chromium + WebKit, once
IMAGE=local/claude-terminal:test npm --prefix claude-terminal/tests test
# Skip the test that needs to reach Anthropic's API
IMAGE=local/claude-terminal:test npm --prefix claude-terminal/tests test -- --grep-invert @network
```

On failure, `claude-terminal/tests/test-results/` holds the terminal buffer, container logs, a screenshot and a trace (`npx playwright show-trace <trace.zip>`). The tests read the screen through ttyd's `window.term` and poll it with timeouts. Select session picker entries by label, not by number.

## CI

`.github/workflows/build.yml` runs on pull requests, on pushes to `main` and on manual dispatch.

- `check` looks up whether `ghcr.io/incognitojam/{arch}-<add-on>:<version>` exists for the version in each `config.yaml`, using `.github/scripts/ghcr-tag-state.sh`, and returns separate missing-tag lists for each add-on.
- `claude` and `codex` each call `validate-addon.yml`. Its `build` matrix builds and tests both amd64 and aarch64 natively, and its `hadolint` job lints that add-on's Dockerfile with hadolint v2.15.1. Codex tests run inside the image; Claude e2e tests include a separate `@network` step and failure artifacts. An explicit validation gate requires both architectures and lint to succeed and rejects failed, skipped or canceled jobs.
- `publish_claude` and `publish_codex` each call `publish-addon.yml` only on `main`, after `check` and their own add-on validation succeed and there are missing tags. One add-on's failure or canceled validation does not block the other's release. Canceling the whole workflow prevents new publish jobs; main runs are not automatically canceled by newer runs, and build matrices disable fail-fast cancellation.
- Publishing loads the exact tested image artifact and never rebuilds it. Each image has a publish concurrency group, and the registry is checked again before pushing so existing version tags are never overwritten. Only publish jobs receive `packages: write`; pull requests cannot publish.
- `CI` runs on `ubuntu-slim` and remains the required check. It requires `check` and both add-on validations to succeed on every run, even when one add-on can publish independently on `main`. It does not wait for publishing.

## Conventions

- Commit and PR titles use Scoped Commits with the add-on as the scope, for example `claude-terminal: <description>` or `codex-terminal: <description>`. Repository-wide changes use `docs:` or `ci:`.
- A release bumps `version` in the add-on's `config.yaml` and adds a matching section to its `CHANGELOG.md`. Merging a version bump to `main` publishes that version's images, and Home Assistant pulls `image:<version>`. Releases are what ship: changes merged without a version bump don't reach users, and one release can cover several changes. Never reuse a version: its images are already published. For codex-terminal, also keep `ARG BUILD_VERSION` in the `Dockerfile` in step with the version.
- Add-on scripts start with `#!/usr/bin/with-contenv bashio` and report through `bashio::log.*`.
- Indent shell with 4 spaces and YAML with 2 spaces.
- Put option defaults in `config.yaml`, and their user-facing names and descriptions in `translations/en.yaml`.

## Gotchas

- `config.yaml`'s `image:` key makes Supervisor pull a prebuilt image; without it, Supervisor builds from source. Local Docker builds still work for development.
- After a release merges, publishing takes a few minutes. Users who update before the image exists get a pull error until publishing finishes.
- `bashio::config` reads options from the Supervisor API, not `/data/options.json`. Without a Supervisor, or if the API call fails, it returns nothing, which is why `get_addon_option` exists.
- Claude Code's native install: the image bakes a binary behind `/root/.local/bin/claude`. On fresh installs or the exact legacy fallback link to that path, `run.sh` copies the resolved bundled executable once to `/data/.local/share/claude/versions/<version>` and links `/data/home/.local/bin/claude` directly to it. Claude treats a chained launcher through `/root` as custom and will download updates without activating them. The direct persistent link lets Claude's native updater repoint it to downloaded versions, which survive restarts. Existing native-managed and custom launchers are preserved. Migration starts with the bundled version rather than guessing a release channel from cached downloads. `auto_update_claude` toggles `DISABLE_AUTOUPDATER`. Don't run `https://claude.ai/install.sh` at startup: it re-downloads the full binary.
- On Alpine (musl), Claude Code needs `USE_BUILTIN_RIPGREP=0` and the system `ripgrep` package.
- Don't install a `$BROWSER` or `xdg-open` shim in claude-terminal. If Claude finds a browser opener, it uses its localhost OAuth callback, which the user's remote browser can't reach. Without one, it shows a login URL and asks the user to paste back the code.
- codex-terminal prefers a Codex the user installed into `/data/npm` (`npm install -g`), as long as it passes `codex --version`. Otherwise it uses the bundled `/usr/local/bin/codex`.
- Each ttyd connection attaches to the shared tmux session through `scripts/attach-session.sh` and `/opt/tmux.conf`; tests kill the tmux server between tests.
