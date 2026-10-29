import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("../skills/code-director/scripts/dispatch.sh", import.meta.url));

test("ACP presets start and continue without inheriting Qoder modes or models", (t) => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-dispatch-test-"));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  const companion = path.join(cwd, "companion.mjs");
  const recording = path.join(cwd, "args.json");
  fs.writeFileSync(companion, `import fs from "node:fs";
// Capability markers: executor-command "executor-permissions" "label" "thread" danger-full-access case "message":
if (process.argv[2] === "status") {
  if (JSON.parse(fs.readFileSync(process.env.RECORDING, "utf8")).includes("--thread")) process.exit(1);
  console.log(JSON.stringify({ job: { id: "task-test", status: "running", threadId: "session-test" } }));
}
else {
  if (process.env.CODEX_COMPANION_ACP_MODE || process.env.CODEX_COMPANION_ACP_MODEL) throw new Error("Preset inherited a generic ACP mode/model");
  fs.writeFileSync(process.env.RECORDING, JSON.stringify(process.argv.slice(2))); console.log(JSON.stringify({ jobId: "task-test" }));
}
`);
  const env = { ...process.env, CODEX_COMPANION: companion, CODEX_DIRECTOR_DSH_COMMAND: "/custom/dsh",
    CODEX_DIRECTOR_ANTIGRAVITY_COMMAND: "/custom/agy_acp_server.par",
    CLAUDE_CONFIG_DIR: cwd, RECORDING: recording, TMPDIR: cwd,
    CODEX_COMPANION_ACP_MODE: "yolo", CODEX_COMPANION_ACP_MODEL: "qoder-only-model" };
  delete env.CODEX_COMPANION_TRANSCRIPT_PATH;
  delete env.CODEX_COMPANION_SESSION_ID;
  for (const [executor, command, launchArgs] of [["dsh", "/custom/dsh", ["--profile", "acp"]],
    ["antigravity", "/custom/agy_acp_server.par", []], ["agy", "/custom/agy_acp_server.par", []]]) {
    for (const [mode, extra] of [["investigate", ""], ["continue", "THREAD: session-test\nEXECUTOR_PERMISSIONS: ask\nEXECUTOR_ARGS: [\"--debug\"]\nEXECUTOR_EFFORT: low\n"]]) {
      const result = spawnSync("bash", [SCRIPT, "dispatch"], { cwd, env, encoding: "utf8",
        input: `MODE: ${mode}\nNAME: ACP conversation\nCWD: ${cwd}\nEXECUTOR: ${executor}\n${extra}\nContinue the work.\n` });
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /THREAD: session-test/);
      const args = JSON.parse(fs.readFileSync(recording, "utf8"));
      const value = flag => args[args.indexOf(flag) + 1];
      assert.equal(value("--executor"), "acp");
      assert.equal(value("--executor-command"), command);
      assert.deepEqual(JSON.parse(value("--executor-args")), mode === "continue" ? ["--debug"] : launchArgs);
      assert.equal(value("--executor-permissions"), mode === "continue" ? "ask" : "allow-once");
      assert.equal(value("--executor-effort"), mode === "continue" ? "low" : executor === "dsh" ? "xhigh" : "high");
      assert.equal(args.includes("--executor-mode"), false);
      assert.equal(args.includes("--executor-model"), false);
      if (mode === "continue") assert.equal(value("--thread"), "session-test");
    }
  }
});
