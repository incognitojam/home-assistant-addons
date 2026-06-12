# Development Guide

This guide covers local development and testing workflows for the Claude Code add-on.

## Local Container Testing

### Prerequisites

- **Docker** or **Podman** installed (commands below use `docker`; `podman` is a drop-in replacement)
- **Git** repository cloned locally

> **Tip:** Build with the base image that matches your machine's architecture so the
> container runs natively (no slow emulation). Use `aarch64-base` on Apple Silicon /
> ARM, `amd64-base` on Intel/AMD.

### Quick Start Testing

The fastest way to test changes — including the full web UI — without publishing a
new version or installing into a real Home Assistant instance:

```bash
# 1. Build test container (use aarch64-base on Apple Silicon, amd64-base on Intel)
docker build --build-arg BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.19 \
  -t local/claude-terminal:test ./claude-terminal

# 2. Run it. Mount /data so the Claude install + auth persist across runs, just
#    like the real add-on. Use the env-var overrides to choose a mode (see note).
mkdir -p /tmp/cc-data /tmp/cc-config
docker run -d --name test-claude-dev \
  -p 7681:7681 \
  -e AUTO_LAUNCH_CLAUDE=false \
  -e AUTO_UPDATE_CLAUDE=true \
  -v /tmp/cc-data:/data \
  -v /tmp/cc-config:/config \
  local/claude-terminal:test

# 3. Check startup logs (confirm options resolve, no per-launch reinstall)
docker logs -f test-claude-dev

# 4. Test the web UI in a browser: http://localhost:7681
#    ttyd serves the terminal here directly (ingress is only added by HA in prod).

# 5. Clean up when done
docker stop test-claude-dev && docker rm test-claude-dev
```

> **Setting options locally:** In a real add-on the user's options come from the
> **Supervisor API** (`bashio::config` calls `http://supervisor/...`). A bare local
> container has no Supervisor, so `bashio::config` can't read options there — this
> is the historical "bashio::config doesn't work in local containers" gotcha.
>
> To work around it, `run.sh` accepts env-var overrides that take precedence over
> `bashio::config`, so you can exercise each mode locally:
>
> | Add-on option        | Local override          | Values        |
> | -------------------- | ----------------------- | ------------- |
> | `auto_launch_claude` | `AUTO_LAUNCH_CLAUDE`    | `true`/`false`|
> | `auto_update_claude` | `AUTO_UPDATE_CLAUDE`    | `true`/`false`|
>
> These overrides are only needed for local testing; in production the values come
> from the add-on configuration as usual.

### Development Workflow

#### 1. Iterative Development

```bash
# Make changes to code
vim claude-terminal/scripts/claude-session-picker.sh

# Rebuild image
podman build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.19 \
  -t local/claude-terminal:test ./claude-terminal

# Stop old container
podman stop test-claude-dev && podman rm test-claude-dev

# Start new container with changes
podman run -d --name test-claude-dev -p 7681:7681 \
  -v /tmp/test-config:/config local/claude-terminal:test

# Test changes
open http://localhost:7681
```

#### 2. Hot-reload Script Testing

For script changes without full rebuilds:

```bash
# Copy updated script to running container
podman cp ./claude-terminal/scripts/claude-session-picker.sh \
  test-claude-dev:/opt/scripts/claude-session-picker.sh

# Make executable
podman exec test-claude-dev chmod +x /opt/scripts/claude-session-picker.sh

# Test directly
podman exec -it test-claude-dev /opt/scripts/claude-session-picker.sh
```

### Testing Scenarios

#### Session Picker Testing

```bash
# Test with auto-launch disabled
echo '{"auto_launch_claude": false}' > /tmp/test-config/options.json

# Test with auto-launch enabled (default)
echo '{"auto_launch_claude": true}' > /tmp/test-config/options.json
# OR
rm /tmp/test-config/options.json
```

#### Authentication Testing

```bash
# Start with clean credentials
rm -rf /tmp/test-config/claude-config/*

# Pre-populate credentials for testing
cp ~/.config/anthropic/* /tmp/test-config/claude-config/
```

#### Multi-session Testing

```bash
# Run multiple containers on different ports
podman run -d --name test-claude-dev-8681 -p 8681:7681 -v /tmp/test-config-2:/config local/claude-terminal:test
podman run -d --name test-claude-dev-9681 -p 9681:7681 -v /tmp/test-config-3:/config local/claude-terminal:test
```

### Debugging Techniques

#### Container Inspection

```bash
# Follow logs in real-time
podman logs -f test-claude-dev

# Execute shell inside container
podman exec -it test-claude-dev /bin/bash

# Check running processes
podman exec test-claude-dev ps aux

# Inspect environment variables
podman exec test-claude-dev env | grep CLAUDE
```

#### Script Debugging

```bash
# Test session picker with debug output
podman exec -it test-claude-dev bash -x /opt/scripts/claude-session-picker.sh

# Test startup script components
podman exec test-claude-dev /usr/local/bin/claude-session-picker

# Check file permissions and locations
podman exec test-claude-dev ls -la /opt/scripts/
podman exec test-claude-dev ls -la /config/claude-config/
```

#### Network Testing

```bash
# Test web endpoint
curl -I http://localhost:7681

# Test WebSocket connection
curl --include --no-buffer \
  --header "Connection: Upgrade" \
  --header "Upgrade: websocket" \
  --header "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
  --header "Sec-WebSocket-Version: 13" \
  http://localhost:7681/ws
```

### Performance Testing

#### Resource Usage

```bash
# Monitor container resources
podman stats test-claude-dev

# Check container size
podman images local/claude-terminal:test

# Inspect layers
podman history local/claude-terminal:test
```

#### Load Testing

```bash
# Multiple concurrent connections
for i in {1..5}; do
  curl http://localhost:7681 &
done
wait
```

### Common Issues & Solutions

#### Port Already In Use
```bash
# Find and kill process using port 7681
sudo lsof -ti:7681 | xargs kill -9

# Or use different port
podman run -d --name test-claude-dev -p 7682:7681 -v /tmp/test-config:/config local/claude-terminal:test
```

#### Volume Mount Issues
```bash
# Ensure directory exists and has correct permissions
mkdir -p /tmp/test-config/claude-config
chmod 755 /tmp/test-config/claude-config

# Check SELinux labels (if applicable)
ls -laZ /tmp/test-config/
```

#### Build Cache Issues
```bash
# Force rebuild without cache
podman build --no-cache --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.19 \
  -t local/claude-terminal:test ./claude-terminal

# Clean up unused images
podman image prune
```

### Cleanup Commands

#### Clean Up Test Environment
```bash
# Stop and remove test containers
podman stop test-claude-dev && podman rm test-claude-dev

# Remove test configurations
rm -rf /tmp/test-config*

# Clean up test images
podman rmi local/claude-terminal:test
```

#### Full System Cleanup
```bash
# Remove all stopped containers
podman container prune

# Remove unused images
podman image prune

# Remove unused volumes
podman volume prune
```

## Production Deployment

Once testing is complete:

```bash
# Commit changes
git add .
git commit -m "feature: description of changes"

# Update version in config.yaml
vim claude-terminal/config.yaml

# Push to main branch
git push origin main
```

The changes will automatically be built and distributed to Home Assistant users.

## Advanced Testing

### Integration with Home Assistant

```bash
# Test with real Home Assistant config structure
mkdir -p /tmp/ha-config/{.storage,claude-config}
echo '{"auto_launch_claude": false}' > /tmp/ha-config/options.json

podman run -d --name test-ha-claude -p 7681:7681 \
  -v /tmp/ha-config:/config local/claude-terminal:test
```

### Cross-Platform Testing

```bash
# Test different base images
podman build --build-arg BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.19 \
  -t local/claude-terminal:arm64 ./claude-terminal

podman build --build-arg BUILD_FROM=ghcr.io/home-assistant/armv7-base:3.19 \
  -t local/claude-terminal:armv7 ./claude-terminal
```
