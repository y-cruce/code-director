#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${CODEX_HOME:-$HOME/.codex}/skills"
# install.sh passes codex-executor alone: Claude's executors need only that skill.
SKILLS=("$@")
[ ${#SKILLS[@]} -gt 0 ] || SKILLS=(codex-director codex-executor)

mkdir -p "$DEST"
for NAME in "${SKILLS[@]}"; do
  SOURCE="$HERE/skills/$NAME"
  TARGET="$DEST/$NAME"
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
done

echo "Shared context tool: $DEST/${SKILLS[0]}/scripts/context.sh"
echo 'Available on your next Codex turn.'
[ "${SKILLS[0]}" != codex-director ] || echo 'Invoke the director with $codex-director; its executors load $codex-executor.'
