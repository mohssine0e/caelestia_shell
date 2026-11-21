"""Scoped, review-only handbook gap suggestions."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend as backend


class GapSuggestionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(backend, "database_path", return_value=Path(self.tmp.name) / "notes.sqlite3")
        self.db_patch.start()
        with backend.database() as db:
            backend._insert_concept_with_blocks(db, {
                "id": "java-ref", "topic": "Java", "area": "Memory",
                "title": "Pass by value", "definition": "Arguments are copied."
            }, [{"kind": "rule", "content": "References are copied values."}])
            backend._insert_concept_with_blocks(db, {
                "id": "java-list", "topic": "Java", "area": "Collections",
                "title": "List", "definition": "Ordered collection."
            }, [])

    def tearDown(self):
        self.db_patch.stop()
        self.tmp.cleanup()

    def _suggest(self, payload, items):
        response = json.dumps({"suggestions": items})
        with patch.object(backend, "_run_provider", return_value=(response, "mock")) as provider:
            result = backend.suggest_gaps_rpc(payload)
        return result, provider

    def test_concept_filters_foreign_targets_and_saved_content(self):
        base = {"kind": "block", "area": "Memory", "title": "Why it matters",
                "content": "Caller rebinding does not change the copied value.",
                "reason": "Shows the boundary.", "block_kind": "caveat"}
        items = [dict(base, related_concept_id="java-list"),
                 dict(base, related_concept_id="java-ref", content="References are copied values."),
                 dict(base, related_concept_id="java-ref")]
        result, provider = self._suggest({"scope": "concept", "id": "java-ref"}, items)
        self.assertEqual(len(result["suggestions"]), 1)
        self.assertEqual(result["suggestions"][0]["related_concept_id"], "java-ref")
        self.assertTrue(result["source_review_complete"])
        self.assertIn('"concept_id": "java-ref"', provider.call_args.args[1])

    def test_area_rejects_other_destinations(self):
        base = {"kind": "new_concept", "title": "Heap", "content": "Memory shared by objects.",
                "reason": "Useful memory model.", "related_concept_id": ""}
        result, _ = self._suggest({"scope": "area", "topic": "Java", "area": "Memory"},
                                  [dict(base, area="Collections"), dict(base, area="Memory")])
        self.assertEqual(len(result["suggestions"]), 1)
        self.assertEqual(result["suggestions"][0]["area"], "Memory")
        self.assertFalse(result["source_review_complete"])

    def test_topic_inspects_all_areas_and_only_new_areas(self):
        base = {"kind": "new_area", "title": "Exceptions", "content": "Failure control flow.",
                "reason": "Useful for backend work.", "related_concept_id": ""}
        result, provider = self._suggest({"scope": "topic", "topic": "Java"},
                                         [dict(base, area="Memory"), dict(base, area="Errors")])
        self.assertEqual(result["inspected_count"], 2)
        self.assertEqual([s["area"] for s in result["suggestions"]], ["Errors"])
        self.assertIn('"area": "Collections"', provider.call_args.args[1])
        self.assertIn('"area": "Memory"', provider.call_args.args[1])

    def test_topic_paginates_before_provider_call(self):
        with backend.database() as db:
            for number in range(101):
                backend._insert_concept_with_blocks(db, {
                    "id": f"java-extra-{number}", "topic": "Java", "area": "Language",
                    "title": f"Feature {number}", "definition": "A Java feature."
                }, [])
        result, provider = self._suggest({"scope": "topic", "topic": "Java"}, [])
        self.assertEqual(result["inspected_count"], 103)
        self.assertTrue(result["inspection_complete"])
        self.assertIn('"title": "Feature 100"', provider.call_args.args[1])

    def test_invalid_scope_and_private_source_do_not_call_provider(self):
        with self.assertRaises(ValueError):
            backend.suggest_gaps_rpc({"scope": "area", "topic": "Java", "area": "All"})
        with backend.database() as db:
            db.execute("""INSERT INTO notes (id, created_at, updated_at, raw_content, local_only)
                VALUES ('secret', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'private', 1)""")
            block_id = db.execute("SELECT id FROM blocks WHERE concept_id='java-ref' LIMIT 1").fetchone()[0]
            db.execute("""INSERT INTO block_sources (id, block_id, note_id, created_at)
                VALUES ('link', ?, 'secret', '2026-01-01T00:00:00Z')""", (block_id,))
        with patch.object(backend, "_run_provider") as provider:
            with self.assertRaisesRegex(ValueError, "private local material"):
                backend.suggest_gaps_rpc({"scope": "topic", "topic": "Java"})
        provider.assert_not_called()

    def test_generation_does_not_mutate_notes(self):
        with backend.database() as db:
            before = db.execute("SELECT count(*) FROM concepts").fetchone()[0]
            before_blocks = db.execute("SELECT count(*) FROM blocks").fetchone()[0]
        result, _ = self._suggest({"scope": "topic", "topic": "Java"}, [])
        self.assertEqual(result["suggestions"], [])
        with backend.database() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM concepts").fetchone()[0], before)
            self.assertEqual(db.execute("SELECT count(*) FROM blocks").fetchone()[0], before_blocks)


if __name__ == "__main__":
    unittest.main()
