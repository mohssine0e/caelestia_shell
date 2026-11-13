import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "notes_backend.py"
SPEC = importlib.util.spec_from_file_location("notes_backend", SCRIPT)
notes = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(notes)


class NotesBackendTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp.name) / "data" / "notes.sqlite3"
        self.env = mock.patch.dict(os.environ, {"CAELESTIA_NOTES_DB": str(self.db_path)})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def test_create_preserves_raw_text_and_extracts_tags(self):
        result = notes.create_note({"raw_content": "docker ps  #Docker #linux #docker"})
        self.assertTrue(result["success"])
        self.assertEqual(result["note"]["raw_content"], "docker ps  #Docker #linux #docker")
        self.assertEqual(result["note"]["tags"], ["#docker", "#linux"])
        self.assertEqual(result["note"]["status"], "inbox")
        self.assertEqual(stat.S_IMODE(self.db_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.db_path.parent.stat().st_mode), 0o700)

    def test_search_update_delete_and_restore(self):
        first = notes.create_note({"raw_content": "podman ps #containers"})["note"]
        notes.create_note({"raw_content": "git rebase #git"})
        found = notes.list_notes({"query": "containers"})["notes"]
        self.assertEqual([item["id"] for item in found], [first["id"]])

        updated = notes.update_note({"id": first["id"], "raw_content": "podman images #containers"})["note"]
        self.assertEqual(updated["status"], "inbox")
        notes.delete_note({"id": first["id"]})
        self.assertEqual(len(notes.list_notes({})["notes"]), 1)
        restored = notes.restore_note({"id": first["id"]})["note"]
        self.assertFalse(restored["deleted"])

    def test_formatting_saves_markdown_and_never_replaces_raw(self):
        original = "docker ps shows containers"
        note = notes.create_note({"raw_content": original})["note"]
        with mock.patch.object(notes, "_format_with_provider", return_value=("## Docker\n\n`docker ps`", "gemini")):
            result = notes.organize_note({"id": note["id"]})
        self.assertTrue(result["success"])
        self.assertEqual(result["note"]["raw_content"], original)
        self.assertEqual(result["note"]["formatted_content"], "## Docker\n\n`docker ps`")
        self.assertEqual(result["note"]["status"], "formatted")

    def test_formatting_failure_keeps_raw_note(self):
        note = notes.create_note({"raw_content": "safe even if provider fails"})["note"]
        with mock.patch.object(notes, "_format_with_provider", side_effect=RuntimeError("offline")):
            result = notes.organize_note({"id": note["id"]})
        self.assertFalse(result["success"])
        stored = notes.get_note({"id": note["id"]})["note"]
        self.assertEqual(stored["raw_content"], "safe even if provider fails")
        self.assertEqual(stored["status"], "format_failed")
        self.assertEqual(stored["format_error"], "offline")

    def test_triage_keeps_personal_thought_verbatim(self):
        original = "I focus better when I start with one small task."
        note = notes.create_note({"raw_content": original})["note"]
        response = '{"keep":true,"category":"personal","essential_bullets":["changed"],"completion_bullets":["invented"]}'
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            result = notes.triage_note({"id": note["id"]})
        self.assertTrue(result["success"])
        stored = result["note"]
        self.assertEqual(stored["raw_content"], original)
        self.assertEqual(stored["formatted_content"], "")
        self.assertEqual(stored["category"], "personal")
        self.assertEqual(stored["keep_decision"], "keep")

    def test_triage_builds_essential_bullets_and_labels_ai_additions(self):
        note = notes.create_note({"raw_content": "docker ps shows running containers"})["note"]
        response = json.dumps({
            "keep": True,
            "category": "technical",
            "essential_bullets": ["`docker ps` lists running containers."],
            "completion_bullets": ["Use `docker ps -a` to include stopped containers."],
        })
        with mock.patch.object(notes, "_run_provider", return_value=(response, "groq")):
            stored = notes.triage_note({"id": note["id"]})["note"]
        self.assertEqual(stored["category"], "technical")
        self.assertIn("- `docker ps` lists running containers.", stored["formatted_content"])
        self.assertIn("**AI-added context**", stored["formatted_content"])
        self.assertEqual(stored["raw_content"], "docker ps shows running containers")

    def test_noise_is_recoverable_instead_of_deleted(self):
        note = notes.create_note({"raw_content": "asdf qwer"})["note"]
        response = '{"keep":false,"category":"noise","essential_bullets":[],"completion_bullets":[]}'
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            stored = notes.triage_note({"id": note["id"]})["note"]
        self.assertEqual(stored["keep_decision"], "skip")
        self.assertEqual(stored["raw_content"], "asdf qwer")
        self.assertFalse(stored["deleted"])

    def test_newer_format_request_wins(self):
        note = notes.create_note({"raw_content": "version one"})["note"]

        def superseded(_raw):
            notes.update_note({"id": note["id"], "raw_content": "version two"})
            return "old result", "gemini"

        with mock.patch.object(notes, "_format_with_provider", side_effect=superseded):
            result = notes.organize_note({"id": note["id"]})
        self.assertTrue(result.get("stale"))
        stored = notes.get_note({"id": note["id"]})["note"]
        self.assertEqual(stored["raw_content"], "version two")
        self.assertEqual(stored["formatted_content"], "")


if __name__ == "__main__":
    unittest.main()
