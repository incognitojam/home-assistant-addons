# Keep persistent npm-installed CLIs ahead of image-owned fallbacks in login shells.
export NPM_CONFIG_PREFIX="/data/npm"
export PATH="${NPM_CONFIG_PREFIX}/bin:${HOME}/.local/bin:${PATH}"
