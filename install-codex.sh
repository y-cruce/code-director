#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/skills/codex-director"
DEST="${CODEX_HOME:-$HOME/.codex}/skills"
TARGET="$DEST/codex-director"

mkdir -p "$DEST"
# Compare physical paths: a checkout reached through a symlink (macOS /tmp, a
# linked projects dir) must still count as the same installation on re-run.
if [ -L "$TARGET" ] && [ "$(cd "$TARGET" 2>/dev/null && pwd -P)" = "$(cd "$SOURCE" && pwd -P)" ]; then
  echo "Already installed: $TARGET -> $SOURCE"
elif [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  echo "INSTALL_CONFLICT: $TARGET already exists; preserve it before installing" >&2
  exit 1
else
  ln -s "$SOURCE" "$TARGET"
  echo "Installed: $TARGET -> $SOURCE"
fi

echo 'Available on your next Codex turn. Invoke with $codex-director.'
