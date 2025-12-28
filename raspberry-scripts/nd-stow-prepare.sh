#!/bin/bash
# Prepare directories for stow to link only files, not directories
#
# Creates all directories in ~/.config that exist in common-dotfiles/.config
# so that stow will create symlinks for individual files instead of
# linking entire directories.
#
# Usage: nd-stow-prepare.sh [dotfiles_dir]
#   dotfiles_dir: Path to common-dotfiles (default: ~/environment/common-dotfiles)

set -euo pipefail

DOTFILES_DIR="${1:-$HOME/environment/common-dotfiles}"
TARGET_DIR="$HOME"

if [[ ! -d "$DOTFILES_DIR" ]]; then
    echo "Error: Dotfiles directory not found: $DOTFILES_DIR" >&2
    exit 1
fi

echo "Preparing directories for stow..."
echo "  Source: $DOTFILES_DIR"
echo "  Target: $TARGET_DIR"
echo

# Find all directories in the dotfiles dir and create them in target
find "$DOTFILES_DIR" -type d | while read -r src_dir; do
    # Get the relative path from dotfiles dir
    rel_path="${src_dir#$DOTFILES_DIR}"

    # Skip the root directory itself
    [[ -z "$rel_path" ]] && continue

    target_path="$TARGET_DIR$rel_path"

    if [[ -L "$target_path" ]]; then
        # It's a symlink - remove it so we can create a real directory
        echo "Removing symlink: $target_path"
        rm "$target_path"
    fi

    if [[ ! -d "$target_path" ]]; then
        echo "Creating: $target_path"
        mkdir -p "$target_path"
    fi
done

echo
echo "Done. You can now run: stow -d '$DOTFILES_DIR' -t '$TARGET_DIR' ."
