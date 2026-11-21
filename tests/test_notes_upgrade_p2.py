#!/usr/bin/env python3
"""Regression and behavior tests for Phase 2: Structured depth without losing detail."""

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


class TestNotesUpgradeP2(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp_dir.name) / "notes.sqlite3"
        self.patcher = patch.object(notes_backend, "database_path", return_value=self.db_path)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()
        self.tmp_dir.cleanup()

    def test_schema_version_13_tables_exist(self):
        """P2.1: Schema v13 must create concepts, blocks, block_sources, and concept_reading_state."""
        with notes_backend.database() as db:
            cur = db.cursor()
            cur.execute("PRAGMA user_version")
            ver = cur.fetchone()[0]
            self.assertGreaterEqual(ver, 13)

            # Check tables
            tables = {row[0] for row in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
            self.assertIn("concepts", tables)
            self.assertIn("blocks", tables)
            self.assertIn("block_sources", tables)
            self.assertIn("concept_reading_state", tables)

    def test_segment_java_capture_into_concepts_preserves_all_snippets(self):
        """P2.2 & P2.6: Segmenting the 9.5k Java fixture must extract concepts without dropping snippets."""
        fixture_path = REPO_ROOT / "tests" / "fixtures" / "notes_upgrade" / "java_deep_capture.txt"
        self.assertTrue(fixture_path.is_file(), "Fixture must exist on disk")
        raw_text = fixture_path.read_text(encoding="utf-8")

        concepts_data = notes_backend.segment_text_to_concepts(raw_text, topic="Java")
        self.assertGreaterEqual(len(concepts_data), 5, "Java fixture must yield at least 5 distinct concepts")

        # Verify key topics are represented
        titles = [c["title"].lower() for c in concepts_data]
        self.assertTrue(any("pass-by-value" in t or "stack vs heap" in t or "memory" in t for t in titles))
        self.assertTrue(any("equals" in t or "hash" in t for t in titles))
        self.assertTrue(any("concurrenthashmap" in t or "hashmap" in t for t in titles))
        self.assertTrue(any("virtual thread" in t or "executor" in t for t in titles))

        # Verify all code blocks are preserved across concepts
        all_code_blocks = []
        for c in concepts_data:
            for b in c.get("blocks", []):
                if b.get("kind") in ("code", "command"):
                    all_code_blocks.append(b.get("content", ""))

        joined_code = "\n".join(all_code_blocks)
        self.assertIn("User u1 = new User", joined_code)
        self.assertIn("computeIfAbsent", joined_code)

    def test_unplaced_text_preservation(self):
        """P2.3: Text outside recognized concept blocks must be retained in an unplaced block."""
        sample_text = (
            "Section 1 — Concurrency\n"
            "Rule: never use synchronized in virtual threads.\n\n"
            "Random scratchpad note:\n"
            "Remember to benchmark with 10k virtual threads on Thursday.\n"
        )
        concepts = notes_backend.segment_text_to_concepts(sample_text, topic="Java")
        all_blocks = [b for c in concepts for b in c.get("blocks", [])]
        all_content = "\n".join(b["content"] for b in all_blocks)
        self.assertIn("benchmark with 10k virtual threads", all_content)

    def test_understand_vs_recall_view_filtering(self):
        """P2.4: Understand shows full explanations; Recall shows high-value rules and caveats without string truncation."""
        concept = {
            "id": "c-1",
            "topic": "Java",
            "area": "Concurrency",
            "title": "Virtual Threads Carrier Pinning",
            "definition": "Virtual threads run on carrier OS threads and must avoid blocking them.",
            "preferred_depth": "understand"
        }
        blocks = [
            {"id": "b-1", "concept_id": "c-1", "kind": "rule", "content": "Never use synchronized inside virtual threads.", "in_recall": 1, "sort_order": 1},
            {"id": "b-2", "concept_id": "c-1", "kind": "mechanism", "content": "When a virtual thread hits a synchronized monitor, the carrier thread is pinned to the OS thread and cannot yield to other virtual tasks.", "in_recall": 0, "sort_order": 2},
            {"id": "b-3", "concept_id": "c-1", "kind": "caveat", "content": "Use ReentrantLock instead of synchronized for lock-free yielding.", "in_recall": 1, "sort_order": 3},
            {"id": "b-4", "concept_id": "c-1", "kind": "code", "language": "java", "content": "final ReentrantLock lock = new ReentrantLock();\nlock.lock();\ntry { ... } finally { lock.unlock(); }", "in_recall": 1, "sort_order": 4}
        ]

        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, concept, blocks)

        # 1. Understand mode
        view_u = notes_backend.get_concept_view("c-1", mode="understand")
        self.assertEqual(len(view_u["blocks"]), 4, "Understand must include all 4 blocks")
        # Ensure complete mechanism is not truncated
        mech_block = next(b for b in view_u["blocks"] if b["kind"] == "mechanism")
        self.assertIn("cannot yield to other virtual tasks", mech_block["content"])

        # 2. Recall mode
        view_r = notes_backend.get_concept_view("c-1", mode="recall")
        # Recall shows only in_recall=1 blocks directly (rule, caveat, code)
        self.assertEqual(len(view_r["blocks"]), 3)
        self.assertFalse(any(b["kind"] == "mechanism" for b in view_r["blocks"]))
        # Secondary blocks must still be accessible in expandable list
        self.assertEqual(len(view_r["expandable_blocks"]), 1)
        self.assertEqual(view_r["expandable_blocks"][0]["kind"], "mechanism")

    def test_faithful_markdown_export(self):
        """P2.5: Markdown export must preserve code fences and full indentation without string surgery."""
        concept = {
            "id": "c-2",
            "topic": "Java",
            "area": "Concurrency",
            "title": "ReentrantLock Idiom",
            "definition": "Explicit lock allowing fine-grained synchronization without carrier pinning."
        }
        code_str = "Lock lock = new ReentrantLock();\nlock.lock();\ntry {\n    doWork();\n} finally {\n    lock.unlock();\n}"
        blocks = [
            {"id": "b-10", "concept_id": "c-2", "kind": "rule", "content": "Always unlock in a finally block.", "in_recall": 1, "sort_order": 1},
            {"id": "b-11", "concept_id": "c-2", "kind": "code", "language": "java", "content": code_str, "in_recall": 1, "sort_order": 2}
        ]
        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, concept, blocks)

        md = notes_backend.export_concept_markdown("c-2")
        self.assertIn("## ReentrantLock Idiom", md)
        self.assertIn("Always unlock in a finally block.", md)
        self.assertIn("```java\nLock lock = new ReentrantLock();\nlock.lock();\ntry {\n    doWork();\n} finally {\n    lock.unlock();\n}\n```", md)

    def test_search_concepts_lands_on_exact_block(self):
        """P3.4: Searching a term must return the matching block ID, snippet, and concept location."""
        concept = {
            "id": "c-search-1",
            "topic": "Java",
            "area": "Collections",
            "title": "ConcurrentHashMap computeIfAbsent",
            "definition": "Atomic compute operation for thread-safe lazy value initialization."
        }
        blocks = [
            {"id": "b-search-rule", "concept_id": "c-search-1", "kind": "rule", "content": "computeIfAbsent is atomic per key.", "in_recall": 1, "sort_order": 1},
            {"id": "b-search-code", "concept_id": "c-search-1", "kind": "code", "language": "java", "content": "cache.computeIfAbsent(1L, id -> loadUser(id));", "in_recall": 1, "sort_order": 2}
        ]
        with notes_backend.database() as db:
            notes_backend._insert_concept_with_blocks(db, concept, blocks)

        res = notes_backend.search_concepts_rpc({"query": "computeIfAbsent"})
        self.assertTrue(res.get("success"))
        results = res.get("results", [])
        self.assertTrue(len(results) > 0)
        matches = [r for r in results if r["concept_id"] == "c-search-1"]
        self.assertEqual(len(matches), 2)
        self.assertEqual(matches[0]["topic"], "Java")
        self.assertEqual(matches[0]["area"], "Collections")
        self.assertTrue(any(r["block_id"] == "b-search-code" for r in matches))
        self.assertTrue(any(r["block_id"] == "b-search-rule" for r in matches))
        self.assertTrue(all("computeIfAbsent" in r["match_snippet"] for r in matches))


if __name__ == "__main__":
    unittest.main()
