# Changelog

## 1.7.5

### 🐛 Bug Fixes
- **Fixed Claude Code startup on current native releases**: Updated the Home Assistant base image from Alpine 3.19 to 3.22 so Claude Code's musl binary can resolve `statx` after install or auto-update.

## 1.7.4

### 📚 Documentation
- **Removed unnecessary workaround for Claude Code Bash tool bug**: The in-container `CLAUDE.md` no longer documents a pipe workaround now that the underlying bug is fixed.

## 1.7.3

### 🛠️ Improvements
- **Mobile terminal input hints**: the web terminal now asks mobile browsers not to autocomplete, autocorrect, autocapitalize, or spellcheck the hidden xterm input. Some keyboards may still ignore these browser hints.

## 1.7.2

### 🛠️ Improvements
- **New sidebar icon**: swapped out the old curly braces for something which felt closer to Claude Code! 🤖

## 1.7.1

### 🐛 Bug Fixes
- **Fixed "configuration not valid" error when upgrading to 1.7.0**: Existing installs failed to start because the new `permission_mode` option had no valid default. Upgrading now applies the `auto` default automatically — no config reset needed.

## 1.7.0

### ✨ New Features
- **Configurable default permission mode**: New `permission_mode` option controls how Claude handles permission prompts at the start of every session. Defaults to **`auto`**, which lets an AI classifier approve or deny each action. Other choices are `acceptEdits` (auto-accept file edits), `default` (prompt before risky actions), and `plan` (read-only). It is applied via Claude's `permissions.defaultMode` setting so it covers all launch paths, and you can still cycle modes mid-session with **Shift+Tab**. Auto mode availability depends on your Anthropic plan/model; when unavailable, Claude falls back to prompting.

## 1.6.2

### 🛠️ Improvements
- **Much faster terminal startup**: Stopped re-running the native installer (`claude.ai/install.sh`) on every terminal launch. That script always re-downloaded the full ~215MB Claude Code binary regardless of whether an update was actually available, adding a large download + reinstall to every single open.
- **`auto_update_claude` now drives the native background updater**: Claude Code's built-in auto-updater already keeps the install current in the background and applies new versions on the next launch (downloads to persistent `/data`, so it survives restarts). When the option is disabled, the add-on now sets `DISABLE_AUTOUPDATER=1` instead of pinning the version via reinstall.

## 1.6.1

### 🐛 Bug Fixes
- **Fixed auto-update reverting on restart**: Container restarts were overwriting the updated Claude binary with the older build-time version. The symlink at `$HOME/.local/bin/claude` is now only created as a fallback when no existing binary is present, preserving auto-updater installations across restarts.

## 1.6.0

### 🐛 Bug Fixes
- **Fixed auto-update not working**: Auto-update was silently failing, leaving users stuck on old Claude Code versions. Replaced broken `claude update` command with the official native installer (`claude.ai/install.sh`) which reliably fetches the latest version on each startup

## 1.5.12

### 🐛 Bug Fixes
- **Fixed ttyd installation**: Install ttyd at build time from Alpine edge repo (fixes libwebsockets compatibility in Alpine 3.19)

### 🛠️ Improvements
- **Faster startup**: ttyd and jq now installed at build time instead of runtime

## 1.5.11

### 🐛 Bug Fixes
- **Fixed install method config**: Run `claude install` during build to set config to native

## 1.5.10

### 🐛 Bug Fixes
- **Fixed PATH check**: Add `$HOME/.local/bin` to PATH (not just symlink) to satisfy Claude's PATH validation

## 1.5.9

### 🐛 Bug Fixes
- **Fixed native install detection**: Create symlink at `$HOME/.local/bin/claude` so Claude finds itself correctly

## 1.5.8

### 🐛 Bug Fixes
- **Fixed PATH warning**: Ensure `~/.local/bin` is in PATH for spawned shells

## 1.5.7

### 🐛 Bug Fixes
- **Fixed claude invocation**: Run `claude` directly instead of through Node.js (`node $(which claude)`)
- **Fixed auto-update**: Use native `claude update` command instead of npm

## 1.5.6

### 🐛 Bug Fixes
- **Fixed native installer build**: Use correct path `~/.local/bin/claude` for native installer

## 1.5.5

### 🔄 Changes
- **Native Claude Code installer**: Switched from npm to official native installer (`curl -fsSL https://claude.ai/install.sh | bash`)
  - Required for latest Claude Code features (faster code diffs, improved performance)
  - Uses official signed binaries from Anthropic
  - Includes built-in auto-update capability
  - Simplified installation without npm retry logic

## 1.5.4

### ✨ New Features
- **Added git**: Git is now available in the container for version control operations

### 🛠️ Improvements
- **Alpine musl compatibility**: Added required dependencies for Claude Code native binaries
  - Added `libgcc`, `libstdc++`, and `ripgrep` packages
  - Set `USE_BUILTIN_RIPGREP=0` environment variable for proper ripgrep integration

## 1.5.3

### 🔄 Dependencies
- **Updated Home Assistant CLI**: Bumped from 4.42.0 to 4.43.0, which includes new `docker migrate-storage-driver` command

## 1.5.2

### 🛠️ Improvements
- **Cleaner update output**: Use npm flags (`--loglevel=error --no-fund --no-audit`) instead of suppressing all output, so errors are still visible if update fails

## 1.5.1

### 🛠️ Improvements
- **Cleaner terminal startup**: Removed welcome messages for faster, cleaner launch
- **Hidden update output**: npm install output is now suppressed during auto-update

## 1.5.0

### ✨ New Features
- **Auto-update Claude Code CLI**: Claude Code is now automatically updated to the latest version when opening the terminal
  - Ensures users always have the latest features and fixes without rebuilding the add-on
  - New `auto_update_claude` configuration option (enabled by default)
  - Updates happen before Claude launches, so built-in self-update restarts are no longer needed

## 1.4.2

### 📚 Documentation
- **Documented Bash tool pipe limitation**: Added critical warning and workarounds for environment variable stripping when using pipes (`|`) in Claude Code Bash tool commands. This affects `SUPERVISOR_TOKEN` and other environment variables, causing 401 auth errors when piping API responses to `jq`.

## 1.4.1

### 📚 Documentation
- **Improved container authentication documentation** (PR #11): Clarified in-container authentication instructions in CLAUDE.md with better guidance for users.

## 1.4.0

### ✨ New Features
- **Home Assistant CLI Access** (PR #1): Added direct access to Home Assistant CLI tools, including mounting `/usr/bin/ha` binary and architecture auto-detection for CLI download.

### 🏷️ Rebranding
- **Claude Terminal → Claude Code**: Updated naming throughout to align with official Anthropic branding.

### 🐛 Bug Fixes
- Fixed CLAUDE.md reference to use correct `ha addons logs` command syntax.

## 1.3.2

### 🐛 Bug Fixes
- **Improved installation reliability** (#16): Enhanced resilience for network issues during installation
  - Added retry logic (3 attempts) for npm package installation
  - Configured npm with longer timeouts for slow/unstable connections
  - Explicitly set npm registry to avoid DNS resolution issues
  - Added 10-second delay between retry attempts

### 🛠️ Improvements
- **Enhanced network diagnostics**: Better troubleshooting for connection issues
  - Added DNS resolution checks to identify network configuration problems
  - Check connectivity to GitHub Container Registry (ghcr.io)
  - Extended connection timeouts for virtualized environments
  - More detailed error messages with specific solutions
- **Better virtualization support**: Improved guidance for VirtualBox and Proxmox users
  - Enhanced VirtualBox detection with detailed configuration requirements
  - Added Proxmox/QEMU environment detection
  - Specific network adapter recommendations for VM installations
  - Clear guidance on minimum resource requirements (2GB RAM, 8GB disk)

## 1.3.1

### 🐛 Critical Fix
- **Restored config directory access**: Fixed regression where add-on couldn't access Home Assistant configuration files
  - Re-added `config:rw` volume mapping that was accidentally removed in 1.2.0
  - Users can now properly access and edit their configuration files again

## 1.3.0

### ✨ New Features
- **Full Home Assistant API Access**: Enabled complete API access for automations and entity control
  - Added `hassio_api`, `homeassistant_api`, and `auth_api` permissions
  - Set `hassio_role` to 'manager' for full Supervisor access
  - Created comprehensive API examples script (`ha-api-examples.sh`)
  - Includes Supervisor API, Core API, and WebSocket examples
  - Python and bash code examples for entity control

### 🐛 Bug Fixes
- **Fixed authentication paste issues** (#14): Added authentication helper for clipboard problems
  - New authentication helper script with multiple input methods
  - Manual code entry option when clipboard paste fails
  - File-based authentication via `/config/auth-code.txt`
  - Integrated into session picker as menu option

### 🛠️ Improvements
- **Enhanced diagnostics** (#16): Added comprehensive health check system
  - System resource monitoring (memory, disk space)
  - Permission and dependency validation
  - VirtualBox-specific troubleshooting guidance
  - Automatic health check on startup
  - Improved error handling with strict mode

## 1.2.1

### 🔧 Internal Changes
- Fixed YAML formatting issues for better compatibility
- Added document start marker and fixed line lengths

## 1.2.0

### 🔒 Authentication Persistence Fix (PR #15)
- **Fixed OAuth token persistence**: Tokens now survive container restarts
  - Switched from `/config` to `/data` directory (Home Assistant best practice)
  - Implemented XDG Base Directory specification compliance
  - Added automatic migration for existing authentication files
  - Removed complex symlink/monitoring systems for simplicity
  - Maintains full backward compatibility

## 1.1.4

### 🧹 Maintenance
- **Cleaned up repository**: Removed erroneously committed test files (thanks @lox!)
- **Improved codebase hygiene**: Cleared unnecessary temporary and test configuration files

## 1.1.3

### 🐛 Bug Fixes
- **Fixed session picker input capture**: Resolved issue with ttyd intercepting stdin, preventing proper user input
- **Improved terminal interaction**: Session picker now correctly captures user choices in web terminal environment

## 1.1.2

### 🐛 Bug Fixes
- **Fixed session picker input handling**: Improved compatibility with ttyd web terminal environment
- **Enhanced input processing**: Better handling of user input with whitespace trimming
- **Improved error messages**: Added debugging output showing actual invalid input values
- **Better terminal compatibility**: Replaced `echo -n` with `printf` for web terminals

## 1.1.1

### 🐛 Bug Fixes  
- **Fixed session picker not found**: Moved scripts from `/config/scripts/` to `/opt/scripts/` to avoid volume mapping conflicts
- **Fixed authentication persistence**: Improved credential directory setup with proper symlink recreation
- **Enhanced credential management**: Added proper file permissions (600) and logging for debugging
- **Resolved volume mapping issues**: Scripts now persist correctly without being overwritten

## 1.1.0

### ✨ New Features
- **Interactive Session Picker**: New menu-driven interface for choosing Claude session types
  - 🆕 New interactive session (default)
  - ⏩ Continue most recent conversation (-c)
  - 📋 Resume from conversation list (-r) 
  - ⚙️ Custom Claude command with manual flags
  - 🐚 Drop to bash shell
  - ❌ Exit option
- **Configurable auto-launch**: New `auto_launch_claude` setting (default: true for backward compatibility)
- **Added nano text editor**: Enables `/memory` functionality and general text editing

### 🛠️ Architecture Changes
- **Simplified credential management**: Removed complex modular credential system
- **Streamlined startup process**: Eliminated problematic background services
- **Cleaner configuration**: Reduced complexity while maintaining functionality
- **Improved reliability**: Removed sources of startup failures from missing script dependencies

### 🔧 Improvements
- **Better startup logging**: More informative messages about configuration and setup
- **Enhanced backward compatibility**: Existing users see no change in behavior by default
- **Improved error handling**: Better fallback behavior when optional components are missing

## 1.0.2

### 🔒 Security Fixes
- **CRITICAL**: Fixed dangerous filesystem operations that could delete system files
- Limited credential searches to safe directories only (`/root`, `/home`, `/tmp`, `/config`)
- Replaced unsafe `find /` commands with targeted directory searches
- Added proper exclusions and safety checks in cleanup scripts

### 🐛 Bug Fixes
- **Fixed architecture mismatch**: Added missing `armv7` support to match build configuration
- **Fixed NPM package installation**: Pinned Claude Code package version for reliable builds
- **Fixed permission conflicts**: Standardized credential file permissions (600) across all scripts
- **Fixed race conditions**: Added proper startup delays for credential management service
- **Fixed script fallbacks**: Implemented embedded scripts when modules aren't found

### 🛠️ Improvements
- Added comprehensive error handling for all critical operations
- Improved build reliability with better package management
- Enhanced credential management with consistent permission handling
- Added proper validation for script copying and execution
- Improved startup logging for better debugging

### 🧪 Development
- Updated development environment to use Podman instead of Docker
- Added proper build arguments for local testing
- Created comprehensive testing framework with Nix development shell
- Added container policy configuration for rootless operation

## 1.0.0

- First stable release of Claude Terminal add-on:
  - Web-based terminal interface using ttyd
  - Pre-installed Claude Code CLI
  - User-friendly interface with clean welcome message
  - Simple claude-logout command for authentication
  - Direct access to Home Assistant configuration
  - OAuth authentication with Anthropic account
  - Auto-launches Claude in interactive mode
