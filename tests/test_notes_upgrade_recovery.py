"""Behavior checks for capture recovery and the handbook migration repair."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend as backend


class NotesRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "notes.sqlite3"
        self.db_patch = patch.object(backend, "database_path", return_value=self.path)
        self.db_patch.start()

    def tearDown(self):
        self.db_patch.stop()
        self.tmp.cleanup()

    def test_capture_retry_keeps_one_note_and_latest_text(self):
        first = backend.create_note({"raw_content": "docker ps", "client_token": "session-1"})["note"]
        retry = backend.create_note({"raw_content": "docker ps", "client_token": "session-1"})["note"]
        later = backend.create_note({"raw_content": "docker ps -a", "client_token": "session-1"})["note"]
        other = backend.create_note({"raw_content": "git status", "client_token": "session-2"})["note"]
        self.assertEqual(first["id"], retry["id"])
        self.assertEqual(first["id"], later["id"])
        self.assertNotEqual(first["id"], other["id"])
        with backend.database() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM notes").fetchone()[0], 2)
            self.assertEqual(db.execute("SELECT raw_content FROM notes WHERE id = ?", (first["id"],)).fetchone()[0], "docker ps -a")

    def test_repair_preserves_original_and_concept_id(self):
        raw = "docker stop container-name\ndocker rm container-name\ndocker rm -f container-name"
        with backend.database() as db:
            db.execute(
                """INSERT INTO notes (id, created_at, updated_at, raw_content, topic, category,
                   title, subconcept, technical_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                ("note-1", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", raw,
                 "Docker", "technical", "Stop and remove Docker containers", "Containers & CLI", "command"),
            )
            backend._insert_concept_with_blocks(db, {
                "id": "concept-1", "topic": "Docker", "area": "General",
                "title": "Overview", "definition": "Overview",
            }, [{"kind": "code", "content": "docker rm container-name"}], source_note_id="note-1")
        repaired = backend.repair_legacy_concepts_rpc({})
        self.assertEqual(repaired["repaired_count"], 1)
        with backend.database() as db:
            note = db.execute("SELECT raw_content FROM notes WHERE id = 'note-1'").fetchone()[0]
            concept = db.execute("SELECT id, title, area FROM concepts WHERE id = 'concept-1'").fetchone()
            blocks = db.execute("SELECT id, kind, content FROM blocks WHERE concept_id = 'concept-1' ORDER BY sort_order").fetchall()
            spans = db.execute("SELECT source_span FROM block_sources ORDER BY created_at").fetchall()
        self.assertEqual(note, raw)
        self.assertEqual(tuple(concept), ("concept-1", "Stop and remove Docker containers", "Containers & CLI"))
        self.assertEqual([b["content"] for b in blocks], raw.splitlines())
        self.assertTrue(all(b["kind"] == "command" for b in blocks))
        self.assertTrue(all(json.loads(span[0])["matched"] for span in spans))
        self.assertEqual(backend.repair_legacy_concepts_rpc({})["repaired_count"], 0)

    def test_search_reaches_raw_source_when_derived_block_omits_it(self):
        with backend.database() as db:
            db.execute(
                """INSERT INTO notes (id, created_at, updated_at, raw_content, topic, category)
                   VALUES ('source-1', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                           'first line\nrare original wording\nlast line', 'Java', 'technical')"""
            )
            backend._insert_concept_with_blocks(db, {
                "id": "concept-1", "topic": "Java", "area": "Memory",
                "title": "References", "definition": "A reference points to an object.",
            }, [{"kind": "rule", "content": "A reference points to an object."}], source_note_id="source-1")
        results = backend.search_concepts_rpc({"query": "rare original wording"})["results"]
        source = next(r for r in results if r["block_kind"] == "source")
        self.assertEqual(source["concept_id"], "concept-1")
        self.assertEqual(source["source_note_id"], "source-1")
        self.assertEqual(source["source_start"], 11)

    def test_opening_and_depth_change_do_not_create_new_unread_revision(self):
        with backend.database() as db:
            backend._insert_concept_with_blocks(db, {
                "id": "concept-1", "topic": "Java", "area": "Memory", "title": "References"
            }, [])
        self.assertEqual(backend.list_concepts_rpc({})["concepts"][0]["unseen"], 1)
        backend.mark_concept_seen_rpc({"id": "concept-1"})
        backend.set_concept_depth_rpc({"id": "concept-1", "depth": "recall"})
        self.assertEqual(backend.list_concepts_rpc({})["concepts"][0]["unseen"], 0)

    def test_full_explanation_preference_persists_without_content_revision(self):
        with backend.database() as db:
            backend._insert_concept_with_blocks(db, {
                "id": "concept-1", "topic": "Java", "area": "Memory", "title": "References"
            }, [{"kind": "mechanism", "content": "References are copied.", "in_recall": 0}])
            before = db.execute("SELECT updated_at FROM concepts WHERE id = 'concept-1'").fetchone()[0]
        backend.mark_concept_seen_rpc({"id": "concept-1"})
        backend.set_concept_expansion_rpc({"id": "concept-1", "expanded": True})
        self.assertTrue(backend.get_concept_view("concept-1", "recall")["show_expanded"])
        self.assertEqual(backend.list_concepts_rpc({})["concepts"][0]["unseen"], 0)
        with backend.database() as db:
            self.assertEqual(db.execute("SELECT updated_at FROM concepts WHERE id = 'concept-1'").fetchone()[0], before)
        backend.set_concept_expansion_rpc({"id": "concept-1", "expanded": False})
        self.assertFalse(backend.get_concept_view("concept-1", "recall")["show_expanded"])


if __name__ == "__main__":
    unittest.main()
