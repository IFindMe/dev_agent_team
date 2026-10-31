import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("team_validate", ROOT / "scripts" / "validate.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FrontmatterValidationTests(unittest.TestCase):
    def test_all_repository_agents_validate(self):
        self.assertEqual(MODULE.validate(ROOT), [])

    def test_frontmatter_requires_delimiters(self):
        with self.assertRaises(ValueError):
            MODULE.extract_frontmatter("name: missing delimiters")

    def test_permissions_reject_missing_effect(self):
        malformed = 'permissions:\n  - action: "read"\n    resource: "*"'
        with self.assertRaises(ValueError):
            MODULE.parse_rules(malformed)

    def test_permissions_accept_valid_rules(self):
        valid = 'permissions:\n  - action: "*"\n    resource: "*"\n    effect: deny'
        self.assertEqual(
            MODULE.parse_rules(valid),
            [{"action": "*", "resource": "*", "effect": "deny"}],
        )


if __name__ == "__main__":
    unittest.main()
