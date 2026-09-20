#!/usr/bin/env bash
# Copies the skill into ~/.claude/ (and removes the agents older versions left behind), then prints the snippet that must be added to CLAUDE.md by hand.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"

mkdir -p "$DEST/skills/code-director/scripts"
# A task is watched by the plugin's tasks pane now; the forwarding agents older
# versions installed would follow the same jobs and report them twice.
rm -f "$DEST/agents/codex-worker.md" "$DEST/agents/codex-task.md"
# The skill was `codex-director` before it took executors other than Codex;
# left in place it loads beside the new one as a second, stale copy.
rm -rf "$DEST/skills/codex-director"
# `codex-worker.sh` is `dispatch.sh` now; a copy left behind is a second
# script the plugin may still resolve to.
rm -f "$DEST/skills/code-director/scripts/codex-worker.sh"
cp "$HERE/skills/code-director/SKILL.md" "$DEST/skills/code-director/SKILL.md"
cp "$HERE/skills/code-director/scripts/dispatch.sh" "$DEST/skills/code-director/scripts/dispatch.sh"
chmod +x "$DEST/skills/code-director/scripts/dispatch.sh"

echo "Installed:"
echo "  $DEST/skills/code-director/SKILL.md"
echo "  $DEST/skills/code-director/scripts/dispatch.sh"
echo
echo "One step left: append the snippet in docs/claude-md-snippet.md to $DEST/CLAUDE.md."
echo "Then run /reload-plugins in Claude Code, or start a new session."
