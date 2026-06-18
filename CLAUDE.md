# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Home Assistant add-ons, specifically the **Claude Code** add-on which provides a web-based terminal interface with Claude Code CLI pre-installed. The add-on allows Home Assistant users to access Claude AI capabilities directly from their dashboard.

## Development Environment

### Setup
Use Docker for local container testing.

### Core Development Commands
```bash
# Build
docker build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.22 -t local/claude-terminal ./claude-terminal

# Run locally
docker run -p 7681:7681 -v $(pwd)/config:/config local/claude-terminal

# Lint
hadolint ./claude-terminal/Dockerfile

# Test endpoint
curl -X GET http://localhost:7681/
```

## Architecture

### Add-on Structure (claude-terminal/)
- **config.yaml** - Home Assistant add-on configuration (multi-arch, ingress, ports)
- **Dockerfile** - Alpine-based container with Node.js and Claude Code CLI
- **build.yaml** - Multi-architecture build configuration (amd64, aarch64, armv7)
- **run.sh** - Main startup script with credential management and ttyd terminal
- **scripts/** - Modular credential management scripts

### Key Components
1. **Web Terminal**: Uses ttyd to provide browser-based terminal access
2. **Credential Management**: Persistent authentication storage in `/config/claude-config/`
3. **Service Integration**: Home Assistant ingress support with panel icon
4. **Multi-Architecture**: Supports amd64, aarch64, armv7 platforms

### Credential System
The add-on implements a sophisticated credential management system:
- **Persistent Storage**: Credentials saved to `/config/claude-config/` (survives restarts)
- **Multiple Locations**: Handles various Claude credential file locations
- **Background Service**: Continuous credential monitoring and saving
- **Security**: Proper file permissions (600) and safe directory operations

### Container Execution Flow
1. Initialize environment and create credential directories
2. Install ttyd and tools via apk
3. Setup modular credential management scripts
4. Start background credential monitoring service
5. Launch ttyd web terminal with Claude auto-start

## Development Notes

### Local Container Testing
For rapid development and debugging without pushing new versions:

#### Quick Build & Test
```bash
# Build test version
docker build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.22 -t local/claude-terminal:test ./claude-terminal

# Create test config directory
mkdir -p /tmp/test-config/claude-config

# Configure session picker (optional)
echo '{"auto_launch_claude": false}' > /tmp/test-config/options.json

# Run test container
docker run -d --name test-claude-dev -p 7681:7681 -v /tmp/test-config:/config local/claude-terminal:test

# Check logs
docker logs test-claude-dev

# Test web interface at http://localhost:7681

# Stop and cleanup
docker stop test-claude-dev && docker rm test-claude-dev
```

#### Interactive Testing
```bash
# Test session picker directly
docker run --rm -it local/claude-terminal:test /opt/scripts/claude-session-picker.sh

# Execute commands inside running container
docker exec -it test-claude-dev /bin/bash

# Test script modifications without rebuilding
docker cp ./claude-terminal/scripts/claude-session-picker.sh test-claude-dev:/opt/scripts/
docker exec test-claude-dev chmod +x /opt/scripts/claude-session-picker.sh
```

#### Development Workflow
1. **Make changes** to scripts or Dockerfile
2. **Rebuild** with `docker build -t local/claude-terminal:test ./claude-terminal`
3. **Stop/remove** old container: `docker stop test-claude-dev && docker rm test-claude-dev`
4. **Start new** container with updated image
5. **Test** changes at http://localhost:7681
6. **Repeat** until satisfied, then commit and push

#### Debugging Tips
- **Check container logs**: `docker logs -f test-claude-dev` (follow mode)
- **Inspect running processes**: `docker exec test-claude-dev ps aux`
- **Test individual scripts**: `docker exec test-claude-dev /opt/scripts/script-name.sh`
- **Volume contents**: `ls -la /tmp/test-config/` to verify persistence

### Production Testing
- **Local Testing**: Run the container locally with `docker run -p 7681:7681 -v $(pwd)/config:/config local/claude-terminal`
- **Container Health**: Check logs with `docker logs <container-id>`
- **Authentication**: Use `claude-auth debug` within terminal for credential troubleshooting

### File Conventions
- **Shell Scripts**: Use `#!/usr/bin/with-contenv bashio` for add-on scripts
- **Indentation**: 2 spaces for YAML, 4 spaces for shell scripts
- **Error Handling**: Use `bashio::log.error` for error reporting
- **Permissions**: Credential files must have 600 permissions

### Key Environment Variables
- `CLAUDE_CREDENTIALS_DIRECTORY=/config/claude-config`
- `ANTHROPIC_CONFIG_DIR=/config/claude-config`
- `HOME=/root`

### Important Constraints
- No sudo privileges available in development environment
- Add-on targets Home Assistant OS (Alpine Linux base)
- Must handle credential persistence across container restarts
- Requires multi-architecture compatibility
