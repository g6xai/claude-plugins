#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$SCRIPT_DIR/plugins/fleet"

echo ""
echo "  Installing g6xai claude-plugins..."
echo ""

mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents"

for skill_dir in "$FLEET_DIR"/skills/fleet-*/; do
    [ -d "$skill_dir" ] || continue
    name=$(basename "$skill_dir")
    target="$HOME/.claude/skills/$name"
    [ -L "$target" ] && rm "$target"
    [ -d "$target" ] && { echo "  ! $name — dir exists, skip"; continue; }
    ln -s "${skill_dir%/}" "$target"
    echo "  + $name"
done

for agent_file in "$FLEET_DIR"/agents/fleet-*.md; do
    [ -f "$agent_file" ] || continue
    name=$(basename "$agent_file")
    target="$HOME/.claude/agents/$name"
    [ -L "$target" ] && rm "$target"
    ln -s "$agent_file" "$target"
    echo "  + $name"
done

echo ""
echo "  Done. Restart Claude Code, then run: /fleet-init"
echo ""
