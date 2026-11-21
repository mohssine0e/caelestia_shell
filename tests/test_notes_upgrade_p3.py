import os
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from scripts import notes_backend


class TestNotesUpgradeP3(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp_dir.name) / "notes.sqlite3"
        self.patcher = patch.object(notes_backend, "database_path", return_value=self.db_path)
        self.patcher.start()
        with notes_backend.database() as db:
            pass  # Runs migrations up to SCHEMA_VERSION 13

    def tearDown(self):
        self.patcher.stop()
        self.tmp_dir.cleanup()

    def test_topic_and_area_listing(self):
        """P3.2: Listing concepts by topic and area must filter correctly."""
        c1 = {
            "id": "c-java-mem",
            "topic": "Java",
            "area": "Memory & References",
            "title": "Pass-by-value and references",
            "definition": "Java is strictly pass-by-value; reference variables copy their handle."
        }
        c2 = {
            "id": "c-java-coll",
            "topic": "Java",
            "area": "Collections",
            "title": "ConcurrentHashMap",
            "definition": "Thread-safe hash map using lock striping."
        }
        c3 = {
            "id": "c-git-cmd",
            "topic": "Git",
            "area": "Branching",
            "title": "Git Rebase",
            "definition": "Reapplies commits on top of another base tip."
        }

        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, c1, [])
            notes_backend._insert_concept_with_blocks(db, c2, [])
            notes_backend._insert_concept_with_blocks(db, c3, [])

        # List all Java
        res_java = notes_backend.list_concepts_rpc({"topic": "Java"})
        self.assertTrue(res_java.get("success"))
        java_cids = [c["id"] for c in res_java["concepts"]]
        self.assertIn("c-java-mem", java_cids)
        self.assertIn("c-java-coll", java_cids)
        self.assertNotIn("c-git-cmd", java_cids)

        # List Java Memory area
        res_mem = notes_backend.list_concepts_rpc({"topic": "Java", "area": "Memory & References"})
        self.assertTrue(res_mem.get("success"))
        mem_cids = [c["id"] for c in res_mem["concepts"]]
        self.assertEqual(mem_cids, ["c-java-mem"])

    def test_understand_vs_recall_reading_state(self):
        """P3.3: Understand mode shows full mechanism; Recall mode filters in_recall and returns expandable blocks."""
        cid = "c-read-depth"
        concept = {
            "id": cid,
            "topic": "Java",
            "area": "Memory",
            "title": "Escape Analysis",
            "definition": "Optimization technique determining if an object escapes the allocating thread."
        }
        blocks = [
            {"id": "b-rule", "concept_id": cid, "kind": "rule", "content": "Scalars can be stack-allocated.", "in_recall": 1, "sort_order": 1},
            {"id": "b-mech", "concept_id": cid, "kind": "mechanism", "content": "JIT analyzes method call graph during tier-4 compilation.", "in_recall": 0, "sort_order": 2},
            {"id": "b-caveat", "concept_id": cid, "kind": "caveat", "content": "Disabled with -XX:-DoEscapeAnalysis.", "in_recall": 1, "sort_order": 3}
        ]
        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, concept, blocks)

        # 1. Understand mode: all blocks returned in main blocks list
        view_u = notes_backend.get_concept_view(cid, mode="understand")
        self.assertEqual(len(view_u["blocks"]), 3)
        self.assertEqual(len(view_u["expandable_blocks"]), 0)

        # 2. Recall mode: only in_recall blocks in main list, mechanism in expandable_blocks
        view_r = notes_backend.get_concept_view(cid, mode="recall")
        self.assertEqual(len(view_r["blocks"]), 2)
        r_kinds = [b["kind"] for b in view_r["blocks"]]
        self.assertIn("rule", r_kinds)
        self.assertIn("caveat", r_kinds)
        self.assertNotIn("mechanism", r_kinds)
        self.assertEqual(len(view_r["expandable_blocks"]), 1)
        self.assertEqual(view_r["expandable_blocks"][0]["id"], "b-mech")

        # 3. Preference persistence
        depth_res = notes_backend.set_concept_depth_rpc({"id": cid, "depth": "recall"})
        self.assertTrue(depth_res.get("success"))
        view_saved = notes_backend.get_concept_view(cid)
        self.assertEqual(view_saved["mode"], "recall")

    def test_search_concepts_landing_and_relevance(self):
        """P3.4: Searching a term must return breadcrumb and exact matching block."""
        cid = "c-concurrency"
        concept = {
            "id": cid,
            "topic": "Java",
            "area": "Concurrency",
            "title": "Virtual Threads",
            "definition": "Lightweight threads managed by the JVM rather than the OS."
        }
        blocks = [
            {"id": "b-vt-rule", "concept_id": cid, "kind": "rule", "content": "Virtual threads are cheap to create.", "in_recall": 1, "sort_order": 1},
            {"id": "b-vt-code", "concept_id": cid, "kind": "code", "language": "java", "content": "Thread.ofVirtual().start(runnable);", "in_recall": 1, "sort_order": 2},
            {"id": "b-vt-caveat", "concept_id": cid, "kind": "caveat", "content": "Pinning occurs when running inside synchronized blocks.", "in_recall": 1, "sort_order": 3}
        ]
        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, concept, blocks)

        res = notes_backend.search_concepts_rpc({"query": "synchronized blocks"})
        self.assertTrue(res.get("success"))
        results = res.get("results", [])
        self.assertTrue(len(results) > 0)
        top = results[0]
        self.assertEqual(top["concept_id"], cid)
        self.assertEqual(top["block_id"], "b-vt-caveat")
        self.assertEqual(top["block_kind"], "caveat")
        self.assertIn("Pinning occurs", top["match_snippet"])

    def test_sync_legacy_notes_migrates_without_data_loss(self):
        """P3.5: Legacy notes must sync into concepts and blocks idempotently."""
        with notes_backend.database() as db:
            db.execute(
                """INSERT INTO notes (id, topic, category, raw_content, formatted_content, status, created_at, updated_at)
                   VALUES ('n-leg-1', 'Docker', 'technical',
                           '# Docker Volume\n\nVolumes are the preferred mechanism for persisting data.\n\n```bash\ndocker volume create my-vol\n```',
                           'Volumes persist data', 'formatted', '2026-11-20T12:00:00Z', '2026-11-20T12:00:00Z')"""
            )
            db.commit()

        sync_res = notes_backend.sync_legacy_notes_rpc({})
        self.assertTrue(sync_res.get("success"))
        self.assertGreaterEqual(sync_res.get("migrated_count", 0), 1)

        # Verify concepts table has the Docker concept
        with notes_backend.database() as db:
            row = db.execute("SELECT * FROM concepts WHERE legacy_note_id = 'n-leg-1'").fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["topic"], "Docker")
            blocks = db.execute("SELECT * FROM blocks WHERE concept_id = ?", (row["id"],)).fetchall()
            self.assertGreaterEqual(len(blocks), 1)

        # Idempotent second run
        sync_res2 = notes_backend.sync_legacy_notes_rpc({})
        self.assertEqual(sync_res2.get("migrated_count"), 0)


if __name__ == "__main__":
    unittest.main()
