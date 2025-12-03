# Changelog

## 1.0.0

### ✨ New Features
- **Tailscale SSH Support**: Added ability to SSH into the add-on container via Tailscale SSH
  - Access Home Assistant configuration files at `/config/`
  - Full `ha` CLI access for managing Home Assistant, add-ons, backups, and more
  - Tailscale CLI for network diagnostics
  - Requires `userspace_networking: false` (kernel networking mode)
  - Configure access via Tailscale ACLs

### 🛠️ Improvements
- Added `hassio_role: manager` for full Supervisor API access
- Added `homeassistant_api: true` for Home Assistant API access
- Mounted `/config` directory for configuration file access
