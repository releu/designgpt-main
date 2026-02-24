#!/usr/bin/env bash
# Symlinks Claude Code project memory into this repo so it stays in git.
# Run once after cloning on a new machine.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="$HOME/.claude/projects/-Users-releu-Code-design-gpt/memory"

mkdir -p "$MEMORY_DIR"
ln -sf "$REPO_DIR/claude/memory/MEMORY.md" "$MEMORY_DIR/MEMORY.md"

echo "Symlink created: $MEMORY_DIR/MEMORY.md -> $REPO_DIR/claude/memory/MEMORY.md"
