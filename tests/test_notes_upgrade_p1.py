#!/usr/bin/env python3
"""Regression tests for Phase 1: Capture and merge correctness."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import notes_backend


class TestNotesUpgradeP1(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp_dir.name) / "notes.sqlite3"
        self.patcher = patch.object(notes_backend, "database_path", return_value=self.db_path)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()
        self.tmp_dir.cleanup()

    def test_smart_upsert_sensitive_content_never_calls_provider(self):
        """P1.2: Sensitive input must be saved locally without calling external AI providers."""
        sensitive_text = "My AWS secret key is AKIAIOSFODNN7EXAMPLE and secret is wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        with patch.object(notes_backend, "_run_provider") as mock_provider:
            res = notes_backend.smart_upsert({"raw_content": sensitive_text})
            mock_provider.assert_not_called()
            self.assertTrue(res.get("success"))
            self.assertEqual(res.get("action"), "create")
            note = res.get("note", {})
            self.assertEqual(note.get("local_only"), 1)
            self.assertTrue(bool(note.get("sensitive_reason")))

    def test_smart_upsert_invalid_merge_id_does_not_mutate_existing_note(self):
        """P1.4: Invalid AI merge ID must never mutate existing_summary[0]; fallback to create."""
        with notes_backend.database() as db:
            db.execute(
                """INSERT INTO notes
                   (id, created_at, updated_at, raw_content, formatted_content, topic, subconcept,
                    title, technology, status, category, keep_decision, schema_version)
                   VALUES ('target-1', '2026-01-01', '2026-01-01', 'Original Docker Note',
                           'Original formatted', 'Docker', 'Compose', 'Original Title',
                           'Docker', 'formatted', 'technical', 'keep', 12)"""
            )
        
        # Mock AI returning action="merge" with an invalid ID "non-existent-id"
        fake_ai_resp = json.dumps({
            "action": "merge",
            "existing_id": "non-existent-id",
            "updated_subconcept": "Overwritten Subconcept",
            "updated_content": "Dangerous Overwrite"
        })
        with patch.object(notes_backend, "_run_provider", return_value=(fake_ai_resp, "gemini")):
            res = notes_backend.smart_upsert({"raw_content": "New capture content"})
            self.assertTrue(res.get("success"))
            # Must NOT be a merge into target-1! Must fall back to create.
            self.assertEqual(res.get("action"), "create")
            self.assertNotEqual(res.get("note", {}).get("id"), "target-1")
            
            # Verify target-1 is completely untouched
            with notes_backend.database() as db:
                row = db.execute("SELECT * FROM notes WHERE id = 'target-1'").fetchone()
                self.assertEqual(row["raw_content"], "Original Docker Note")
                self.assertEqual(row["formatted_content"], "Original formatted")
                self.assertEqual(row["subconcept"], "Compose")

    def test_smart_upsert_valid_merge_preserves_sources_and_updates_blocks(self):
        """P1.5: Valid merge must append raw source, update essentials_json and excerpts_json."""
        with notes_backend.database() as db:
            db.execute(
                """INSERT INTO notes
                   (id, created_at, updated_at, raw_content, formatted_content, topic, subconcept,
                    title, technology, status, category, keep_decision, essentials_json, excerpts_json, schema_version)
                   VALUES ('target-2', '2026-01-01', '2026-01-01', 'Original Base Content',
                           'Original Base Formatted', 'Git', 'History', 'Git Log',
                           'Git', 'formatted', 'technical', 'keep', '[\"Original bullet 1\"]',
                           '[{\"label\": \"Original\", \"language\": \"bash\", \"content\": \"git log\"}]', 12)"""
            )

        fake_ai_resp = json.dumps({
            "action": "merge",
            "existing_id": "target-2",
            "updated_subconcept": "History & Inspection",
            "updated_content": "Updated Formatted Log",
            "mechanics": ["New mechanic: git log -p shows patch diffs"],
            "snippets": [{"label": "Patch diff", "language": "bash", "code": "git log -p"}]
        })
        with patch.object(notes_backend, "_run_provider", return_value=(fake_ai_resp, "gemini")):
            res = notes_backend.smart_upsert({"raw_content": "Additional git log -p details"})
            self.assertTrue(res.get("success"))
            self.assertEqual(res.get("action"), "merge")
            
            with notes_backend.database() as db:
                row = db.execute("SELECT * FROM notes WHERE id = 'target-2'").fetchone()
                # 1. Source preserved
                self.assertIn("Original Base Content", row["raw_content"])
                self.assertIn("Additional git log -p details", row["raw_content"])
                # 2. Essentials updated
                essentials = json.loads(row["essentials_json"])
                self.assertIn("Original bullet 1", essentials)
                self.assertTrue(any("git log -p" in e for e in essentials))
                # 3. Excerpts updated
                excerpts = json.loads(row["excerpts_json"])
                self.assertEqual(len(excerpts), 2)
                self.assertTrue(any(e.get("content") == "git log -p" for e in excerpts))

    def test_connect_does_not_mutate_database_on_read(self):
        """P1.6: Opening connection must not execute _refactor_subconcepts_internal."""
        with notes_backend.database() as db:
            db.execute(
                """INSERT INTO notes
                   (id, created_at, updated_at, raw_content, subconcept, schema_version)
                   VALUES ('row-1', '2026-01-01', '2026-01-01', 'Some note', '', 12)"""
            )
        
        # Now connect again (as a read/list would do)
        with patch.object(notes_backend, "_refactor_subconcepts_internal") as mock_refactor:
            conn = notes_backend.connect()
            conn.close()
            mock_refactor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
