"""Coverage inventory distinguishes structured content from original captures."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend as backend


class CoverageInventoryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "notes.sqlite3"
        self.db_patch = patch.object(backend, "database_path", return_value=self.db)
        self.db_patch.start()

    def tearDown(self):
        self.db_patch.stop()
        self.tmp.cleanup()

    def test_exact_scope_and_original_source_caution(self):
        with backend.database() as connection:
            connection.execute("""INSERT INTO notes
                (id, created_at, updated_at, raw_content, topic, category)
                VALUES ('source-1', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                        'Java passes a copied reference. A full example follows.', 'Java', 'technical')""")
            backend._insert_concept_with_blocks(connection, {
                "id": "java-ref", "topic": "Java", "area": "Memory",
                "title": "Pass-by-value", "definition": "Java passes a copied reference."
            }, [{"kind": "rule", "content": "Java passes a copied reference."}], source_note_id="source-1")
            backend._insert_concept_with_blocks(connection, {
                "id": "docker-ps", "topic": "Docker", "area": "Commands",
                "title": "List running containers", "definition": "Shows running containers."
            }, [{"kind": "command", "content": "docker ps"}])

        result = backend.coverage_inventory_rpc({"scope": "area", "topic": "Java", "area": "Memory"})
        self.assertEqual(result["total_count"], 1)
        self.assertTrue(result["complete"])
        item = result["concepts"][0]
        self.assertEqual(item["id"], "java-ref")
        self.assertIn("mechanism", item["candidate_roles"])
        self.assertTrue(item["source_review_required"])
        self.assertEqual(item["source_note_ids"], ["source-1"])

        docker = backend.coverage_inventory_rpc({"scope": "topic", "topic": "Docker"})["concepts"][0]
        self.assertTrue(docker["known_roles"]["example"])
        self.assertEqual(docker["candidate_roles"], [])

    def test_large_topic_reports_continuation_instead_of_silent_truncation(self):
        with backend.database() as connection:
            for number in range(101):
                backend._insert_concept_with_blocks(connection, {
                    "id": f"java-{number}", "topic": "Java", "area": "Language",
                    "title": f"Concept {number}", "definition": f"Definition {number}."
                }, [])
        first = backend.coverage_inventory_rpc({"scope": "topic", "topic": "Java"})
        self.assertFalse(first["complete"])
        self.assertEqual(first["inspected_count"], 100)
        second = backend.coverage_inventory_rpc({"scope": "topic", "topic": "Java",
                                                  "offset": first["next_offset"]})
        self.assertTrue(second["complete"])
        self.assertEqual(second["inspected_count"], 1)


if __name__ == "__main__":
    unittest.main()
