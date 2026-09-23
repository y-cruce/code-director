#!/usr/bin/env bash
# Shell side of Codex dispatching, called by the director (Claude main thread) from Bash:
#   dispatch.sh dispatch [input-file]  read the brief from the file or stdin, start Codex, return at once with
#                                          STATUS: started / JOB / NAME / THREAD (launch + collect in one call)
#   dispatch.sh follow <job-id> --cwd <repo> [--after <cursor>] [--max-seconds <n>] [--until done]
#                                          block and print the job's event stream until something the director must act on
#                                          (DONE/FAILED/QUESTION/QUESTION_PENDING/NOTIFIED/STALLED/TIMEOUT)
#   dispatch.sh events --cwd <repo>    stream job events (one line each) for a Monitor; needs a plugin with `events`
#   dispatch.sh message <job-id> <prompt-file> [--cwd <repo>] [--interrupt|--queue]
#                                          forward a correction; print MESSAGED (with queued=<job> for --queue) or MESSAGE_FAILED
#                                          no flag = add it to the running turn (Codex only); --queue = deliver as the
#                                          next turn once this one ends; --interrupt = cancel this turn and run it now
#   dispatch.sh answer <job-id> <request-id> <answers-file> [--cwd <repo>]
#                                          deliver answers to a structured question
#   dispatch.sh companion              print the selected codex-companion.mjs path
# Building blocks of dispatch, also usable on their own:
#   dispatch.sh launch <input-file>    parse the header lines, start Codex, print WORK=... JOB=... STARTED
#   dispatch.sh collect <WORK>         print the STATUS / JOB / NAME / THREAD lines
#
# Input file format: `KEY: value` header lines, a blank line, then the brief body.
# Headers: NAME (required task name), MODE (investigate|implement|review|adversarial-review|continue), EFFORT, MODEL, BASE, WRITE, THREAD,
# SIBLINGS, CWD, SANDBOX (full = no sandbox, the default for every task; network = workspace-write plus network
# access; default = the plugin's own read-only / workspace-write choice),
# EXECUTOR (codex | qoder | acp) with EXECUTOR_COMMAND, EXECUTOR_ARGS (JSON array), EXECUTOR_MODE, EXECUTOR_EFFORT and MODEL for a
# non-Codex agent; task-class modes only. Without the header the default is $CODEX_DIRECTOR_EXECUTOR, else codex,
# and qoder runs in its `yolo` permission mode unless EXECUTOR_MODE or $CODEX_DIRECTOR_EXECUTOR_MODE says otherwise.
set -uo pipefail

select_companion() {
  if [ -n "${CODEX_COMPANION:-}" ]; then printf '%s\n' "$CODEX_COMPANION"; return; fi
  local cc f
  cc=$(ls ~/.claude/plugins/cache/*/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
  for f in $(ls ~/.claude/plugins/cache/*/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V); do grep -q '"thread"' "$f" && cc="$f"; done
  for f in $(ls ~/.claude/plugins/cache/*/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V); do grep -q 'case "message":' "$f" && cc="$f"; done
  for f in $(ls ~/.claude/plugins/cache/*/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V); do grep -q 'case "events":' "$f" && cc="$f"; done
  for f in $(ls ~/.claude/plugins/cache/*/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V); do grep -q 'case "observe":' "$f" && cc="$f"; done
  if [ -z "$cc" ]; then
    echo "COMPANION_NOT_FOUND: no codex-companion.mjs under ~/.claude/plugins/cache; install the Codex plugin or set CODEX_COMPANION" >&2
    return 1
  fi
  printf '%s\n' "$cc"
}

# Reads $1 (the input file). Sets the header variables and writes the body to $WORK/brief.md.
parse_input() {
  local line key val in_header=1
  NAME=""; MODE=""; EFFORT=""; MODEL=""; BASE=""; WRITE=""; THREAD=""; SIBLINGS=""; CWD=""; SANDBOX=""; EXECUTOR=""; EXECUTOR_MODE=""; EXECUTOR_EFFORT=""; EXECUTOR_COMMAND=""; EXECUTOR_ARGS=""
  : > "$WORK/brief.md"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_header" = 1 ]; then
      if [ -z "$line" ]; then in_header=0; continue; fi
      case "$line" in
        NAME:*|MODE:*|EFFORT:*|MODEL:*|BASE:*|WRITE:*|THREAD:*|SIBLINGS:*|CWD:*|SANDBOX:*|EXECUTOR:*|EXECUTOR_MODE:*|EXECUTOR_EFFORT:*|EXECUTOR_COMMAND:*|EXECUTOR_ARGS:*)
          key=${line%%:*}; val=${line#*:}; val=${val#"${val%%[![:space:]]*}"}
          printf -v "$key" '%s' "$val" ;;
        *) in_header=0; printf '%s\n' "$line" >> "$WORK/brief.md" ;;
      esac
    else
      printf '%s\n' "$line" >> "$WORK/brief.md"
    fi
  done < "$1"
  CWD="${CWD:-$PWD}"
}

# The note prepended to investigate/implement briefs so Codex knows who started it.
director_note() {
  cat <<'EOF'
## Who you are working with
You were started by an automated director agent (Claude Code), not by a human. The director wrote the brief below and reads your final message; no human is watching this thread.
EOF
  # request_user_input and notify_director are Codex tools; another executor has
  # neither, and naming them would send it looking for tools it does not have.
  if [ -z "$EXECUTOR" ] || [ "$EXECUTOR" = codex ]; then
    cat <<'EOF'
- When you need a decision, missing information, or authorization, call request_user_input. The director answers it.
EOF
  else
    cat <<'EOF'
- When you need a decision, missing information, or authorization, ask for it however this agent asks the user. The director answers it.
EOF
  fi
  if { [ -z "$EXECUTOR" ] || [ "$EXECUTOR" = codex ]; } && grep -rq 'notify_director' "$(dirname "$CC")"; then
    cat <<'EOF'
- notify_director(message) sends a one-line note to the director without stopping your work. Use it only when you reach a conclusion that changes the plan (root cause found, scope larger than briefed, a blocker you are working around) or finish a phase the director could act on while you continue. Do not report routine progress. The director does not reply through this tool.
EOF
  fi
  cat <<EOF
- Other tasks started by the same director may be running in this workspace. Do not coordinate with them yourself; tell the director what they need to know in your final message.
- Other tasks currently running: ${SIBLINGS:-none known}

---- Brief ----
EOF
}

task_effort() {  # $1 default
  printf '%s\n' "${EFFORT:-$1}"
}

do_launch() {
  local input="$1"
  # Every launch gets its own work directory: several dispatch files may sit in one
  # folder and be launched at the same time, so nothing is written next to the input.
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/dispatch.sh.XXXXXX")
  cp "$input" "$WORK/input.md"
  parse_input "$WORK/input.md"
  if [ -z "$NAME" ]; then
    echo 'NAME_REQUIRED: add a NAME: header with a few words that say what this task does (for example "worker answer subcommand")'; exit 1
  fi
  NAME=$(python3 -c 'import sys; print(sys.argv[1][:80])' "$NAME")
  # Codex probes its own CLI inside CWD, so a path that does not exist is reported as a missing Codex install.
  if [ ! -d "$CWD" ]; then
    echo "CWD_NOT_FOUND: $CWD does not exist; fix the CWD: header (it must be an absolute path to an existing directory)"; exit 1
  fi
  CC=$(select_companion)
  if [ -z "$CC" ]; then echo "CODEX_FAILED: no codex-companion.mjs found under ~/.claude/plugins/cache"; exit 1; fi
  printf '%s\n' "$CC" > "$WORK/companion"
  printf '%s\n' "$CWD" > "$WORK/cwd"
  printf '%s\n' "$NAME" > "$WORK/name"

  # Settled before the note is written: director_note tells the agent which
  # tools it has, and a default coming from the environment would otherwise
  # reach an ACP agent describing Codex's.
  EXECUTOR="${EXECUTOR:-${CODEX_DIRECTOR_EXECUTOR:-codex}}"

  local CMD=() FOCUS CAND
  case "$MODE" in
    investigate)
      { director_note; cat "$WORK/brief.md"; } > "$WORK/prompt.md"
      CMD=(node "$CC" task --cwd "$CWD" --prompt-file "$WORK/prompt.md" --effort "$(task_effort high)") ;;
    implement)
      { director_note; cat "$WORK/brief.md"; } > "$WORK/prompt.md"
      CMD=(node "$CC" task --cwd "$CWD" --prompt-file "$WORK/prompt.md" --effort "$(task_effort high)" --write) ;;
    continue)
      cp "$WORK/brief.md" "$WORK/prompt.md"
      if [ -n "$THREAD" ] && grep -q '"thread"' "$CC"; then
        CMD=(node "$CC" task --cwd "$CWD" --thread "$THREAD" --prompt-file "$WORK/prompt.md")
      else
        CAND=$(node "$CC" task-resume-candidate --cwd "$CWD" --json 2>/dev/null | python3 -c 'import json,sys; print(((json.load(sys.stdin).get("candidate") or {}).get("threadId")) or "")')
        if [ -n "$THREAD" ] && [ "$CAND" != "$THREAD" ]; then
          echo "THREAD_MISMATCH: requested $THREAD but this plugin version can only resume its most recent task thread in this repo, which is ${CAND:-none}. Dispatch a fresh task instead, or continue without THREAD." > "$WORK/note"
          CMD=(false)
        else
          CMD=(node "$CC" task --cwd "$CWD" --resume-last --prompt-file "$WORK/prompt.md")
        fi
      fi
      [ -n "$EFFORT" ] && CMD+=(--effort "$EFFORT")
      [ "$WRITE" = yes ] && CMD+=(--write) ;;
    review|adversarial-review)
      FOCUS=""
      [ "$MODE" = adversarial-review ] && FOCUS="$(tr '\n' ' ' < "$WORK/brief.md")"
      if [ -n "$BASE" ]; then
        CMD=(node "$CC" "$MODE" --cwd "$CWD" --wait --scope branch --base "$BASE" ${FOCUS:+"$FOCUS"})
      elif [ "$(git -C "$CWD" ls-files --others --exclude-standard | wc -l)" -le 3 ]; then
        CMD=(node "$CC" "$MODE" --cwd "$CWD" --wait ${FOCUS:+"$FOCUS"})
      else
        {
          echo 'You are performing a code review. The working tree contains many untracked files; do not treat them as part of this change.'
          echo 'First determine the scope of the change yourself with git status --short and git diff (including --cached). If the brief below lists files, the brief takes precedence.'
          echo 'Report in review form: each finding with file:line, what can go wrong, the impact, and the concrete fix; ordered by severity. If there are no material findings, say so explicitly.'
          echo 'Read-only. Do not modify any file.'
          [ "$MODE" = adversarial-review ] && echo 'Take an adversarial stance: assume the change fails in subtle, high-cost ways. Focus on trust boundaries, data loss or duplication, retries and idempotency, concurrency and ordering, empty/timeout/degraded paths, and compatibility.'
          echo; echo '---- Brief ----'; cat "$WORK/brief.md"
        } > "$WORK/prompt.md"
        echo 'NOTE: too many untracked files; fell back to a read-only task for this review' > "$WORK/note"
        CMD=(node "$CC" task --cwd "$CWD" --prompt-file "$WORK/prompt.md" --effort high)
      fi ;;
    *)
      echo "CODEX_FAILED: unknown MODE '${MODE}'"; exit 1 ;;
  esac
  # --model is Codex's; for another executor MODEL names that agent's own model
  # and is passed as --executor-model below.
  [ -n "$MODEL" ] && [ "$EXECUTOR" = codex ] && CMD+=(--model "$MODEL")

  # EXECUTOR picks which agent runs the task. `codex` (the default) keeps every
  # existing flag; `qoder` runs qodercli over ACP, and `acp` is any other ACP
  # agent, which then needs EXECUTOR_COMMAND.
  if [ "$EXECUTOR" = codex ] && [ "${CMD[2]:-}" = task ] && grep -q 'executor-command' "$CC"; then
    # Named rather than left to the companion's default, which reads
    # $CODEX_COMPANION_EXECUTOR: an inherited value would otherwise quietly
    # overrule a brief that asked for Codex.
    CMD+=(--executor codex)
  fi
  if [ "$EXECUTOR" != codex ]; then
    # Gate on the mode that was asked for, not on the command that was built:
    # a review with more than three untracked files is rebuilt as a task, which
    # would otherwise let a review through to an agent that must not run one.
    case "$MODE" in
      investigate|implement|continue) ;;
      *) echo "CODEX_FAILED: EXECUTOR: $EXECUTOR only runs task-class modes (investigate, implement, continue); MODE: $MODE is Codex-only"; exit 1 ;;
    esac
    if ! grep -q 'executor-command' "$CC"; then
      echo "CODEX_FAILED: the installed plugin has no --executor support; install a newer plugin, or point CODEX_COMPANION at a checkout that has it"; exit 1
    fi
    case "$EXECUTOR" in
      qoder)
        EXECUTOR_COMMAND="${EXECUTOR_COMMAND:-${CODEX_DIRECTOR_QODER_COMMAND:-}}"
        if [ -z "$EXECUTOR_COMMAND" ]; then
          EXECUTOR_COMMAND=$(command -v qoder || true)
          [ -z "$EXECUTOR_COMMAND" ] && [ -x "$HOME/.qoder/entry/qoder" ] && EXECUTOR_COMMAND="$HOME/.qoder/entry/qoder"
        fi
        if [ -z "$EXECUTOR_COMMAND" ]; then
          echo "CODEX_FAILED: qoder not found; put it on PATH or set CODEX_DIRECTOR_QODER_COMMAND"; exit 1
        fi
        CMD+=(--executor acp --executor-command "$EXECUTOR_COMMAND" --executor-args '["--acp"]')
        # Qoder remembers the model each session ran on and reuses it for the
        # next one, so a single `MODEL: ultimate` job would quietly put every
        # later dispatch that names no model on Opus 5. Name the cheap default
        # the skill documents instead of inheriting whatever ran last. A
        # continue is left alone: its thread was created on some model, and
        # switching it mid-thread is not what "no MODEL header" asks for.
        if [ "$MODE" != continue ] && [ -z "$MODEL" ]; then MODEL=dfmodel; fi
        # Same standing policy as Codex's danger-full-access: a dispatched task
        # must not stall on a permission prompt no human is watching.
        EXECUTOR_MODE="${EXECUTOR_MODE:-${CODEX_DIRECTOR_EXECUTOR_MODE:-yolo}}" ;;
      acp)
        EXECUTOR_COMMAND="${EXECUTOR_COMMAND:-${CODEX_COMPANION_ACP_COMMAND:-}}"
        if [ -z "$EXECUTOR_COMMAND" ]; then
          echo "CODEX_FAILED: EXECUTOR: acp needs EXECUTOR_COMMAND or CODEX_COMPANION_ACP_COMMAND"; exit 1
        fi
        CMD+=(--executor acp --executor-command "$EXECUTOR_COMMAND")
        [ -n "${EXECUTOR_ARGS:-}" ] && CMD+=(--executor-args "$EXECUTOR_ARGS")
        # Mode ids are the agent's own, so an unknown agent gets no default.
        EXECUTOR_MODE="${EXECUTOR_MODE:-${CODEX_DIRECTOR_EXECUTOR_MODE:-}}" ;;
      *)
        echo "CODEX_FAILED: EXECUTOR must be 'codex', 'qoder' or 'acp', got '$EXECUTOR'"; exit 1 ;;
    esac
    [ -n "$EXECUTOR_MODE" ] && CMD+=(--executor-mode "$EXECUTOR_MODE")
    [ -n "$MODEL" ] && CMD+=(--executor-model "$MODEL")
    # EFFORT is the reasoning budget of a Codex dispatch and means nothing to
    # another agent, so it is not what sets the rung here: EXECUTOR_EFFORT is,
    # and it asks for the most the model has. Which rungs exist depends on the
    # model the agent ends up on, and only the agent knows them: qoder's
    # ultimate has xhigh, its dfmodel stops at max. So the intent goes out as
    # written and the driver settles it against the options it actually reports.
    EXECUTOR_EFFORT="${EXECUTOR_EFFORT:-${CODEX_DIRECTOR_EXECUTOR_EFFORT:-xhigh}}"
    CMD+=(--executor-effort "$EXECUTOR_EFFORT")
    # --effort above is Codex's; rebuild without it so the agent is not handed
    # both (unset would leave holes that set -u then trips over).
    local kept=() skip=0 arg
    for arg in "${CMD[@]}"; do
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      if [ "$arg" = --effort ]; then skip=1; continue; fi
      kept+=("$arg")
    done
    CMD=("${kept[@]}")
  fi
  if [ "${CMD[2]:-}" = task ]; then
    # Policy: Codex tasks run without a sandbox (full read/write and network) unless the header says otherwise.
    # Read-only intent is expressed in the brief, not enforced by the sandbox.
    local explicit="$SANDBOX"; SANDBOX="${SANDBOX:-full}"
    if grep -rq 'danger-full-access' "$(dirname "$CC")"; then
      case "$SANDBOX" in
        full)    CMD+=(--sandbox danger-full-access) ;;
        network) CMD+=(--sandbox workspace-write --network) ;;
        default) ;;   # keep the plugin's own default (read-only, or workspace-write with --write)
        *)       echo "CODEX_FAILED: SANDBOX must be 'full', 'network' or 'default', got '$SANDBOX'"; exit 1 ;;
      esac
    elif [ -n "$explicit" ]; then
      echo "NOTE: the installed plugin has no --sandbox/--network options; SANDBOX: $explicit was ignored and Codex ran in the plugin's default sandbox" > "$WORK/note"
    fi
  fi

  if grep -q '"label"' "$CC"; then
    CMD+=(--label "$NAME")
  else
    echo 'NOTE: the installed plugin ignores NAME (no --label support)' >> "$WORK/note"
  fi

  echo "WORK=$WORK"
  if [ "${CMD[2]:-}" = task ] && grep -q 'case "message":' "$CC"; then
    if "${CMD[@]}" --background --json > "$WORK/launch.json" 2> "$WORK/log"; then
      python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["jobId"])' "$WORK/launch.json" > "$WORK/job"
      echo "JOB=$(cat "$WORK/job")"
    else
      cat "$WORK/log"; exit 1
    fi
  else
    ( nohup "${CMD[@]}" > "$WORK/out.txt" 2> "$WORK/log" < /dev/null; echo $? > "$WORK/exit" ) > /dev/null 2>&1 < /dev/null & disown
  fi
  echo "STARTED"
}

do_collect() {
  WORK="$1"
  if [ -f "$WORK/job" ]; then
    python3 - "$WORK" <<'PY' || return 1
import json, pathlib, subprocess, sys, time
work = pathlib.Path(sys.argv[1])
cc, job_id, cwd = [(work / name).read_text().strip() for name in ("companion", "job", "cwd")]
name = (work / "name").read_text().rstrip("\n") if (work / "name").exists() else ""
if not job_id:
    print("STATUS: failed\nJOB: \nNAME: " + name + "\nTHREAD: \nERROR: launch returned no job id; dispatch again")
    sys.exit(1)
deadline = time.monotonic() + 10
while True:
    try:
        raw = subprocess.check_output(["node", cc, "status", job_id, "--cwd", cwd, "--json"], stderr=subprocess.DEVNULL)
        job = json.loads(raw)["job"]
    except (subprocess.CalledProcessError, ValueError, KeyError):
        # status unavailable: report started as before and let the monitor take over
        print("STATUS: started\nJOB: " + job_id + "\nNAME: " + name + "\nTHREAD: ")
        sys.exit(0)
    (work / "status.json").write_bytes(raw)
    status = job["status"]
    if status not in ("queued", "running") or (status == "running" and job.get("threadId")):
        break
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        break
    time.sleep(min(1, remaining))
failed = status not in ("queued", "running", "completed")
print("STATUS: " + ("failed" if failed else "started"))
print("JOB: " + job_id)
print("NAME: " + name)
print("THREAD: " + (job.get("threadId") or ""))
if failed:
    error = job.get("errorMessage") or ((job.get("result") or {}).get("error") or {}).get("message")
    if not error:
        result = subprocess.check_output(["node", cc, "result", job_id, "--cwd", cwd, "--json"], stderr=subprocess.DEVNULL)
        stored = json.loads(result).get("storedJob") or {}
        error = stored.get("errorMessage") or ((stored.get("result") or {}).get("error") or {}).get("message")
    print("ERROR: " + (error or status).splitlines()[0])
    sys.exit(1)
PY
  else
    # Detached path (review modes): no job id at launch; the monitor's DONE/FAILED event carries it.
    echo "STATUS: started"; echo "JOB: "; echo "NAME: $(cat "$WORK/name" 2>/dev/null)"; echo "THREAD: "
    echo "NOTE: started detached without a job id; the monitor's DONE/FAILED event carries it, then read the output with result <job-id>"
  fi
  [ -f "$WORK/note" ] && cat "$WORK/note"
  return 0
}

# dispatch [input-file]: launch, then collect. The brief comes from the file or from stdin.
do_dispatch() {
  local input="${1:-}" launched
  if [ -z "$input" ]; then
    input=$(mktemp -d "${TMPDIR:-/tmp}/dispatch.sh.XXXXXX")/input.md
    cat > "$input"
  fi
  # launch prints WORK= / JOB= / STARTED for the building-block flow; dispatch reports only collect's lines.
  launched=$(do_launch "$input") || { printf '%s\n' "$launched"; return 1; }
  WORK=$(printf '%s\n' "$launched" | sed -n 's/^WORK=//p')
  do_collect "$WORK"
}

do_events() {
  local CC
  CC=$(select_companion)
  if [ -z "$CC" ] || ! grep -q 'case "events":' "$CC"; then
    echo "EVENTS_UNSUPPORTED: the installed plugin has no events subcommand; install a plugin version that has it"
    exit 2
  fi
  exec node "$CC" events "$@"
}

do_follow() {
  local CC
  CC=$(select_companion)
  if [ -z "$CC" ] || ! grep -q '"observe"' "$CC"; then
    echo "FOLLOW_UNSUPPORTED: the installed plugin has no observe subcommand; install a plugin version that has it"
    exit 2
  fi
  exec node "$CC" observe follow "$@"
}

do_message() {
  local CC cwd="$PWD" job="${1:-unknown}" args=() mode=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cwd) [ "$#" -ge 2 ] || { echo "MESSAGE_FAILED job=$job usage: --cwd <repo>"; return 1; }; cwd="$2"; shift 2 ;;
      --interrupt|--queue)
        if [ "${#mode[@]}" -gt 0 ]; then
          echo "MESSAGE_FAILED job=$job --interrupt and --queue are two different intents; pass one"; return 1
        fi
        mode=("$1"); shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  job="${args[0]:-unknown}"
  if [ "${#args[@]}" -ne 2 ]; then
    echo "MESSAGE_FAILED job=$job usage: dispatch.sh message <job-id> <prompt-file> [--cwd <repo>] [--interrupt|--queue]"; return 1
  fi
  CC=$(select_companion)
  if [ -z "$CC" ] || ! grep -q 'case "message":' "$CC" 2>/dev/null; then
    echo "MESSAGE_UNSUPPORTED: the installed plugin has no message subcommand; install a plugin version that has it"
    return 2
  fi
  node - "$CC" "$cwd" "${args[@]}" ${mode[@]+"${mode[@]}"} <<'NODE'
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const [cc, cwd, job, file, ...flags] = process.argv.slice(2);
try {
  const reply = execFileSync(process.execPath, [cc, "message", job, "--prompt-file", path.resolve(cwd, file), "--cwd", cwd, ...flags],
    // The default 1 MiB buffer is smaller than a result carrying a turn's
    // partial changes, and an overflow does not just lose the reply: Node kills
    // the companion, so an interrupt already sent is reported as a failure.
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
  // A queued message runs its turn as a job of its own, and that id is the only
  // handle on it: dropped here, the director first heard of the turn when a DONE
  // arrived for an id it had never been given.
  let queued = null;
  try { queued = JSON.parse(reply).queuedJobId ?? null; } catch {}
  console.log(`MESSAGED job=${job}${queued ? ` queued=${queued}` : ""}`);
} catch (error) {
  const detail = String(error.stderr || error.message).trim().split(/\r?\n/)[0];
  // A failed `--interrupt` does not mean nothing happened: the cancel may have
  // reached the agent and only the reply been lost. Saying "failed" alone reads
  // as "the task is untouched", which is how a running task gets abandoned.
  const note = flags.includes("--interrupt") ? " (the turn may already have been cancelled; check status)" : "";
  console.log(`MESSAGE_FAILED job=${job} ${detail}${note}`);
  process.exit(1);
}
NODE
}

do_answer() {
  local CC cwd="$PWD" args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cwd) [ "$#" -ge 2 ] || { echo 'usage: --cwd <repo>'; return 1; }; cwd="$2"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [ "${#args[@]}" -ne 3 ]; then
    echo 'usage: dispatch.sh answer <job-id> <request-id> <answers-file> [--cwd <repo>]'; return 1
  fi
  CC=$(select_companion)
  node - "$CC" "$cwd" "${args[@]}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const [cc, cwd, job, request, file] = process.argv.slice(2);
const prefix = `ANSWER_FAILED job=${job} request=${request}`;
try {
  if (!cc) throw new Error("no codex-companion.mjs found under ~/.claude/plugins/cache");
  const run = (...args) => execFileSync(process.execPath, [cc, ...args, "--cwd", cwd],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
  const pending = () => {
    const live = JSON.parse(run("status", job, "--json")).job.live;
    if (live?.unavailable) throw new Error(live.unavailable);
    return live?.questions ?? [];
  };
  const requests = pending();
  const question = requests.find((item) => String(item.requestId) === request);
  if (!question) {
    console.log(`${prefix} no pending question with that request id`);
    if (requests.length) console.log(`pending: ${requests.map((item) => item.requestId).join(" ")}`);
    process.exit(1);
  }
  const answersFile = path.resolve(cwd, file);
  const answers = JSON.parse(fs.readFileSync(answersFile, "utf8"));
  if (!answers || typeof answers !== "object" || Array.isArray(answers)) throw new Error("answers file must be a JSON map");
  const expected = question.questions.map((item) => item.id).sort();
  const got = Object.keys(answers).sort();
  if (JSON.stringify(expected) !== JSON.stringify(got)) {
    console.log(`${prefix} answer keys do not match question ids\nexpected: ${expected.join(" ")}\ngot: ${got.join(" ")}`);
    process.exit(1);
  }
  if (!expected.every((id) => Array.isArray(answers[id]?.answers) && answers[id].answers.length > 0 &&
    answers[id].answers.every((answer) => typeof answer === "string" && answer.trim()))) {
    throw new Error("each question requires a nonempty answers array of nonempty strings");
  }
  run("answer", job, "--request-id", request, "--answers-file", answersFile);
  if (pending().some((item) => String(item.requestId) === request)) throw new Error("still pending after answer");
  console.log(`ANSWERED job=${job} request=${request}`);
} catch (error) {
  const detail = String(error.stderr || error.message).trim().split(/\r?\n/)[0];
  console.log(`${prefix} ${detail}`);
  process.exit(1);
}
NODE
}

case "${1:-}" in
  dispatch)  do_dispatch "${2:-}" ;;
  launch)    [ "$#" -ge 2 ] || { echo "usage: dispatch.sh launch <input-file>"; exit 1; }; do_launch "$2" ;;
  collect)   [ "$#" -ge 2 ] || { echo "usage: dispatch.sh collect <WORK>"; exit 1; }; do_collect "$2" ;;
  companion) select_companion ;;
  events)    shift; do_events "$@" ;;
  follow)    shift; do_follow "$@" ;;
  message)   shift; do_message "$@" ;;
  answer)    shift; do_answer "$@" ;;
  *) echo "usage: dispatch.sh dispatch [input-file] | launch <input-file> | collect <WORK> | companion | events --cwd <repo> | follow <job-id> --cwd <repo> [--after <cursor>] | message <job-id> <prompt-file> [--cwd <repo>] [--interrupt] | answer <job-id> <request-id> <answers-file> [--cwd <repo>]"; exit 1 ;;
esac
