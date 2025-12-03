# incognitojam's Home Assistant Add-ons

This repository contains custom add-ons for Home Assistant.

## Installation

To add this repository to your Home Assistant instance:

1. Go to **Settings** → **Add-ons** → **Add-on Store**
2. Click the three dots menu in the top right corner
3. Select **Repositories**
4. Add the URL: `https://github.com/incognitojam/home-assistant-addons`
5. Click **Add**

## Add-ons

### Claude Code

A web-based terminal interface with Claude Code CLI pre-installed. This add-on provides a terminal environment directly in your Home Assistant dashboard, allowing you to use Claude's powerful AI capabilities for coding, automation, and configuration tasks.

Features:
- Web terminal access through your Home Assistant UI
- Pre-installed Claude Code CLI that launches automatically
- Direct access to your Home Assistant config directory
- No configuration needed (uses OAuth)
- Access to Claude's complete capabilities including:
  - Code generation and explanation
  - Debugging assistance
  - Home Assistant automation help
  - Learning resources

[Documentation](claude-terminal/DOCS.md)

### Tailscale

A fork of the [Home Assistant Community Add-on: Tailscale](https://github.com/hassio-addons/addon-tailscale) providing a zero config VPN for building secure networks. This add-on installs Tailscale on your Home Assistant instance, creating a secure network between your servers, computers, and cloud instances.

Features:
- Zero configuration VPN that works from anywhere
- Exit node support for routing all traffic through Home Assistant
- Subnet routing to access your local network remotely
- MagicDNS for easy device addressing
- Tailscale Serve and Funnel for HTTPS access to Home Assistant
- Taildrop for receiving files from other Tailscale devices
- App connector support
- Headscale (self-hosted control server) compatibility

[Documentation](tailscale/DOCS.md)

## Support

If you have any questions or issues with this add-on, please create an issue in this repository.

## Credits

This add-on was created with the assistance of Claude Code itself! The development process, debugging, and documentation were all completed using Claude's AI capabilities.

## License

This repository is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
