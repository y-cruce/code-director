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
// Capability markers: executor-command executor-preset notify-director ask-director "executor-permissions" "label" "thread" danger-full-access case "message":
if (process.argv[2] === "status") {
  if (JSON.parse(fs.readFileSync(process.env.RECORDING, "utf8")).includes("--thread")) process.exit(1);
  console.log(JSON.stringify({ job: { id: "task-test", status: "running", threadId: "session-test" } }));
}
else {
  if (!process.argv.includes("--thread") && (process.env.CODEX_COMPANION_ACP_MODE || process.env.CODEX_COMPANION_ACP_MODEL)) throw new Error("Preset inherited a generic ACP mode/model");
  fs.writeFileSync(process.env.RECORDING, JSON.stringify(process.argv.slice(2))); console.log(JSON.stringify({ jobId: "task-test" }));
}
`);
  const env = { ...process.env, CODEX_COMPANION: companion, CODEX_DIRECTOR_DSH_COMMAND: "/custom/dsh",
    CODEX_DIRECTOR_ANTIGRAVITY_COMMAND: "/custom/agy",
    CLAUDE_CONFIG_DIR: cwd, RECORDING: recording, TMPDIR: cwd,
    CODEX_COMPANION_ACP_MODE: "yolo", CODEX_COMPANION_ACP_MODEL: "qoder-only-model" };
  delete env.CODEX_COMPANION_TRANSCRIPT_PATH;
  delete env.CODEX_COMPANION_SESSION_ID;
  delete env.CODEX_DIRECTOR_DSH_ARGS;
  const localAgy = path.join(cwd, ".local/bin/agy");
  fs.mkdirSync(path.dirname(localAgy), { recursive: true });
  fs.writeFileSync(localAgy, "#!/bin/sh\n", { mode: 0o755 });
  for (const [executor, command, launchArgs] of [["dsh", "/custom/dsh", ["--profile", "acp"]],
    ["antigravity", "/custom/agy", ["acp"]], ["agy", localAgy, ["acp"]]]) {
    for (const [mode, extra] of [["investigate", ""], ["continue", "THREAD: session-test\nEXECUTOR_PERMISSIONS: ask\nEXECUTOR_ARGS: [\"--debug\"]\nEXECUTOR_EFFORT: low\n"]]) {
      const presetEnv = executor === "agy" ? { ...env, HOME: cwd, CODEX_DIRECTOR_ANTIGRAVITY_COMMAND: "" } : env;
      const result = spawnSync("bash", [SCRIPT, "dispatch"], { cwd, env: presetEnv, encoding: "utf8",
        input: `MODE: ${mode}\nNAME: ACP conversation\nCWD: ${cwd}\nEXECUTOR: ${executor}\n${extra}\nContinue the work.\n` });
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /THREAD: session-test/);
      const args = JSON.parse(fs.readFileSync(recording, "utf8"));
      const value = flag => args[args.indexOf(flag) + 1];
      assert.equal(value("--executor-preset"), executor);
      if (mode === "continue") assert.equal(args.includes("--executor"), false, "transport comes from the thread");
      else {
        assert.equal(value("--executor"), "acp");
        assert.equal(value("--executor-command"), command);
      }
      assert.deepEqual(JSON.parse(value("--executor-args")), mode === "continue" ? ["--debug"] : launchArgs);
      assert.equal(value("--executor-permissions"), mode === "continue" ? "ask" : "allow-once");
      if (mode === "continue" || executor === "dsh") assert.equal(value("--executor-effort"), mode === "continue" ? "low" : "xhigh");
      else assert.equal(args.includes("--executor-effort"), false, "agy new-session effort belongs to the driver");
      assert.equal(args.includes("--executor-mode"), false);
      assert.equal(args.includes("--executor-model"), false);
      if (mode === "continue") assert.equal(value("--thread"), "session-test");
      const prompt = fs.readFileSync(value("--prompt-file"), "utf8");
      assert.match(prompt, /---- 最终回报要求 ----/);
      assert.ok(prompt.indexOf("Continue the work.") < prompt.indexOf("最终回报要求"), "evidence requirement follows the brief");
      if (mode === "investigate") {
        assert.match(prompt, /notify-director/);
        if (executor === "dsh") assert.match(prompt, /ask-director/);
      }
    }
  }
  const pathDsh = path.join(cwd, "bin/dsh");
  fs.mkdirSync(path.dirname(pathDsh), { recursive: true });
  fs.writeFileSync(pathDsh, "#!/bin/sh\n", { mode: 0o755 });
  for (const row of [
    { name: "isolated", installed: true, mode: "plan", expected: ["--profile", "acp-fork"] },
    { name: "PATH", expected: ["--profile", "acp"] },
    { name: "env default args", command: "/custom/dsh", envArgs: ["--profile", "acp-fork"], mode: "plan", expected: ["--profile", "acp-fork"] },
    { name: "PATH override", envArgs: ["--profile", "acp-fork"], args: ["--custom"], expected: ["--custom"] },
    { name: "PATH mode", mode: "plan", refused: true }
  ]) {
    const home = path.join(cwd, row.name);
    fs.mkdirSync(home, { recursive: true });
    const isolatedDsh = path.join(home, ".local/share/dsh-fork/dsh");
    if (row.installed) {
      fs.mkdirSync(path.dirname(isolatedDsh), { recursive: true });
      fs.writeFileSync(isolatedDsh, "#!/bin/sh\n", { mode: 0o755 });
    }
    const selected = spawnSync("bash", [SCRIPT, "dispatch"], {
      cwd, env: { ...env, HOME: home, PATH: `${path.dirname(pathDsh)}${path.delimiter}${env.PATH}`,
        CODEX_DIRECTOR_DSH_COMMAND: row.command ?? "", CODEX_DIRECTOR_DSH_ARGS: row.envArgs ? JSON.stringify(row.envArgs) : "" }, encoding: "utf8",
      input: `MODE: investigate\nNAME: ${row.name} DSH\nCWD: ${cwd}\nEXECUTOR: dsh\n${row.mode ? `EXECUTOR_MODE: ${row.mode}\n` : ""}${row.args ? `EXECUTOR_ARGS: ${JSON.stringify(row.args)}\n` : ""}\nInspect.\n`
    });
    if (row.refused) {
      assert.notEqual(selected.status, 0, selected.stdout + selected.stderr);
      assert.match(selected.stdout, /dsh ACP has no session modes/);
      continue;
    }
    assert.equal(selected.status, 0, selected.stdout + selected.stderr);
    const args = JSON.parse(fs.readFileSync(recording, "utf8"));
    const value = flag => args[args.indexOf(flag) + 1];
    const command = row.command ?? (row.installed ? isolatedDsh : pathDsh);
    assert.equal(value("--executor-command"), command);
    assert.deepEqual(JSON.parse(value("--executor-args")), row.expected);
    if (row.mode) assert.equal(value("--executor-mode"), row.mode);
    else assert.equal(args.includes("--executor-mode"), false);
    t.diagnostic(`DSH ${row.name}: ${command} ${JSON.stringify(row.expected)}`);
  }
  const result = spawnSync("bash", [SCRIPT, "dispatch"], { cwd, env: { ...env, CODEX_DIRECTOR_EXECUTOR: "agy" }, encoding: "utf8",
    input: `MODE: continue\nNAME: original executor\nCWD: ${cwd}\nTHREAD: codex-thread\n\nContinue.\n` });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const args = JSON.parse(fs.readFileSync(recording, "utf8"));
  for (const flag of ["--executor", "--executor-preset", "--executor-command", "--executor-args", "--executor-effort"]) {
    assert.equal(args.includes(flag), false, `continue must not supply a default ${flag}`);
  }
});

test("older companions omit unavailable ACP commands and require an explicit continue executor", (t) => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), "legacy-dispatch-test-"));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  const companion = path.join(cwd, "companion.mjs"), recording = path.join(cwd, "args.json");
  fs.writeFileSync(companion, `import fs from "node:fs";
// Capability markers: executor-command "executor-permissions" "label" "thread" danger-full-access case "message":
if (process.argv[2] === "status") console.log(JSON.stringify({ job: { id: "task-old", status: "running", threadId: "original-thread" } }));
else { fs.writeFileSync(process.env.RECORDING, JSON.stringify(process.argv.slice(2))); console.log(JSON.stringify({ jobId: "task-old" })); }
`);
  const env = { ...process.env, CODEX_COMPANION: companion, RECORDING: recording, TMPDIR: cwd,
    CLAUDE_CONFIG_DIR: cwd, CODEX_DIRECTOR_EXECUTOR: "agy", CODEX_DIRECTOR_DSH_COMMAND: "/custom/dsh" };
  delete env.CODEX_COMPANION_TRANSCRIPT_PATH;
  delete env.CODEX_COMPANION_SESSION_ID;
  delete env.CODEX_DIRECTOR_DSH_ARGS;
  const dispatch = headers => spawnSync("bash", [SCRIPT, "dispatch"], { cwd, env, encoding: "utf8",
    input: `NAME: legacy capability check\nCWD: ${cwd}\n${headers}\nProceed.\n` });
  for (const executor of ["dsh", "acp"]) {
    const result = dispatch(`MODE: investigate\nEXECUTOR: ${executor}\nEXECUTOR_COMMAND: /custom/${executor}\n`);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const args = JSON.parse(fs.readFileSync(recording, "utf8"));
    const prompt = fs.readFileSync(args[args.indexOf("--prompt-file") + 1], "utf8");
    assert.doesNotMatch(prompt, /ask-director|notify-director/);
    if (executor === "dsh") assert.match(prompt, /no question tool.*final reply/);
  }
  const refused = dispatch("MODE: continue\nTHREAD: original-thread\n");
  assert.notEqual(refused.status, 0);
  assert.match(refused.stdout, /EXECUTOR_REQUIRED:.*Reload an updated plugin.*original executor/);
  const explicit = dispatch("MODE: continue\nTHREAD: original-thread\nEXECUTOR: dsh\n");
  assert.equal(explicit.status, 0, explicit.stdout + explicit.stderr);
  const args = JSON.parse(fs.readFileSync(recording, "utf8"));
  assert.equal(args[args.indexOf("--executor-command") + 1], "/custom/dsh");
});
