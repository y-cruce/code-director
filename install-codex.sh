#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/skills/codex-director"
DEST="${CODEX_HOME:-$HOME/.codex}/skills"
TARGET="$DEST/codex-director"

mkdir -p "$DEST"
if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$SOURCE" ]; then
  echo "Already installed: $TARGET -> $SOURCE"
elif [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  echo "INSTALL_CONFLICT: $TARGET already exists; preserve it before installing" >&2
  exit 1
else
  ln -s "$SOURCE" "$TARGET"
  echo "Installed: $TARGET -> $SOURCE"
fi

echo 'Available on your next Codex turn. Invoke with $codex-director.'
