#!/usr/bin/env bash
# Links the skill into ~/.claude/ (and removes the agents older versions left behind), then prints the snippet that must be added to CLAUDE.md by hand.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"

mkdir -p "$DEST/skills"
# A task is watched by the plugin's tasks pane now; the forwarding agents older
# versions installed would follow the same jobs and report them twice.
rm -f "$DEST/agents/codex-worker.md" "$DEST/agents/codex-task.md"
# The skill was `codex-director` before it took executors other than Codex;
# left in place it loads beside the new one as a second, stale copy.
rm -rf "$DEST/skills/codex-director"
# Older versions installed a copy; a link to this checkout keeps one source,
# so later edits here need no reinstall.
rm -rf "$DEST/skills/code-director"
ln -s "$HERE/skills/code-director" "$DEST/skills/code-director"
chmod +x "$HERE/skills/code-director/scripts/dispatch.sh"

echo "Installed:"
echo "  $DEST/skills/code-director -> $HERE/skills/code-director"
echo
echo "One step left: append the snippet in docs/claude-md-snippet.md to $DEST/CLAUDE.md."
echo "Then run /reload-plugins in Claude Code, or start a new session."
