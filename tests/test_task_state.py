import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "task_state.py"


class TaskStateCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / ".opencode" / "agents").mkdir(parents=True)
        (self.root / ".opencode" / "agents" / "explorer.md").write_text("---\nname: explorer\n---\n", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args, expect=0):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=self.root, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, expect, msg=result.stdout + result.stderr)
        return result

    def init(self):
        self.run_cli("init", "--workflow-id", "sample", "--goal", "Test durable task tracking")

    def add(self, task_id="T1", depends_on=()):
        args = [
            "add", "--workflow-id", "sample", "--task-id", task_id,
            "--title", f"Task {task_id}", "--objective", "Inspect the requested scope",
            "--owner", "explorer",
            "--report-path", f".opencode/reports/sample/explorer-agent-{task_id}-investigation.md",
            "--expected-output", "Evidence-backed report",
            "--verification", "Report cites files and symbols",
        ]
        for dependency in depends_on:
            args.extend(["--depends-on", dependency])
        self.run_cli(*args)

    def test_lifecycle_and_event_log(self):
        self.init()
        self.add()
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "queued")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "running")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "waiting_verification")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "completed", "--reason", "Independent verification report: PASS")
        self.run_cli("validate", "--workflow-id", "sample")
        state = json.loads((self.root / ".tasks/sample/tasks.json").read_text(encoding="utf-8"))
        self.assertEqual(state["tasks"][0]["status"], "completed")
        events = (self.root / ".tasks/sample/events.jsonl").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(events), 6)

    def test_illegal_transition_rejected(self):
        self.init()
        self.add()
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "completed", "--reason", "not verified", expect=1)
        state = json.loads((self.root / ".tasks/sample/tasks.json").read_text(encoding="utf-8"))
        self.assertEqual(state["tasks"][0]["status"], "planned")

    def test_dependencies_gate_queueing(self):
        self.init()
        self.add("T1")
        self.add("T2", depends_on=("T1",))
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T2", "--status", "queued", expect=1)
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "queued")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "running")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "waiting_verification")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T1", "--status", "completed", "--reason", "Tests and review passed")
        self.run_cli("set-status", "--workflow-id", "sample", "--task-id", "T2", "--status", "queued")

    def test_unsafe_report_path_rejected(self):
        self.init()
        result = self.run_cli(
            "add", "--workflow-id", "sample", "--task-id", "T1",
            "--title", "Bad path", "--objective", "Reject traversal", "--owner", "explorer",
            "--report-path", ".opencode/reports/sample/../../outside.md",
            "--expected-output", "No task", "--verification", "Command fails",
            expect=1,
        )
        self.assertIn("report path", result.stderr)

    def test_duplicate_task_id_rejected(self):
        self.init()
        self.add()
        self.run_cli(
            "add", "--workflow-id", "sample", "--task-id", "T1",
            "--title", "Duplicate", "--objective", "Must fail", "--owner", "explorer",
            "--report-path", ".opencode/reports/sample/explorer-agent-T1-other.md",
            "--expected-output", "No duplicate", "--verification", "Command fails",
            expect=1,
        )


if __name__ == "__main__":
    unittest.main()
