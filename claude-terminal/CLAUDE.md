# Home Assistant Claude Terminal Environment

This document provides context for Claude Code running inside a Home Assistant add-on container.

## Environment Overview

You are running inside the **Claude Terminal** add-on for Home Assistant. This is a specialized Alpine Linux container with:
- Full access to Home Assistant APIs and CLI tools
- Persistent storage in `/config` and `/data`
- Manager-level permissions for Home Assistant operations
- Web-based terminal interface via ttyd

## Current Environment

### System Information
- **OS**: Alpine Linux (Home Assistant base image)
- **Shell**: bash with bashio library
- **Architecture**: Multi-arch support (amd64, aarch64, armv7)
- **Container Runtime**: Docker/Podman managed by Home Assistant Supervisor

### Environment Variables
```bash
HOME=/data/home                          # User home directory
ANTHROPIC_CONFIG_DIR=/data/.config/claude  # Claude credentials
XDG_CONFIG_HOME=/data/.config            # Configuration files
XDG_CACHE_HOME=/data/.cache              # Cache directory
XDG_STATE_HOME=/data/.local/state        # State files
```

### Key Directories

#### `/config` - Home Assistant Configuration
- **Purpose**: Main Home Assistant configuration directory
- **Access**: Read/Write
- **Contents**:
  - `configuration.yaml` - Main HA config
  - `automations.yaml` - Automation definitions
  - `scripts.yaml` - Script definitions
  - `secrets.yaml` - Sensitive values
  - Custom component directories
  - Integration-specific configs
- **Persistence**: Survives container restarts and updates
- **Backups**: Included in Home Assistant backups

#### `/data` - Add-on Persistent Storage
- **Purpose**: Add-on specific data storage
- **Access**: Read/Write
- **Contents**:
  - `.config/claude/` - Claude authentication files
  - `.cache/` - Temporary cache files
  - `.local/` - Application state
- **Persistence**: Survives container restarts
- **Backups**: May be included depending on HA backup settings

#### `/opt/scripts` - Add-on Helper Scripts
- `claude-session-picker.sh` - Interactive session picker
- `claude-auth-helper.sh` - Authentication management
- `health-check.sh` - System diagnostics

## Available Commands

### Home Assistant CLI (`ha`)
Full-featured CLI for Home Assistant management with manager-level permissions.

The `ha` command provides access to all Home Assistant Supervisor functions including core management, add-ons, backups, host system, DNS, network, and more.

**Usage:**
```bash
ha --help               # List all available commands
ha <command> --help     # Get help for specific command
```

Use `ha --help` to discover all available commands and their usage.

### bashio - Home Assistant Shell Functions
Helper functions for add-on development and debugging.

```bash
bashio::log.info "message"      # Log info message
bashio::log.warning "message"   # Log warning
bashio::log.error "message"     # Log error
bashio::config 'key' 'default'  # Get addon config value
bashio::addon.hostname          # Get addon hostname
bashio::api.supervisor          # Access supervisor API
```

### Standard Linux Tools
```bash
curl          # HTTP requests
jq            # JSON processing
nano          # Text editor
bash          # Shell
ps            # Process listing
grep          # Pattern searching
find          # File searching
```

## Common Tasks

### Configuration File Management
Key configuration files are located in `/config`:
- `configuration.yaml` - Main Home Assistant configuration
- `automations.yaml` - Automation definitions
- `scripts.yaml` - Script definitions
- `secrets.yaml` - Sensitive values (API keys, passwords)
- `custom_components/` - Custom integrations

### Best Practice Workflow
1. **Before making changes**: Create a backup using `ha backups`
2. **Edit files**: Use `nano` or other text editor
3. **Validate**: Use `ha core check` to validate configuration
4. **Apply changes**: Restart Home Assistant or reload specific components
5. **Monitor**: Check logs for errors after changes

### Working with the ha CLI
Use `ha --help` to discover all available commands. Common command groups include:
- `ha core` - Core Home Assistant management
- `ha addons` - Add-on management
- `ha backups` - Backup operations
- `ha supervisor` - Supervisor operations
- `ha host` - Host system management

### Custom Components and Integrations
Custom components are stored in `/config/custom_components/`. Many users install HACS (Home Assistant Community Store) for managing custom integrations.

## Home Assistant API Access

### Supervisor API
Available via localhost with automatic authentication:
```bash
curl -X GET http://supervisor/core/info
curl -X GET http://supervisor/addons
curl -X GET http://supervisor/backups
```

### Home Assistant Core API
```bash
# Get states
curl -X GET http://supervisor/core/api/states

# Call a service
curl -X POST http://supervisor/core/api/services/light/turn_on \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.living_room"}'
```

## File Editing Best Practices

### Before Making Changes
1. **Create a backup** using `ha backups` commands
2. **Validate current config** using `ha core check`
3. **Review existing files**: Check current structure before modifying

### After Making Changes
1. **Validate configuration** using `ha core check`
2. **Check for errors**: Review output carefully
3. **Test changes**: Restart affected services
4. **Monitor logs**: Use `ha core logs` to catch issues

### Common Configuration Files
```
/config/configuration.yaml    # Main configuration
/config/automations.yaml      # Automations
/config/scripts.yaml          # Scripts
/config/scenes.yaml           # Scenes
/config/groups.yaml           # Groups
/config/customize.yaml        # Entity customization
/config/secrets.yaml          # Sensitive data (API keys, passwords)
```

## Troubleshooting

### Check Container Health
Use the `ha` CLI to:
- View addon logs with `ha addons logs`
- Check system resources with `ha host info`
- View supervisor logs with `ha supervisor logs`

### Configuration Validation Errors
Always validate configuration using `ha core check` before restarting.

Common YAML issues:
- Indentation (use 2 spaces, not tabs)
- Missing quotes around special characters
- Invalid entity IDs or service names
- Incorrect file paths

### Authentication Issues with Claude
```bash
# Check credential files
ls -la /data/.config/claude/

# Re-authenticate if needed
claude-auth-helper.sh

# View credential locations
echo $ANTHROPIC_CONFIG_DIR
```

### Network and Connectivity
- Test internet connectivity with `curl`
- Check DNS resolution with `nslookup`
- View network info with `ha network info`

## Security Considerations

### Sensitive Files
- **Never commit secrets**: Use `/config/secrets.yaml` for sensitive data
- **Protect API tokens**: Store in secrets, reference with `!secret name`
- **Backup security**: Backups contain ALL config including secrets

### File Permissions
```bash
# Credential files should be restricted
chmod 600 /data/.config/claude/*

# Configuration files typically 644
chmod 644 /config/configuration.yaml
```

### API Access
- This addon has **manager-level** access to Home Assistant
- Can control all aspects of the system
- Use caution when making automated changes
- Always backup before major modifications

## Limitations and Constraints

### System Limitations
- **No sudo**: Running in unprivileged container
- **No apt/apt-get**: Alpine Linux uses `apk` (not available at runtime)
- **Read-only filesystem**: Most of the container filesystem is read-only
- **No systemd**: Uses s6-overlay for service management

### Home Assistant Constraints
- **Restart required**: Some config changes need `ha core restart`
- **Reload services**: Some changes can be reloaded without restart
- **Supervisor managed**: Container lifecycle controlled by Supervisor
- **Resource limits**: Subject to system resource constraints

### Best Practices
- Always validate configuration before applying changes
- Create backups before major modifications
- Test changes incrementally
- Monitor logs after changes
- Use Home Assistant's built-in tools when possible

## Getting Help

### Resources
- **Home Assistant Docs**: https://www.home-assistant.io/docs/
- **Home Assistant Community**: https://community.home-assistant.io/
- **Claude Code Docs**: https://github.com/anthropics/claude-code
- **Add-on Repository**: https://github.com/incognitojam/home-assistant-addons

### Finding Information
Use `ha --help` to explore all available commands. The CLI provides access to system info, logs, and diagnostic tools.

### Debugging
Enable debug logging in `configuration.yaml`:
```yaml
logger:
  default: info
  logs:
    homeassistant.components.automation: debug
```

After editing, validate with `ha core check`, then restart and monitor logs.

## Quick Reference

### Essential Tools
- **`ha` CLI**: Use `ha --help` to explore all Home Assistant management commands
- **`nano`**: Edit configuration files
- **`curl`**: Make HTTP requests and test APIs
- **`bashio::*`**: Home Assistant shell functions for logging and config access

### Important Paths
| Purpose | Path |
|---------|------|
| HA Config | `/config/configuration.yaml` |
| Automations | `/config/automations.yaml` |
| Secrets | `/config/secrets.yaml` |
| Custom Components | `/config/custom_components/` |
| Claude Credentials | `/data/.config/claude/` |
| Add-on Scripts | `/opt/scripts/` |

---

**Welcome to Home Assistant Claude Terminal!** You have powerful tools at your disposal. Use them wisely, always backup before major changes, and enjoy the integration of Claude AI with your Home Assistant system.
