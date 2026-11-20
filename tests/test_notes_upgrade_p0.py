#!/usr/bin/env python3
"""Regression and baseline fixture tests for Notes upgrade (Phase 0)."""

import os
import sys
import unittest
from pathlib import Path

# Add scripts directory to path
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import notes_backend


class TestNotesUpgradeFixtures(unittest.TestCase):
    """Ensure baseline test fixtures are established and loadable without side effects."""

    def setUp(self):
        self.fixtures_dir = REPO_ROOT / "tests" / "fixtures" / "notes_upgrade"
        self.assertTrue(self.fixtures_dir.is_dir(), "Fixtures directory must exist")

    def test_java_deep_capture_fixture(self):
        java_path = self.fixtures_dir / "java_deep_capture.txt"
        self.assertTrue(java_path.is_file(), "Java deep capture fixture must exist")
        content = java_path.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(content), 9000, "Java fixture must retain the full ~9.5k char source")
        self.assertIn("Stack vs Heap", content)
        self.assertIn("ConcurrentHashMap", content)
        self.assertIn("Virtual threads", content)

    def test_personal_text_fixture(self):
        personal_path = self.fixtures_dir / "personal_text.txt"
        self.assertTrue(personal_path.is_file())
        content = personal_path.read_text(encoding="utf-8")
        self.assertIn("moad", content.lower())

    def test_commands_fixture(self):
        cmd_path = self.fixtures_dir / "commands_capture.txt"
        self.assertTrue(cmd_path.is_file())
        content = cmd_path.read_text(encoding="utf-8")
        self.assertTrue(len(content) > 0)

    def test_error_and_reference_fixtures(self):
        err_path = self.fixtures_dir / "error_fix.txt"
        ref_path = self.fixtures_dir / "reference_links.txt"
        self.assertTrue(err_path.is_file())
        self.assertTrue(ref_path.is_file())


if __name__ == "__main__":
    unittest.main()
