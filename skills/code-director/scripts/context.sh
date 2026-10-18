#!/usr/bin/env bash
# Repository conclusions shared by every worktree. Requires only Git and Python 3.
exec python3 -c '
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid


def git(*args):
    return subprocess.check_output(["git", "-C", str(cwd), *args], stderr=subprocess.DEVNULL, text=True).strip()


def load(path):
    try:
        raw = path.read_text(encoding="utf-8")
        if not raw.startswith("---\n"):
            raise ValueError("missing frontmatter")
        header, body = raw[4:].split("\n---\n", 1)
        entry = {}
        for line in header.split("\n"):
            if line.startswith("  - "):
                value = line[4:]
                entry["files"].append(json.loads(value) if value.startswith(chr(34)) else value)
            else:
                key, value = line.split(":", 1)
                value = value.strip()
                if key == "files":
                    entry[key] = []
                else:
                    entry[key] = json.loads(value) if value.startswith(chr(34)) else value
        for key in ["id", "kind", "status", "title", "commit", "source", "supersedes", "created"]:
            if not isinstance(entry.get(key), str):
                raise ValueError("missing or invalid " + key)
        if not isinstance(entry.get("files"), list) or not all(isinstance(item, str) and "@" in item for item in entry["files"]):
            raise ValueError("missing or invalid files")
        return entry, body, raw
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise ValueError("cannot read entry " + str(path) + ": " + str(error)) from None


def write(path, entry, body):
    lines = ["---"]
    for key, value in entry.items():
        if key == "files":
            lines.append("files:")
            lines.extend("  - " + json.dumps(item, ensure_ascii=False) for item in value)
        else:
            lines.append(key + ": " + json.dumps(value, ensure_ascii=False))
    lines.extend(["---", body.rstrip(), ""])
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=entries, prefix=".", delete=False) as f:
        f.write("\n".join(lines))
    os.replace(f.name, path)


def freshness(entry):
    for item in entry["files"]:
        name, blob = item.rsplit("@", 1)
        try:
            if git("hash-object", "--", str(root / name)) != blob:
                return "可能过期"
        except subprocess.CalledProcessError:
            return "可能过期"
    return "current"


parser = argparse.ArgumentParser(description="Shared repository conclusions; file paths are relative to --cwd.")
parser.add_argument("--cwd", default=os.getcwd(), help="repository directory (default: current directory)")
commands = parser.add_subparsers(dest="command", required=True)
kinds = ["repo-map", "root-cause", "code-path", "pitfall", "decision"]
for name in ["find", "show", "save", "verify", "retract", "rules"]:
    command = commands.add_parser(name)
    command.add_argument("--cwd", default=argparse.SUPPRESS, help="repository directory")
    if name == "find":
        command.add_argument("--kind", choices=kinds)
        command.add_argument("--all", action="store_true", help="include retracted entries")
        command.add_argument("words", nargs="*")
    elif name == "save":
        command.add_argument("--kind", choices=kinds, required=True)
        command.add_argument("--title", required=True)
        command.add_argument("--files", required=True, help="comma-separated paths relative to --cwd")
        command.add_argument("--source", default="thread=" + os.environ["CODEX_THREAD_ID"] if os.environ.get("CODEX_THREAD_ID") else "")
        command.add_argument("--supersedes", default="")
    elif name == "rules":
        command.add_argument("--from", dest="start", help="main agent startup directory, when known")
        command.add_argument("--memory", help="memory index, when known")
    else:
        command.add_argument("id")
        if name == "retract":
            command.add_argument("--reason")
args = parser.parse_args()
cwd = Path(args.cwd).resolve()
try:
    root = Path(git("rev-parse", "--show-toplevel")).resolve()
    common = Path(git("rev-parse", "--git-common-dir"))
except (subprocess.CalledProcessError, FileNotFoundError):
    parser.error("not a Git repository; use --cwd <repository-directory>")
entries = (cwd / common).resolve() / "agent-context" / "entries"

try:
    if args.command == "rules":
        # Assumes Codex uses its default .git project root marker.
        directories = []
        if args.start:
            start = Path(args.start).resolve()
            directories = [directory for directory in reversed(root.parents)
                           if directory == start or directory in start.parents or start in directory.parents]
        paths = []
        for directory in directories:
            path = directory / "CLAUDE.md"
            if path.is_file():
                paths.append(path)
        directory = root
        for part in [None, *cwd.relative_to(root).parts]:
            if part is not None:
                directory = directory / part
            if not any((directory / name).is_file() for name in ["AGENTS.md", "AGENTS.override.md"]):
                path = directory / "CLAUDE.md"
                if path.is_file():
                    paths.append(path)
        seen = set()
        for path in paths:
            candidates = [path]
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line.startswith("@"):
                    imported = (path.parent / Path(line[1:]).expanduser()).resolve()
                    if imported.is_file():
                        candidates.append(imported)
            for candidate in candidates:
                candidate = candidate.resolve()
                if candidate not in seen:
                    print(candidate)
                    seen.add(candidate)
        if args.memory and Path(args.memory).is_file():
            print(Path(args.memory).resolve())
    elif args.command == "save":
        files = []
        for name in filter(None, args.files.split(",")):
            path = Path(os.path.abspath(cwd / name))
            relative = path.relative_to(root)
            files.append(str(relative) + "@" + git("hash-object", "--", str(path)))
        if not files:
            parser.error("--files must name at least one file")
        created = datetime.datetime.now(datetime.timezone.utc)
        entry_id = created.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8]
        entry = dict(id=entry_id, kind=args.kind, status="unverified", title=args.title,
                     commit=git("rev-parse", "HEAD"), files=files, source=args.source,
                     supersedes=args.supersedes, created=created.isoformat(timespec="seconds"))
        entries.mkdir(parents=True, exist_ok=True)
        write(entries / (entry_id + ".md"), entry, sys.stdin.read())
        print(entry_id)
    elif args.command == "find":
        for path in sorted(entries.glob("*.md")):
            try:
                entry, body, raw = load(path)
            except ValueError as error:
                print("context: skipping " + str(error), file=sys.stderr)
                continue
            if entry["status"] == "retracted" and not args.all:
                continue
            if args.kind and entry["kind"] != args.kind:
                continue
            if not all(word.casefold() in raw.casefold() for word in args.words):
                continue
            print("\t".join(value.replace("\t", " ").replace("\r", " ").replace("\n", " ") for value in
                              [entry["id"], entry["status"], freshness(entry), entry["title"], entry["source"]]))
    else:
        if Path(args.id).name != args.id or args.id in [".", ".."]:
            parser.error("invalid entry id")
        path = entries / (args.id + ".md")
        entry, body, raw = load(path)
        if args.command == "show":
            print("Freshness: " + freshness(entry))
            print(raw, end="")
        else:
            entry["status"] = "verified" if args.command == "verify" else "retracted"
            if args.command == "retract" and args.reason:
                entry["retraction_reason"] = args.reason
            write(path, entry, body)
            print(entry["id"] + "\t" + entry["status"])
except (OSError, ValueError, subprocess.CalledProcessError) as error:
    parser.exit(1, "context: " + str(error) + "\n")
' "$@"
