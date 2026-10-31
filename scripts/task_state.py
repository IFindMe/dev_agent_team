#!/usr/bin/env python3
"""Concurrent-safe task-state helper for Dev Agent Team (Python standard library only)."""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import re
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterator

AGENTS = {
    "architect", "builder", "designer", "detective", "explorer", "maintainer",
    "orchestrator", "philosopher", "reviewer", "tester", "toolsmith",
    "tracker", "workflow-architect", "writer",
}
STATUSES = {
    "planned", "queued", "running", "waiting_agent", "waiting_tool",
    "waiting_verification", "blocked", "repairing", "completed", "failed", "cancelled",
}
TRANSITIONS = {
    "planned": {"queued", "cancelled"},
    "queued": {"running", "blocked", "cancelled"},
    "running": {"waiting_agent", "waiting_tool", "waiting_verification", "blocked", "repairing", "completed", "failed", "cancelled"},
    "waiting_agent": {"running", "blocked", "failed", "cancelled"},
    "waiting_tool": {"running", "blocked", "failed", "cancelled"},
    "waiting_verification": {"completed", "repairing", "blocked", "failed"},
    "blocked": {"queued", "running", "cancelled"},
    "repairing": {"running", "waiting_verification", "blocked", "failed", "cancelled"},
    "failed": {"queued", "cancelled"},
    "completed": set(),
    "cancelled": set(),
}
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
REASON_REQUIRED = {"blocked", "failed", "cancelled", "completed"}


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def require_id(value: str, label: str) -> str:
    if not ID_RE.fullmatch(value):
        raise ValueError(f"invalid {label}: use 1-64 letters, digits, dot, underscore, or hyphen")
    return value


def paths(root: Path, workflow_id: str) -> tuple[Path, Path, Path]:
    require_id(workflow_id, "workflow ID")
    directory = root / ".tasks" / workflow_id
    return directory, directory / "tasks.json", directory / "events.jsonl"


@contextlib.contextmanager
def locked(directory: Path) -> Iterator[None]:
    directory.mkdir(parents=True, exist_ok=True)
    lock_path = directory / ".lock"
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        dir_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)
        raise


def append_event(path: Path, event: dict[str, Any]) -> None:
    payload = (json.dumps(event, sort_keys=True) + "\n").encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        with os.fdopen(fd, "ab") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        # fdopen closes the descriptor on success; close it defensively on failure.
        with contextlib.suppress(OSError):
            os.close(fd)


def load_state(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"workflow not initialized: {path}")
    with path.open("r", encoding="utf-8") as stream:
        data = json.load(stream)
    if not isinstance(data, dict):
        raise ValueError("tasks.json must contain a JSON object")
    return data


def validate_report_path(value: str, workflow_id: str, owner: str, task_id: str) -> None:
    p = PurePosixPath(value)
    if p.is_absolute() or ".." in p.parts or len(p.parts) != 4:
        raise ValueError("report path must be a safe relative path under .opencode/reports/<workflow-id>/")
    if p.parts[:3] != (".opencode", "reports", workflow_id):
        raise ValueError("report path must be under this workflow's .opencode/reports directory")
    if not p.name.startswith(f"{owner}-agent-{task_id}-") or not p.name.endswith(".md"):
        raise ValueError("report filename must be <owner>-agent-<task-id>-<report-name>.md")


def validate_state(data: dict[str, Any], workflow_id: str) -> list[str]:
    errors: list[str] = []
    if data.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if data.get("workflow_id") != workflow_id:
        errors.append("workflow_id does not match requested workflow")
    if not isinstance(data.get("goal"), str) or not data["goal"].strip():
        errors.append("goal must be a non-empty string")
    if data.get("status") not in {"active", "completed", "blocked", "cancelled"}:
        errors.append("invalid workflow status")
    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        return errors + ["tasks must be an array"]
    by_id: dict[str, dict[str, Any]] = {}
    required = {"id", "title", "objective", "status", "owner", "depends_on", "scope", "inputs",
                "expected_output", "verification", "report_path", "created_at", "updated_at"}
    for index, task in enumerate(tasks):
        prefix = f"tasks[{index}]"
        if not isinstance(task, dict):
            errors.append(f"{prefix} must be an object")
            continue
        missing = required - task.keys()
        if missing:
            errors.append(f"{prefix} missing: {', '.join(sorted(missing))}")
            continue
        task_id = task["id"]
        if not isinstance(task_id, str) or not ID_RE.fullmatch(task_id):
            errors.append(f"{prefix}.id is invalid")
            continue
        if task_id in by_id:
            errors.append(f"duplicate task ID: {task_id}")
        by_id[task_id] = task
        if not isinstance(task["status"], str) or task["status"] not in STATUSES:
            errors.append(f"{prefix}.status is invalid")
        if not isinstance(task["owner"], str) or task["owner"] not in AGENTS:
            errors.append(f"{prefix}.owner is invalid")
        if not isinstance(task["title"], str) or not task["title"].strip():
            errors.append(f"{prefix}.title must be non-empty")
        if not isinstance(task["objective"], str) or not task["objective"].strip():
            errors.append(f"{prefix}.objective must be non-empty")
        if (not isinstance(task["depends_on"], list)
                or not all(isinstance(item, str) for item in task["depends_on"])
                or len(set(task["depends_on"])) != len(task["depends_on"])):
            errors.append(f"{prefix}.depends_on must be a unique array of task IDs")
        if not isinstance(task["expected_output"], list) or not task["expected_output"]:
            errors.append(f"{prefix}.expected_output must be a non-empty array")
        if not isinstance(task["verification"], list) or not task["verification"]:
            errors.append(f"{prefix}.verification must be a non-empty array")
        scope = task["scope"]
        if not isinstance(scope, dict) or not isinstance(scope.get("in_scope"), list) or not isinstance(scope.get("out_of_scope"), list):
            errors.append(f"{prefix}.scope must contain in_scope and out_of_scope arrays")
        try:
            validate_report_path(task["report_path"], workflow_id, task["owner"], task_id)
        except (TypeError, ValueError) as exc:
            errors.append(f"{prefix}.report_path: {exc}")
    for task_id, task in by_id.items():
        for dep in task.get("depends_on", []):
            if dep not in by_id:
                errors.append(f"{task_id} depends on missing task {dep}")
            if dep == task_id:
                errors.append(f"{task_id} cannot depend on itself")
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(task_id: str) -> None:
        if task_id in visiting:
            errors.append(f"dependency cycle includes {task_id}")
            return
        if task_id in visited or task_id not in by_id:
            return
        visiting.add(task_id)
        for dep in by_id[task_id].get("depends_on", []):
            visit(dep)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in by_id:
        visit(task_id)
    return errors


def event(workflow_id: str, kind: str, task_id: str | None, before: str | None,
          after: str, reason: str) -> dict[str, Any]:
    return {
        "event_id": uuid.uuid4().hex,
        "timestamp": now(),
        "workflow_id": workflow_id,
        "type": kind,
        "task_id": task_id,
        "from_status": before,
        "to_status": after,
        "reason": reason,
        "actor": "tracker",
    }


def command_init(args: argparse.Namespace) -> None:
    workflow_id = require_id(args.workflow_id, "workflow ID")
    directory, state_path, event_path = paths(Path.cwd(), workflow_id)
    with locked(directory):
        if state_path.exists():
            raise FileExistsError(f"workflow already exists: {state_path}")
        timestamp = now()
        data = {
            "schema_version": 1, "workflow_id": workflow_id, "goal": args.goal.strip(),
            "status": "active", "created_at": timestamp, "updated_at": timestamp, "tasks": [],
        }
        if not data["goal"]:
            raise ValueError("goal must not be empty")
        atomic_json(state_path, data)
        append_event(event_path, event(workflow_id, "workflow.created", None, None, "active", data["goal"]))
    print(f"Initialized .tasks/{workflow_id}/tasks.json")


def command_add(args: argparse.Namespace) -> None:
    workflow_id = require_id(args.workflow_id, "workflow ID")
    task_id = require_id(args.task_id, "task ID")
    if args.owner not in AGENTS:
        raise ValueError(f"unknown owner: {args.owner}")
    validate_report_path(args.report_path, workflow_id, args.owner, task_id)
    dependencies = [item for value in args.depends_on for item in value.split(",") if item]
    directory, state_path, event_path = paths(Path.cwd(), workflow_id)
    with locked(directory):
        data = load_state(state_path)
        existing_errors = validate_state(data, workflow_id)
        if existing_errors:
            raise ValueError("; ".join(existing_errors))
        if any(t.get("id") == task_id for t in data["tasks"]):
            raise ValueError(f"task already exists: {task_id}")
        existing = {t["id"] for t in data["tasks"]}
        missing = set(dependencies) - existing
        if missing:
            raise ValueError(f"dependencies must already exist: {', '.join(sorted(missing))}")
        timestamp = now()
        task = {
            "id": task_id, "title": args.title.strip(), "objective": args.objective.strip(),
            "status": "planned", "owner": args.owner, "depends_on": dependencies,
            "scope": {"in_scope": args.scope_in, "out_of_scope": args.scope_out},
            "inputs": args.input, "expected_output": args.expected_output,
            "verification": args.verification, "report_path": args.report_path,
            "created_at": timestamp, "updated_at": timestamp,
        }
        if not task["title"] or not task["objective"]:
            raise ValueError("title and objective must not be empty")
        data["tasks"].append(task)
        data["updated_at"] = timestamp
        errors = validate_state(data, workflow_id)
        if errors:
            raise ValueError("; ".join(errors))
        atomic_json(state_path, data)
        append_event(event_path, event(workflow_id, "task.created", task_id, None, "planned", task["title"]))
    print(f"Created task {task_id} (planned)")


def command_status(args: argparse.Namespace) -> None:
    workflow_id = require_id(args.workflow_id, "workflow ID")
    require_id(args.task_id, "task ID")
    if args.status not in STATUSES:
        raise ValueError(f"invalid status: {args.status}")
    directory, state_path, event_path = paths(Path.cwd(), workflow_id)
    with locked(directory):
        data = load_state(state_path)
        existing_errors = validate_state(data, workflow_id)
        if existing_errors:
            raise ValueError("; ".join(existing_errors))
        task = next((t for t in data["tasks"] if t.get("id") == args.task_id), None)
        if task is None:
            raise ValueError(f"unknown task: {args.task_id}")
        before = task["status"]
        if args.status not in TRANSITIONS[before]:
            raise ValueError(f"invalid transition: {before} -> {args.status}")
        reason = (args.reason or "").strip()
        if args.status in REASON_REQUIRED and not reason:
            raise ValueError(f"--reason is required when transitioning to {args.status}")
        if args.status in {"queued", "running"}:
            by_id = {t["id"]: t for t in data["tasks"]}
            incomplete = [dep for dep in task["depends_on"] if by_id[dep]["status"] != "completed"]
            if incomplete:
                raise ValueError(f"dependencies are not completed: {', '.join(incomplete)}")
        timestamp = now()
        task["status"] = args.status
        task["updated_at"] = timestamp
        data["updated_at"] = timestamp
        errors = validate_state(data, workflow_id)
        if errors:
            raise ValueError("; ".join(errors))
        atomic_json(state_path, data)
        append_event(event_path, event(workflow_id, "task.status_changed", args.task_id, before, args.status, reason))
    print(f"{args.task_id}: {before} -> {args.status}")


def command_show(args: argparse.Namespace) -> None:
    workflow_id = require_id(args.workflow_id, "workflow ID")
    directory, state_path, _ = paths(Path.cwd(), workflow_id)
    with locked(directory):
        data = load_state(state_path)
        errors = validate_state(data, workflow_id)
        if errors:
            raise ValueError("; ".join(errors))
        print(json.dumps(data, indent=2, sort_keys=True))


def command_validate(args: argparse.Namespace) -> None:
    workflow_id = require_id(args.workflow_id, "workflow ID")
    directory, state_path, event_path = paths(Path.cwd(), workflow_id)
    with locked(directory):
        data = load_state(state_path)
        errors = validate_state(data, workflow_id)
        if not event_path.is_file():
            errors.append("events.jsonl is missing")
        else:
            for number, line in enumerate(event_path.read_text(encoding="utf-8").splitlines(), start=1):
                try:
                    item = json.loads(line)
                    if item.get("workflow_id") != workflow_id or not item.get("event_id"):
                        errors.append(f"events.jsonl:{number} has invalid workflow_id or event_id")
                except (json.JSONDecodeError, AttributeError):
                    errors.append(f"events.jsonl:{number} is not a valid event object")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        raise ValueError(f"validation failed with {len(errors)} error(s)")
    print(f"VALID: workflow {workflow_id}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init", help="initialize a workflow")
    init.add_argument("--workflow-id", required=True)
    init.add_argument("--goal", required=True)
    init.set_defaults(func=command_init)

    add = sub.add_parser("add", help="add a planned task")
    add.add_argument("--workflow-id", required=True)
    add.add_argument("--task-id", required=True)
    add.add_argument("--title", required=True)
    add.add_argument("--objective", required=True)
    add.add_argument("--owner", required=True, choices=sorted(AGENTS))
    add.add_argument("--depends-on", action="append", default=[])
    add.add_argument("--scope-in", action="append", default=[])
    add.add_argument("--scope-out", action="append", default=[])
    add.add_argument("--input", action="append", default=[])
    add.add_argument("--expected-output", action="append", required=True)
    add.add_argument("--verification", action="append", required=True)
    add.add_argument("--report-path", required=True)
    add.set_defaults(func=command_add)

    status = sub.add_parser("set-status", help="transition a task")
    status.add_argument("--workflow-id", required=True)
    status.add_argument("--task-id", required=True)
    status.add_argument("--status", required=True, choices=sorted(STATUSES))
    status.add_argument("--reason", default="")
    status.set_defaults(func=command_status)

    show = sub.add_parser("show", help="show the authoritative workflow state")
    show.add_argument("--workflow-id", required=True)
    show.set_defaults(func=command_show)

    validate = sub.add_parser("validate", help="validate task state and event log")
    validate.add_argument("--workflow-id", required=True)
    validate.set_defaults(func=command_validate)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
