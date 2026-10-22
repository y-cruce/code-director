import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("../skills/code-director/scripts/dispatch.sh", import.meta.url));

test("DSH dispatch starts and continues the ACP session without Qoder modes or models", (t) => {
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
  if (process.env.CODEX_COMPANION_ACP_MODE || process.env.CODEX_COMPANION_ACP_MODEL) throw new Error("DSH inherited a generic ACP mode/model");
  fs.writeFileSync(process.env.RECORDING, JSON.stringify(process.argv.slice(2))); console.log(JSON.stringify({ jobId: "task-test" }));
}
`);
  const env = { ...process.env, CODEX_COMPANION: companion, CODEX_DIRECTOR_DSH_COMMAND: "/custom/dsh",
    CLAUDE_CONFIG_DIR: cwd, RECORDING: recording, TMPDIR: cwd,
    CODEX_COMPANION_ACP_MODE: "yolo", CODEX_COMPANION_ACP_MODEL: "qoder-only-model" };
  delete env.CODEX_COMPANION_TRANSCRIPT_PATH;
  delete env.CODEX_COMPANION_SESSION_ID;
  for (const [mode, extra] of [["investigate", ""], ["continue", "THREAD: session-test\nEXECUTOR_PERMISSIONS: ask\n"]]) {
    const result = spawnSync("bash", [SCRIPT, "dispatch"], { cwd, env, encoding: "utf8",
      input: `MODE: ${mode}\nNAME: DSH conversation\nCWD: ${cwd}\nEXECUTOR: dsh\n${extra}\nContinue the work.\n` });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /THREAD: session-test/);
    const args = JSON.parse(fs.readFileSync(recording, "utf8"));
    const value = flag => args[args.indexOf(flag) + 1];
    assert.equal(value("--executor"), "acp");
    assert.equal(value("--executor-command"), "/custom/dsh");
    assert.deepEqual(JSON.parse(value("--executor-args")), ["--profile", "acp"]);
    assert.equal(value("--executor-permissions"), mode === "continue" ? "ask" : "allow-once");
    assert.equal(args.includes("--executor-mode"), false);
    assert.equal(args.includes("--executor-model"), false);
    if (mode === "continue") assert.equal(value("--thread"), "session-test");
  }
});
