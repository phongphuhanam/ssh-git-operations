#!/bin/bash
# Installation script for ssh-git-operations Oh My Zsh plugin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== ssh-git-operations Plugin Installer ===${NC}\n"

# Check prerequisites
echo "Checking prerequisites..."

# Check for Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo -e "${RED}✗ Oh My Zsh not found${NC}"
    echo "Please install Oh My Zsh first: https://ohmyz.sh/#install"
    exit 1
fi
echo -e "${GREEN}✓ Oh My Zsh found${NC}"

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}✗ GitHub CLI (gh) not found${NC}"
    echo "Please install it:"
    echo "  macOS: brew install gh"
    echo "  Linux: https://github.com/cli/cli#installation"
    exit 1
fi
echo -e "${GREEN}✓ GitHub CLI found${NC}"

# Check GitHub authentication
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}⚠ GitHub CLI not authenticated${NC}"
    echo "Run: gh auth login"
    echo ""
fi
echo -e "${GREEN}✓ GitHub CLI authenticated${NC}\n"

# Installation
PLUGIN_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/ssh-git-operations"

# Check if already installed
if [ -d "$PLUGIN_DIR" ]; then
    echo -e "${YELLOW}Plugin directory already exists at:${NC}"
    echo "$PLUGIN_DIR"
    read -p "Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
    rm -rf "$PLUGIN_DIR"
fi

# Copy plugin files
echo "Installing plugin..."
mkdir -p "$PLUGIN_DIR"
cp ssh-git-operations.plugin.zsh "$PLUGIN_DIR/"
cp README.md "$PLUGIN_DIR/"
cp LICENSE "$PLUGIN_DIR/"
cp -r examples "$PLUGIN_DIR/" 2>/dev/null || true

echo -e "${GREEN}✓ Plugin installed to: $PLUGIN_DIR${NC}\n"

# Update .zshrc
echo "Checking .zshrc configuration..."
if grep -q "ssh-git-operations" "$HOME/.zshrc"; then
    echo -e "${GREEN}✓ Plugin already in .zshrc${NC}"
else
    echo "Adding plugin to .zshrc..."
    # Backup .zshrc
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
    echo -e "\n# ssh-git-operations plugin" >> "$HOME/.zshrc"

    # Add to plugins array
    sed -i.bak 's/plugins=(\(.*\))/plugins=(\1 ssh-git-operations)/' "$HOME/.zshrc"
    rm -f "$HOME/.zshrc.bak"

    echo -e "${GREEN}✓ Added to .zshrc (backup saved to .zshrc.backup)${NC}"
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Reload your shell: source ~/.zshrc"
echo "2. Test the plugin: ssh-gh-remote-push --help"
echo "3. See examples: cat $PLUGIN_DIR/examples/EXAMPLES.md"
echo ""
echo "Quick start:"
echo "  ssh-gh-remote-push user@host /path/to/repo"
echo "  ssh-gh-remote-pull user@host /path/to/repo"
echo "  ssh-gh-remote-fetch user@host /path/to/repo"
echo ""
echo "For more info: cat $PLUGIN_DIR/README.md"
