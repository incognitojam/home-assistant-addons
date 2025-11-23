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

**Core Commands:**
```bash
ha core info              # Show Home Assistant Core information
ha core logs              # View Home Assistant logs
ha core restart           # Restart Home Assistant
ha core update            # Update Home Assistant
ha core check             # Check configuration
```

**Add-on Management:**
```bash
ha addons                 # List all addons
ha addons info <addon>    # Get addon details
ha addons logs <addon>    # View addon logs
ha addons start <addon>   # Start an addon
ha addons stop <addon>    # Stop an addon
ha addons restart <addon> # Restart an addon
ha addons update <addon>  # Update an addon
```

**Backup Operations:**
```bash
ha backups               # List backups
ha backups new           # Create new backup
ha backups restore       # Restore from backup
ha backups reload        # Reload backup list
```

**System Management:**
```bash
ha supervisor info       # Supervisor information
ha supervisor logs       # Supervisor logs
ha supervisor update     # Update supervisor
ha host info            # Host system info
ha host reboot          # Reboot host
ha dns info             # DNS information
ha network info         # Network configuration
```

**Help and Documentation:**
```bash
ha --help               # General help
ha <command> --help     # Command-specific help
```

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

### Viewing Home Assistant Logs
```bash
# View live logs
ha core logs -f

# View specific addon logs
ha addons logs claude_terminal -f

# Check supervisor logs
ha supervisor logs
```

### Checking System Status
```bash
# Core info
ha core info

# Supervisor status
ha supervisor info

# Host system info
ha host info

# List installed addons
ha addons
```

### Configuration Management
```bash
# Check configuration validity
ha core check

# Edit main configuration
nano /config/configuration.yaml

# After config changes, restart HA
ha core restart
```

### Backup and Restore
```bash
# List existing backups
ha backups

# Create full backup
ha backups new --name "Before Changes"

# Create partial backup (config only)
ha backups new --name "Config Only" --homeassistant

# Restore from backup
ha backups restore <slug>
```

### Add-on Management
```bash
# List all addons with status
ha addons

# View addon details
ha addons info addon_slug

# Check addon logs
ha addons logs addon_slug

# Restart an addon
ha addons restart addon_slug
```

### Working with Automations
```bash
# Edit automations
nano /config/automations.yaml

# Validate configuration
ha core check

# Reload automations (faster than full restart)
# Use Developer Tools in HA UI, or:
curl -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  http://supervisor/core/api/services/automation/reload
```

### Custom Components
```bash
# Custom components location
ls /config/custom_components/

# View component logs
ha core logs | grep -i "custom_component_name"
```

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
1. **Create a backup**: `ha backups new --name "Before editing"`
2. **Validate current config**: `ha core check`
3. **Review existing files**: Check current structure before modifying

### After Making Changes
1. **Validate configuration**: `ha core check`
2. **Check for errors**: Review output carefully
3. **Test changes**: Restart affected services
4. **Monitor logs**: `ha core logs -f` to catch issues

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

## Integrations and Custom Components

### Viewing Integrations
```bash
# Check loaded integrations in logs
ha core logs | grep -i "setup of domain"

# List custom components
ls -la /config/custom_components/
```

### Installing Custom Components
Many users use HACS (Home Assistant Community Store):
```bash
# HACS is typically in custom_components
ls /config/custom_components/hacs/
```

## Troubleshooting

### Check Container Health
```bash
# View addon logs
ha addons logs claude_terminal

# Check system resources
ha host info

# View supervisor logs for system-level issues
ha supervisor logs
```

### Configuration Validation Errors
```bash
# Always validate before restart
ha core check

# Common issues:
# - YAML indentation (use 2 spaces, not tabs)
# - Missing quotes around special characters
# - Invalid entity IDs or service names
# - Incorrect file paths
```

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
```bash
# Test internet connectivity
curl -I https://www.google.com

# Check DNS resolution
nslookup home-assistant.io

# View network info
ha network info
```

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

### Common Commands for Information
```bash
ha --help                    # CLI help
ha core info                 # Core system info
ha supervisor info           # Supervisor details
ha host info                 # Host system info
ha addons info claude_terminal  # This addon's info
```

### Debugging
```bash
# Enable debug logging in configuration.yaml
# Add to configuration.yaml:
# logger:
#   default: info
#   logs:
#     homeassistant.components.automation: debug

# Then restart and check logs
ha core restart
ha core logs -f
```

## Quick Reference

### Essential Commands
| Task | Command |
|------|---------|
| Check config | `ha core check` |
| Restart HA | `ha core restart` |
| View logs | `ha core logs -f` |
| Create backup | `ha backups new --name "backup_name"` |
| List addons | `ha addons` |
| Edit main config | `nano /config/configuration.yaml` |
| System info | `ha core info` |

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
