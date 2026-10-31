import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install.sh"


class InstallerIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.base / "home")
        self.env["XDG_CONFIG_HOME"] = str(self.base / "config")
        self.env["XDG_STATE_HOME"] = str(self.base / "state")
        Path(self.env["HOME"]).mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def run_installer(self, *args, expect=0):
        result = subprocess.run(
            [str(INSTALLER), *map(str, args)],
            cwd=ROOT, env=self.env, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, expect, msg=result.stdout + result.stderr)
        return result

    def test_project_install_conflict_backup_and_uninstall(self):
        project = self.base / "project"
        project.mkdir()
        self.run_installer("--project", project, "--dry-run")
        self.assertFalse((project / ".opencode").exists())

        self.run_installer("--project", project)
        opencode = project / ".opencode"
        agents = opencode / "agents"
        self.assertEqual(len(list(agents.glob("*.md"))), 14)
        self.assertTrue((opencode / "scripts/task_state.py").is_file())
        self.assertTrue((opencode / "dev_agent_team.manifest").is_file())

        # A second install is idempotent and does not create backups.
        self.run_installer("--project", project)
        self.assertFalse((opencode / "backups").exists())

        builder = agents / "builder.md"
        builder.write_text("user modification\n", encoding="utf-8")
        self.run_installer("--project", project, expect=1)
        self.assertEqual(builder.read_text(encoding="utf-8"), "user modification\n")

        self.run_installer("--project", project, "--force")
        self.assertEqual(builder.read_text(encoding="utf-8"), (ROOT / "agents/builder.md").read_text(encoding="utf-8"))
        self.assertTrue(list((opencode / "backups/dev_agent_team").rglob("builder.md")))

        # Uninstall removes files still owned by the installer, but preserves edits.
        explorer = agents / "explorer.md"
        explorer.write_text("local customization\n", encoding="utf-8")
        self.run_installer("--project", project, "--uninstall")
        self.assertEqual(explorer.read_text(encoding="utf-8"), "local customization\n")
        self.assertFalse(builder.exists())
        self.assertFalse((opencode / "scripts/task_state.py").exists())
        self.assertFalse((opencode / "dev_agent_team.manifest").exists())

    def test_unmanaged_conflict_requires_force(self):
        project = self.base / "conflict-project"
        target = project / ".opencode/agents"
        target.mkdir(parents=True)
        (target / "explorer.md").write_text("user-owned\n", encoding="utf-8")
        self.run_installer("--project", project, expect=1)
        self.assertEqual((target / "explorer.md").read_text(encoding="utf-8"), "user-owned\n")
        self.run_installer("--project", project, "--force")
        self.assertEqual(
            (target / "explorer.md").read_text(encoding="utf-8"),
            (ROOT / "agents/explorer.md").read_text(encoding="utf-8"),
        )
        self.assertTrue(list((project / ".opencode/backups/dev_agent_team").rglob("explorer.md")))

    def test_global_install_uses_xdg_config_home(self):
        self.run_installer("--global")
        target = Path(self.env["XDG_CONFIG_HOME"]) / "opencode"
        self.assertEqual(len(list((target / "agents").glob("*.md"))), 14)
        self.assertTrue((target / "scripts/task_state.py").is_file())
        self.run_installer("--global", "--uninstall")
        self.assertFalse((target / "agents/explorer.md").exists())
        self.assertFalse((target / "scripts/task_state.py").exists())


if __name__ == "__main__":
    unittest.main()
