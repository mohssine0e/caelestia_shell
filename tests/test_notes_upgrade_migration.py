import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend


class TestNotesUpgradeMigration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.path = self.root / "notes.sqlite3"
        self.patch = patch.object(notes_backend, "database_path", return_value=self.path)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def test_schema_v15_upgrade_is_additive_and_idempotent(self):
        with notes_backend.database() as db:
            # Simulate v15 rows and legacy columns before the v16 migration.
            db.execute("INSERT INTO notes (id, created_at, updated_at, raw_content, category, keep_decision) "
                       "VALUES ('n-a','2026-11-20','2026-11-20','A','technical','keep')")
            db.execute("INSERT INTO notes (id, created_at, updated_at, raw_content, category, keep_decision, related_note_ids) "
                       "VALUES ('n-b','2026-11-20','2026-11-20','B','technical','keep','[\"n-a\"]')")
            for note_id, concept_id in (("n-a", "c-a"), ("n-b", "c-b")):
                db.execute("INSERT INTO concepts (id, legacy_note_id, topic, area, title, created_at, updated_at) "
                           "VALUES (?, ?, 'Docker', 'Core', ?, '2026-11-20', '2026-11-20')",
                           (concept_id, note_id, concept_id))
            db.execute("DROP TABLE concept_relations")
            for table, column in (("concepts", "applicability"), ("blocks", "applicability"),
                                  ("blocks", "evidence_status"),
                                  ("concept_detail_proposals", "applicability"),
                                  ("concept_detail_proposals", "evidence_status"),
                                  ("concept_gap_proposals", "applicability"),
                                  ("concept_gap_proposals", "evidence_status")):
                db.execute(f"ALTER TABLE {table} DROP COLUMN {column}")
            # Simulate interruption after only part of the additive column migration.
            db.execute("ALTER TABLE concepts ADD COLUMN applicability TEXT NOT NULL DEFAULT ''")
            db.execute("ALTER TABLE concept_detail_proposals ADD COLUMN evidence_status TEXT NOT NULL DEFAULT 'unverified'")
            db.execute("PRAGMA user_version=15")
            db.commit()

        first = notes_backend.connect()
        self.assertEqual(first.execute("PRAGMA user_version").fetchone()[0], notes_backend.SCHEMA_VERSION)
        count_first = first.execute("SELECT count(*) FROM concept_relations").fetchone()[0]
        first.close()
        second = notes_backend.connect()
        count_second = second.execute("SELECT count(*) FROM concept_relations").fetchone()[0]
        self.assertEqual(count_first, 1)
        self.assertEqual(count_second, count_first)
        self.assertEqual(second.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        self.assertEqual(second.execute("SELECT raw_content FROM notes WHERE id='n-a'").fetchone()[0], "A")
        second.close()

    def test_backup_and_restore_preserve_handbook_tables(self):
        note = notes_backend.create_note({"raw_content": "Original source stays intact."})["note"]
        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, {
                "id": "c-export", "topic": "Docker", "area": "Core", "title": "Export test",
                "definition": "Definition", "applicability": "Docker 26+"
            }, [{"id": "b-export", "kind": "rule", "content": "A saved rule.",
                 "applicability": "Linux", "evidence_status": "unverified"}], source_note_id=note["id"])
            notes_backend._insert_concept_with_blocks(db, {
                "id": "c-export-2", "topic": "Docker", "area": "Core", "title": "Related",
                "definition": "Another definition"
            }, [])
            db.execute("INSERT INTO concept_reading_state (concept_id, preferred_depth, last_seen_at) "
                       "VALUES ('c-export','recall','2026-11-21T00:00:00Z')")
            db.execute("INSERT INTO concept_detail_proposals (id, concept_id, detail_kind, base_revision, content, "
                       "created_at, updated_at) VALUES ('p-export','c-export','why','rev','Proposal','now','now')")
            db.execute("INSERT INTO concept_relations (id, source_concept_id, target_concept_id, created_at, updated_at) "
                       "VALUES ('r-export','c-export','c-export-2','now','now')")
            db.commit()
        backup = self.root / "backup.sqlite3"
        restored = self.root / "restored.sqlite3"
        self.assertTrue(notes_backend.backup_database(self.path, backup)["success"])
        self.assertTrue(notes_backend.restore_database(backup, restored)["success"])
        db = sqlite3.connect(restored)
        self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        self.assertEqual(db.execute("SELECT count(*) FROM notes").fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM blocks").fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM block_sources").fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM concept_reading_state").fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM concept_detail_proposals").fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM concept_relations").fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT applicability FROM blocks WHERE id='b-export'").fetchone()[0], "Linux")
        db.close()

    def test_flag_explanation_does_not_apply_git_p_meaning_out_of_context(self):
        add_patch = notes_backend.explain_flag({"tool": "git", "subcommand": "add", "flag": "-p"})
        log_patch = notes_backend.explain_flag({"tool": "git", "subcommand": "log", "flag": "-p"})
        diff_patch = notes_backend.explain_flag({"tool": "git", "subcommand": "diff", "flag": "-p"})
        self.assertIn("choose", add_patch["explanation"])
        self.assertIn("patch introduced", log_patch["explanation"])
        self.assertNotIn("Interactively choose", diff_patch["explanation"])

    def test_search_paginates_more_than_one_thousand_concepts(self):
        with notes_backend.database() as db:
            for index in range(1005):
                notes_backend._insert_concept_with_blocks(db, {
                    "id": f"scale-{index:04d}", "topic": "Scale", "area": "Synthetic",
                    "title": f"Scale concept {index:04d}", "definition": "needle searchable content"
                }, [])
        offset = 0
        seen = 0
        while True:
            page = notes_backend.search_concepts_rpc({"query": "needle", "limit": 87, "offset": offset})
            seen += len(page["results"])
            if page["complete"]:
                break
            offset = page["next_offset"]
        self.assertEqual(page["total"], 1005)
        self.assertEqual(seen, 1005)


if __name__ == "__main__":
    unittest.main()
