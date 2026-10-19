#!/usr/bin/env bash
# Links the skill into ~/.claude/ (and removes the agents older versions left behind), allows the Codex
# plugin's dispatch tools in ~/.claude/settings.json, then prints the snippet that must be added to CLAUDE.md by hand.
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

# The Codex plugin (1.4.48+) gives the director dispatch tools of its own. They
# run what the skill would otherwise run from Bash, so they are allowed in the
# user's settings once instead of asked about at every call. The five names are
# spelled out: `mcp__codex__*` would also cover a Codex MCP server named codex.
SETTINGS="$DEST/settings.json"
node - "$SETTINGS" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const file = process.argv[2];
const rules = ["dispatch", "message", "answer", "result", "status"].map(name => `mcp__codex__${name}`);
let settings = {};
if (fs.existsSync(file)) {
  try { settings = JSON.parse(fs.readFileSync(file, "utf8")); }
  catch (error) {
    console.log(`Left ${file} alone: it is not valid JSON (${error.message}). Add these to permissions.allow by hand: ${rules.join(", ")}`);
    process.exit(0);
  }
}
if (!settings || typeof settings !== "object" || Array.isArray(settings)) {
  console.log(`Left ${file} alone: it does not hold a JSON object. Add these to permissions.allow by hand: ${rules.join(", ")}`);
  process.exit(0);
}
settings.permissions ??= {};
const allow = Array.isArray(settings.permissions.allow) ? settings.permissions.allow : [];
const missing = rules.filter(rule => !allow.includes(rule));
if (!missing.length) {
  console.log(`Permissions: ${file} already allows the Codex dispatch tools.`);
  process.exit(0);
}
settings.permissions.allow = [...allow, ...missing];
fs.mkdirSync(path.dirname(file), { recursive: true });
const temp = `${file}.code-director-${process.pid}`;
fs.writeFileSync(temp, `${JSON.stringify(settings, null, 2)}\n`);
fs.renameSync(temp, file);
console.log(`Permissions: added ${missing.join(", ")} to permissions.allow in ${file}.`);
NODE

# Dispatched Codex tasks follow the codex-executor skill, which Codex reads from its own skills directory.
bash "$HERE/install-codex.sh" codex-executor

echo "Installed:"
echo "  $DEST/skills/code-director -> $HERE/skills/code-director"
echo
echo "One step left: append the snippet in docs/claude-md-snippet.md to $DEST/CLAUDE.md."
echo "Then run /reload-plugins in Claude Code, or start a new session."
