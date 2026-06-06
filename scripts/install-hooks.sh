#!/usr/bin/env bash
# Installs git hooks from scripts/hooks/ into .git/hooks/.
# Run once after cloning: bash scripts/install-hooks.sh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="$ROOT/scripts/hooks"
HOOKS_DST="$ROOT/.git/hooks"

for hook in "$HOOKS_SRC"/*; do
    name="$(basename "$hook")"
    dest="$HOOKS_DST/$name"
    cp "$hook" "$dest"
    chmod +x "$dest"
    echo "Installed $name → .git/hooks/$name"
done

echo "Done."
