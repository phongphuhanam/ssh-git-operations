#!/bin/bash
# Installs this repo's agent skills (agent/<name>/SKILL.md) into any AI
# coding harness's skills directory found on this machine.
#
# Only installs into a harness's directory if that harness's own config
# directory already exists (i.e. the tool is actually installed) - this
# script never creates a new harness's config dir from scratch, and never
# guesses at a harness that isn't present.
#
# Confirmed convention: Claude Code reads ~/.claude/skills/<name>/SKILL.md.
# The Codex/Cursor/Windsurf entries below are best-effort, based on the same
# emerging SKILL.md convention (Cursor is already observed using it for
# project-local skills) - adjust HARNESS_NAMES/HARNESS_BASES below if a
# tool's actual path differs.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO_URL="https://github.com/phongphuhanam/ssh-git-operations.git"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
TMP_DIR=""

# Locate the agent/ skills directory: use the checkout this script lives in
# if present, otherwise fetch one (curl/wget | bash install).
if [ ! -d "$SOURCE_DIR/agent" ]; then
    echo "Downloading ssh-git-operations..."
    if ! command -v git &> /dev/null; then
        echo -e "${RED}✗ git is required to install without a local clone${NC}"
        exit 1
    fi
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    git clone --quiet --depth 1 "$REPO_URL" "$TMP_DIR"
    SOURCE_DIR="$TMP_DIR"
fi

if [ ! -d "$SOURCE_DIR/agent" ]; then
    echo -e "${RED}✗ No agent/ skills directory found in the repo${NC}"
    exit 1
fi

echo -e "${GREEN}=== ssh-git-operations Skill Installer ===${NC}\n"

HARNESS_NAMES=(Claude Codex Cursor Windsurf)
HARNESS_BASES=("$HOME/.claude" "$HOME/.codex" "$HOME/.cursor" "$HOME/.windsurf")

installed_any=false

for i in "${!HARNESS_BASES[@]}"; do
    name="${HARNESS_NAMES[$i]}"
    base_dir="${HARNESS_BASES[$i]}"

    if [ ! -d "$base_dir" ]; then
        echo -e "${YELLOW}- $name not detected ($base_dir), skipping${NC}"
        continue
    fi

    for skill_dir in "$SOURCE_DIR"/agent/*/; do
        [ -f "${skill_dir}SKILL.md" ] || continue
        skill_name=$(basename "$skill_dir")
        target="$base_dir/skills/$skill_name"
        mkdir -p "$target"
        cp "${skill_dir}SKILL.md" "$target/SKILL.md"
        echo -e "${GREEN}✓ Installed '$skill_name' for $name -> $target/SKILL.md${NC}"
        installed_any=true
    done
done

echo ""
if [ "$installed_any" = false ]; then
    echo -e "${YELLOW}⚠ No supported harness config directories found.${NC}"
    echo "Nothing installed. If your tool uses a different skills path, copy manually:"
    for skill_dir in "$SOURCE_DIR"/agent/*/; do
        [ -f "${skill_dir}SKILL.md" ] && echo "  ${skill_dir}SKILL.md"
    done
    exit 1
fi

echo -e "${GREEN}=== Done ===${NC}"
