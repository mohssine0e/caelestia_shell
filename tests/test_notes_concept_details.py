"""Focused concept explanations stay scoped and reviewable."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend as backend


class ConceptDetailsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "notes.sqlite3"
        self.db_patch = patch.object(backend, "database_path", return_value=self.db)
        self.db_patch.start()
        with backend.database() as connection:
            backend._insert_concept_with_blocks(connection, {
                "id": "java-ref", "topic": "Java", "area": "Memory",
                "title": "Pass-by-value", "definition": "Java passes a copy of each argument value."
            }, [{"kind": "rule", "content": "The copied reference still points to the same object."}])

    def tearDown(self):
        self.db_patch.stop()
        self.tmp.cleanup()

    def test_existing_answer_is_local(self):
        with backend.database() as connection:
            connection.execute("""INSERT INTO blocks
                (id, concept_id, kind, content, created_at, updated_at)
                VALUES ('existing-why', 'java-ref', 'why', 'It prevents caller variable rebinding.',
                        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')""")
        with patch.object(backend, "_run_provider") as provider:
            answer = backend.concept_detail_rpc({"id": "java-ref", "kind": "why"})
        provider.assert_not_called()
        self.assertEqual(answer["state"], "saved")
        self.assertEqual(answer["block_id"], "existing-why")

    def test_proposal_requires_acceptance_and_retry_is_idempotent(self):
        response = json.dumps({"content": "The copied reference reaches the same object, but rebinding does not change the caller's variable."})
        with patch.object(backend, "_run_provider", return_value=(response, "mock")) as provider:
            first = backend.concept_detail_rpc({"id": "java-ref", "kind": "why"})
            second = backend.concept_detail_rpc({"id": "java-ref", "kind": "why"})
        provider.assert_called_once()
        self.assertEqual(first["proposal_id"], second["proposal_id"])
        with backend.database() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM blocks WHERE kind = 'why'").fetchone()[0], 0)
        accepted = backend.accept_concept_detail_rpc({"proposal_id": first["proposal_id"]})
        again = backend.accept_concept_detail_rpc({"proposal_id": first["proposal_id"]})
        self.assertEqual(accepted["block_id"], again["block_id"])
        with backend.database() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM blocks WHERE kind = 'why'").fetchone()[0], 1)

    def test_stale_proposal_cannot_change_newer_concept(self):
        with patch.object(backend, "_run_provider", return_value=(json.dumps({"content": "A comparison."}), "mock")):
            proposal = backend.concept_detail_rpc({"id": "java-ref", "kind": "compare"})
        with backend.database() as connection:
            connection.execute("UPDATE concepts SET updated_at = '2099-01-01T00:00:00Z' WHERE id = 'java-ref'")
        with self.assertRaisesRegex(ValueError, "changed"):
            backend.accept_concept_detail_rpc({"proposal_id": proposal["proposal_id"]})

    def test_private_source_never_reaches_provider(self):
        with backend.database() as connection:
            connection.execute("""INSERT INTO notes
                (id, created_at, updated_at, raw_content, local_only)
                VALUES ('private-note', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                        'private Java note', 1)""")
            connection.execute("""INSERT INTO block_sources
                (id, block_id, note_id, created_at)
                VALUES ('private-link',
                        (SELECT id FROM blocks WHERE concept_id = 'java-ref' LIMIT 1),
                        'private-note', '2026-01-01T00:00:00Z')""")
        with patch.object(backend, "_run_provider") as provider:
            with self.assertRaisesRegex(ValueError, "private local material"):
                backend.concept_detail_rpc({"id": "java-ref", "kind": "name"})
        provider.assert_not_called()

    def test_provider_repetition_does_not_create_a_proposal(self):
        repeated = json.dumps({"content": "Java passes a copy of each argument value."})
        with patch.object(backend, "_run_provider", return_value=(repeated, "mock")):
            result = backend.concept_detail_rpc({"id": "java-ref", "kind": "name"})
        self.assertEqual(result["state"], "covered")
        with backend.database() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM concept_detail_proposals").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
