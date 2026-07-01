# incognitojam's Home Assistant Apps

This repository contains custom apps for Home Assistant.

## Installation

To add this repository to your Home Assistant instance:

1. Go to **Settings** → **Apps** → **App Store**
2. Click the three dots menu in the top right corner
3. Select **Repositories**
4. Add the URL: `https://github.com/incognitojam/home-assistant-addons`
5. Click **Add**

## Apps

### Codex for Home Assistant

A web-based terminal interface with OpenAI Codex CLI pre-installed. This app starts Codex in your Home Assistant `/config` directory after an authentication check.

Features:
- Web terminal access through your Home Assistant UI
- Pre-installed Codex CLI
- Pre-launch picker for device code or API key authentication
- Direct write access to your Home Assistant config directory
- Bundled `AGENTS.md` guidance for Home Assistant-aware Codex sessions
- Persistent Codex state under the app `/data` volume
- Home Assistant CLI (`ha`) included
- Supports `amd64` and `aarch64`

[Documentation](codex-terminal/DOCS.md)

### Claude Code

A web-based terminal interface with Claude Code CLI pre-installed. This app provides a terminal environment directly in your Home Assistant dashboard, allowing you to use Claude's powerful AI capabilities for coding, automation, and configuration tasks.

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

## Support

If you have any questions or issues with this app, please create an issue in this repository.

## Credits

This app was created with the assistance of Claude Code itself! The development process, debugging, and documentation were all completed using Claude's AI capabilities.

## License

This repository is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
