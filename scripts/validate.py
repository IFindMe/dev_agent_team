#!/usr/bin/env python3
"""Dependency-free structural validation for Dev Agent Team."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

EXPECTED_AGENTS = {
    "architect", "builder", "designer", "detective", "explorer", "maintainer",
    "orchestrator", "philosopher", "reviewer", "tester", "toolsmith",
    "tracker", "workflow-architect", "writer",
}
READ_ONLY_ROLES = {"architect", "designer", "detective", "explorer", "reviewer", "workflow-architect"}


def extract_frontmatter(content: str) -> str:
    if not content.startswith("---\n"):
        raise ValueError("missing opening YAML frontmatter delimiter")
    end = content.find("\n---", 4)
    if end < 0:
        raise ValueError("missing closing YAML frontmatter delimiter")
    return content[4:end]


def parse_rules(frontmatter: str) -> list[dict[str, str]]:
    matches = list(re.finditer(
        r'^  - action: "([^"]+)"\n    resource: "([^"]+)"\n    effect: (allow|ask|deny)$',
        frontmatter, re.MULTILINE,
    ))
    declared = frontmatter.count('  - action: "')
    if declared != len(matches):
        raise ValueError("malformed permissions rule; each rule needs action, resource, and effect")
    return [{"action": m.group(1), "resource": m.group(2), "effect": m.group(3)} for m in matches]


def has_rule(rules: list[dict[str, str]], action: str, resource: str, effect: str) -> bool:
    return any(r == {"action": action, "resource": resource, "effect": effect} for r in rules)


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    agents_dir = root / "agents"
    if not agents_dir.is_dir():
        return ["agents/ directory is missing"]
    actual = {p.stem for p in agents_dir.glob("*.md")}
    if actual != EXPECTED_AGENTS:
        errors.append(f"agent set mismatch: missing={sorted(EXPECTED_AGENTS-actual)}, unexpected={sorted(actual-EXPECTED_AGENTS)}")

    all_content: dict[str, str] = {}
    parsed: dict[str, tuple[str, list[dict[str, str]]]] = {}
    for agent_id in sorted(EXPECTED_AGENTS & actual):
        path = agents_dir / f"{agent_id}.md"
        content = path.read_text(encoding="utf-8")
        all_content[agent_id] = content
        try:
            fm = extract_frontmatter(content)
            for key in ("name", "description", "mode", "permissions"):
                if not re.search(rf"^{key}:\s*", fm, re.MULTILINE):
                    raise ValueError(f"frontmatter missing {key}:")
            if re.search(r"^permission:", fm, re.MULTILINE):
                raise ValueError("legacy singular permission: frontmatter is not supported")
            if re.search(r"^\s+(bash|task):", fm, re.MULTILINE):
                raise ValueError("legacy bash/task frontmatter key found; use shell/subagent permission actions")
            name = re.search(r"^name:\s*([a-z][a-z-]*)\s*$", fm, re.MULTILINE).group(1)
            mode = re.search(r"^mode:\s*(primary|subagent)\s*$", fm, re.MULTILINE).group(1)
            if name != agent_id:
                raise ValueError(f"frontmatter name {name!r} does not match filename")
            expected_mode = "primary" if agent_id == "orchestrator" else "subagent"
            if mode != expected_mode:
                raise ValueError(f"mode must be {expected_mode}")
            rules = parse_rules(fm)
            if not rules or rules[0] != {"action": "*", "resource": "*", "effect": "deny"}:
                raise ValueError("first permission rule must deny all actions")
            if not has_rule(rules, "external_directory", "*", "deny"):
                raise ValueError("external_directory access must be denied")
            parsed[agent_id] = (fm, rules)
        except (ValueError, AttributeError) as exc:
            errors.append(f"{path.relative_to(root)}: {exc}")

    for agent_id in READ_ONLY_ROLES:
        if agent_id not in parsed:
            continue
        _, rules = parsed[agent_id]
        if has_rule(rules, "edit", "*", "allow") or has_rule(rules, "edit", "*", "ask"):
            errors.append(f"{agent_id}: read-only role has broad edit permission")
        if not has_rule(rules, "edit", ".opencode/reports/**", "allow"):
            errors.append(f"{agent_id}: must be able to write its assigned report")

    if "orchestrator" in parsed:
        _, rules = parsed["orchestrator"]
        dispatched = {r["resource"] for r in rules if r["action"] == "subagent" and r["effect"] == "allow"}
        expected = EXPECTED_AGENTS - {"orchestrator"}
        if dispatched != expected:
            errors.append(f"orchestrator subagent allowlist mismatch: missing={sorted(expected-dispatched)}, unexpected={sorted(dispatched-expected)}")
        if any(r["action"] == "read" and r["effect"] == "allow" for r in rules):
            errors.append("orchestrator must not have project read permission")
        if any(r["action"] == "edit" and r["effect"] == "allow" for r in rules):
            errors.append("orchestrator must not have project edit permission")
        if any(r["action"] == "shell" and r["effect"] != "deny" for r in rules):
            errors.append("orchestrator must not have shell permission")

    if "tester" in parsed:
        _, rules = parsed["tester"]
        if has_rule(rules, "edit", "*", "allow"):
            errors.append("tester must not have broad production edit permission")
        if not any(r["action"] == "edit" and r["resource"] == "tests/**" and r["effect"] == "allow" for r in rules):
            errors.append("tester must be allowed to edit tests/**")

    if "toolsmith" in parsed:
        _, rules = parsed["toolsmith"]
        if not any(r["action"] == "edit" and r["resource"] == "scripts/**" and r["effect"] == "allow" for r in rules):
            errors.append("toolsmith must be allowed to edit scripts/**")

    if "tracker" in parsed:
        _, rules = parsed["tracker"]
        if not has_rule(rules, "shell", "python3 ~/.config/opencode/scripts/task_state.py *", "allow"):
            errors.append("tracker must be allowed to use the global task-state helper")
        if not has_rule(rules, "edit", ".tasks/**", "allow"):
            errors.append("tracker must own .tasks/**")
        if not has_rule(rules, "shell", "python3 .opencode/scripts/task_state.py *", "allow"):
            errors.append("tracker must be allowed to use the project task-state helper")

    if "philosopher" in parsed:
        _, rules = parsed["philosopher"]
        if not has_rule(rules, "edit", "philosophy.md", "allow"):
            errors.append("philosopher must be allowed to maintain philosophy.md")

    if "designer" in all_content and "WCAG 2.2 AA" not in all_content["designer"]:
        errors.append("designer must use WCAG 2.2 AA as its default baseline")

    if "orchestrator" in all_content:
        orchestrator = all_content["orchestrator"]
        forbidden = [
            "mandatory gateway for ALL investigation",
            "any investigation, however small → Explorer (mandatory gateway, no exceptions)",
            "do not skip Philosopher when the purpose is already clear",
        ]
        for phrase in forbidden:
            if phrase in orchestrator:
                errors.append(f"orchestrator contains contradictory routing rule: {phrase}")
        if ".opencode/reports/<workflow-id>/" not in orchestrator:
            errors.append("orchestrator report contract must use .opencode/reports/<workflow-id>/")
        route_start = orchestrator.find("## Routing Table — MANDATORY Specialist per Concern")
        route_end = orchestrator.find("\n## ", route_start + 4)
        route_section = orchestrator[route_start:route_end if route_end >= 0 else None]
        route_names = set(re.findall(r'^\|[^\n]*?\| `([a-z][a-z-]*)` \|', route_section, re.MULTILINE))
        if route_names != EXPECTED_AGENTS:
            errors.append(f"routing table agent mismatch: missing={sorted(EXPECTED_AGENTS-route_names)}, unexpected={sorted(route_names-EXPECTED_AGENTS)}")
        for referenced in re.findall(r"agents/([a-z][a-z-]*)\.md", orchestrator):
            if referenced not in EXPECTED_AGENTS:
                errors.append(f"orchestrator references missing agent file: agents/{referenced}.md")

    required_files = [
        "README.md", "SECURITY.md", "AGENTS.md", "install.sh",
        "docs/TASK_STATE.md", "schemas/tasks.schema.json",
        "scripts/task_state.py", "scripts/validate.py", "tests/test_task_state.py",
        ".github/workflows/validate.yml",
    ]
    for relative in required_files:
        if not (root / relative).is_file():
            errors.append(f"required package file missing: {relative}")

    schema_path = root / "schemas/tasks.schema.json"
    if schema_path.is_file():
        try:
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
            if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
                errors.append("tasks schema must declare JSON Schema 2020-12")
        except json.JSONDecodeError as exc:
            errors.append(f"schemas/tasks.schema.json: invalid JSON: {exc}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    errors = validate(root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"Validation failed: {len(errors)} error(s)", file=sys.stderr)
        return 1
    print("Validation passed: 14 agents, V2 permissions, routing, package files, and task schema.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
