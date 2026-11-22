import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend


class TestLegacyConceptSync(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp_dir.name) / "notes.sqlite3"
        self.patcher = patch.object(notes_backend, "database_path", return_value=self.db_path)
        self.patcher.start()
        with notes_backend.database():
            pass

    def tearDown(self):
        self.patcher.stop()
        self.tmp_dir.cleanup()

    def _add_kubernetes_capture(self):
        raw = "Kubernetes imagePullPolicy controls when the kubelet pulls an image. This relates to Docker image layers."
        essentials = [
            "Kubernetes imagePullPolicy controls when the kubelet attempts to pull a container image.",
            "The policy determines whether the container runtime fetches the image or uses a locally cached image.",
        ]
        completions = [
            "Values are Always, IfNotPresent, and Never.",
            "The default is Always for :latest or an omitted tag; otherwise it is IfNotPresent.",
        ]
        with notes_backend.database() as db:
            db.execute(
                """INSERT INTO notes
                   (id, title, topic, subconcept, category, technical_type, topic_section,
                    raw_content, formatted_content, essentials_json, completions_json,
                    excerpts_json, status, created_at, updated_at)
                   VALUES (?, ?, ?, ?, 'technical', 'concept', 'notes', ?, ?, ?, ?, '[]',
                           'formatted', '2026-11-18T19:20:00Z', '2026-11-18T19:20:00Z')""",
                ("note-k8s", "Kubernetes imagePullPolicy mechanics", "Kubernetes", "Core Kubernetes",
                 raw, "", json.dumps(essentials), json.dumps(completions)),
            )
            notes_backend._insert_concept_with_blocks(
                db,
                {"id": "concept-k8s", "legacy_note_id": "note-k8s", "topic": "Kubernetes",
                 "area": "Core Kubernetes", "title": "Kubernetes imagePullPolicy mechanics",
                 "definition": essentials[0]},
                [{"kind": "rule", "role": "primary", "content": raw, "in_recall": 1}],
                source_note_id="note-k8s",
            )
        return raw, essentials, completions

    def test_sync_imports_saved_essentials_and_completions_without_touching_raw_capture(self):
        raw, essentials, completions = self._add_kubernetes_capture()

        first = notes_backend.sync_legacy_notes_rpc({"id": "note-k8s"})
        self.assertEqual(first["enriched_count"], 4)  # replaces raw seed, adds 3 distinct facts

        with notes_backend.database() as db:
            stored_raw = db.execute("SELECT raw_content FROM notes WHERE id='note-k8s'").fetchone()[0]
            blocks = db.execute(
                "SELECT kind, content, in_recall, evidence_status FROM blocks "
                "WHERE concept_id='concept-k8s' ORDER BY sort_order"
            ).fetchall()
            sources = db.execute(
                "SELECT count(*) FROM block_sources s JOIN blocks b ON b.id=s.block_id "
                "WHERE b.concept_id='concept-k8s' AND s.note_id='note-k8s'"
            ).fetchone()[0]

        self.assertEqual(stored_raw, raw)
        self.assertEqual(blocks[0]["content"], essentials[0])
        contents = [row["content"] for row in blocks]
        for item in [essentials[1], *completions]:
            self.assertIn(item, contents)
        self.assertEqual(contents.count(essentials[0]), 1)
        self.assertEqual(blocks[1]["kind"], "mechanism")
        self.assertEqual(blocks[0]["evidence_status"], "unverified")
        self.assertEqual(sum(row["in_recall"] for row in blocks), 2)
        self.assertTrue(all(row["evidence_status"] == "unverified" for row in blocks[1:]))
        self.assertEqual(sources, len(blocks))

        second = notes_backend.sync_legacy_notes_rpc({"id": "note-k8s"})
        self.assertEqual(second["enriched_count"], 0)
        with notes_backend.database() as db:
            count = db.execute("SELECT count(*) FROM blocks WHERE concept_id='concept-k8s'").fetchone()[0]
        self.assertEqual(count, len(blocks))

    def test_targeted_sync_does_not_enrich_other_existing_concepts(self):
        self._add_kubernetes_capture()
        with notes_backend.database() as db:
            db.execute(
                """INSERT INTO notes (id, title, topic, subconcept, category, technical_type,
                   raw_content, essentials_json, completions_json, status, created_at, updated_at)
                   VALUES ('note-docker','Docker layers','Docker','Images & Build','technical','concept',
                   'Docker layers are immutable.', '[\"Layers are immutable.\"]', '[\"Each layer is cached.\"]',
                   'formatted','2026-11-18T19:20:00Z','2026-11-18T19:20:00Z')"""
            )
            notes_backend._insert_concept_with_blocks(
                db,
                {"id": "concept-docker", "legacy_note_id": "note-docker", "topic": "Docker",
                 "area": "Images & Build", "title": "Docker layers", "definition": "Docker layers are immutable."},
                [{"kind": "rule", "role": "primary", "content": "Docker layers are immutable.", "in_recall": 1}],
                source_note_id="note-docker",
            )

        notes_backend.sync_legacy_notes_rpc({"id": "note-k8s"})
        with notes_backend.database() as db:
            docker_blocks = db.execute(
                "SELECT content FROM blocks WHERE concept_id='concept-docker' ORDER BY sort_order"
            ).fetchall()
        self.assertEqual([row[0] for row in docker_blocks], ["Docker layers are immutable."])


if __name__ == "__main__":
    unittest.main()
