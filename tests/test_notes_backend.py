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
        self.assertEqual(result["note"]["topic"], "Docker")
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
        response = '{"keep":true,"category":"personal","title":"AI rewrite","essential_bullets":["changed"],"completion_bullets":["invented"]}'
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            result = notes.triage_note({"id": note["id"]})
        self.assertTrue(result["success"])
        stored = result["note"]
        self.assertEqual(stored["raw_content"], original)
        self.assertEqual(stored["formatted_content"], "")
        self.assertEqual(stored["category"], "personal")
        self.assertEqual(stored["keep_decision"], "keep")
        self.assertEqual(stored["title"], "")

    def test_triage_builds_essential_bullets_and_labels_ai_additions(self):
        note = notes.create_note({"raw_content": "docker ps shows running containers"})["note"]
        response = json.dumps({
            "keep": True,
            "category": "technical",
            "technical_type": "command",
            "canonical_topic": "Docker",
            "title": "List running Docker containers",
            "technology": "Docker",
            "suggested_tags": ["#docker", "#containers"],
            "essential_bullets": ["`docker ps` lists running containers."],
            "completion_bullets": ["Use `docker ps -a` to include stopped containers."],
            "exact_excerpts": [{"language": "bash", "content": "docker ps"}],
        })
        with mock.patch.object(notes, "_run_provider", return_value=(response, "groq")):
            stored = notes.triage_note({"id": note["id"]})["note"]
        self.assertEqual(stored["category"], "technical")
        self.assertIn("- `docker ps` lists running containers.", stored["formatted_content"])
        self.assertIn("**AI-added context**", stored["formatted_content"])
        self.assertIn("```bash\ndocker ps\n```", stored["formatted_content"])
        self.assertEqual(stored["title"], "List running Docker containers")
        self.assertEqual(stored["technical_type"], "command")
        self.assertEqual(stored["technology"], "Docker")
        self.assertEqual(stored["topic"], "Docker")
        self.assertEqual(stored["ai_tags"], ["#docker", "#containers"])
        self.assertEqual(stored["essentials"], ["`docker ps` lists running containers."])
        self.assertEqual(stored["exact_excerpts"], [{"language": "bash", "content": "docker ps"}])
        self.assertEqual(stored["raw_content"], "docker ps shows running containers")

    def test_sensitive_note_stays_local_without_calling_provider(self):
        note = notes.create_note({"raw_content": "api_key = sk_test_12345678901234567890"})["note"]
        with mock.patch.object(notes, "_run_provider") as provider:
            stored = notes.triage_note({"id": note["id"]})["note"]
        provider.assert_not_called()
        self.assertTrue(stored["local_only"])
        self.assertEqual(stored["raw_content"], "api_key = sk_test_12345678901234567890")
        self.assertEqual(stored["provider"], "")
        self.assertIn("secret", stored["sensitive_reason"])

    def test_similar_notes_are_linked_without_automatic_merge(self):
        original = notes.create_note({"raw_content": "docker ps"})["note"]
        duplicate = notes.create_note({"raw_content": "docker ps"})["note"]
        response = json.dumps({
            "keep": True,
            "category": "technical",
            "technical_type": "command",
            "title": "List Docker containers",
            "technology": "Docker",
            "suggested_tags": ["#docker"],
            "essential_bullets": ["Lists running containers."],
            "completion_bullets": [],
            "exact_excerpts": [{"language": "bash", "content": "docker ps"}],
        })
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            stored = notes.triage_note({"id": duplicate["id"]})["note"]
        self.assertEqual(stored["duplicate_of"], original["id"])
        self.assertEqual(len(notes.list_notes({})["notes"]), 2)

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


    def test_fill_topic_excludes_private_and_other_topic_notes(self):
        notes.create_note({"raw_content": "docker ps"})
        notes.create_note({"raw_content": "git rebase unrelated details"})
        notes.create_note({"raw_content": "docker password=supersecretvalue123"})
        response = json.dumps([{"section": "overview", "content": "Images are container templates.", "command": ""}])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")) as provider:
            notes.fill_topic({"topic": "Docker"})
        context = json.loads(provider.call_args.args[1])
        self.assertEqual(len(context["notes"]), 1)
        self.assertIn("docker ps", context["notes"][0]["content"])
        self.assertNotIn("supersecret", str(context))
        self.assertNotIn("rebase", str(context))

    def test_fill_topic_with_no_shareable_notes_does_not_call_provider(self):
        notes.create_note({"raw_content": "docker password=supersecretvalue123"})
        with mock.patch.object(notes, "_run_provider") as provider:
            with self.assertRaises(ValueError):
                notes.fill_topic({"topic": "Docker"})
        provider.assert_not_called()

    def _fill_lines(self):
        notes.create_note({"raw_content": "docker ps lists running containers"})
        response = json.dumps([
            {"section": "overview", "content": "An image is a template for containers.", "command": ""},
            {"section": "commands", "content": "Lists container logs.", "command": "docker logs <container>"},
            {"section": "errors", "content": "A stopped container remains until removed.", "command": ""},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            return notes.fill_topic({"topic": "Docker"})["suggestions"]

    def test_fill_topic_returns_structured_lines_without_saving_notes(self):
        lines = self._fill_lines()
        self.assertEqual([item["section"] for item in lines], ["overview", "commands", "errors"])
        self.assertEqual(lines[1]["command"], "docker logs <container>")
        self.assertEqual(len(notes.list_notes({})["notes"]), 1)

    def test_fill_topic_requests_overview_when_first_reply_has_only_commands(self):
        notes.create_note({"raw_content": "docker ps lists running containers"})
        command = json.dumps([{"section": "commands", "content": "Lists images.", "command": "docker images"}])
        overview = json.dumps([{"section": "overview", "content": "Docker runs applications in containers.",
                                "command": ""}])
        with mock.patch.object(notes, "_run_provider", side_effect=[(command, "gemini"),
                                                                      (overview, "gemini")]) as provider:
            lines = notes.fill_topic({"topic": "Docker"})["suggestions"]
        self.assertEqual(provider.call_count, 2)
        self.assertEqual({item["section"] for item in lines}, {"overview", "commands"})

    def test_accept_line_organizes_command_and_is_idempotent(self):
        lines = self._fill_lines()
        payload = {"topic": "Docker", "id": lines[1]["id"]}
        notes.accept_topic_line(payload)
        notes.accept_topic_line(payload)
        stored = notes.list_notes({})["notes"]
        self.assertEqual(len(stored), 2)
        command = next(item for item in stored if item["origin"] == "ai")
        self.assertEqual(command["topic"], "Docker")
        self.assertEqual(command["technical_type"], "command")
        self.assertEqual(command["exact_excerpts"][0]["content"], "docker logs <container>")
        self.assertEqual(command["essentials"], ["Lists container logs."])

    def test_accept_overview_and_notes_retains_their_sections(self):
        notes.create_note({"raw_content": "docker ps lists running containers"})
        response = json.dumps([
            {"section": "overview", "content": "Docker packages applications in containers.", "command": ""},
            {"section": "notes", "content": "Images are reusable container templates.", "command": ""},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            notes.fill_topic({"topic": "Docker"})
        notes.accept_all_topic_lines({"topic": "Docker"})
        saved = [item for item in notes.list_notes({})["notes"] if item["origin"] == "ai"]
        self.assertEqual({item["topic_section"] for item in saved}, {"overview", "notes"})
        self.assertTrue(all(item["technical_type"] == "concept" for item in saved))

    def test_discard_and_accept_all_do_not_save_discarded_lines(self):
        lines = self._fill_lines()
        notes.dismiss_gap({"topic": "Docker", "id": lines[0]["id"]})
        notes.accept_all_topic_lines({"topic": "Docker"})
        notes.accept_all_topic_lines({"topic": "Docker"})
        self.assertEqual(len(notes.list_notes({})["notes"]), 3)
        state = {item["id"]: item["state"] for item in notes.learning_list({"topic": "Docker"})["suggestions"]}
        self.assertEqual(state[lines[0]["id"]], "dismissed")
        self.assertEqual(state[lines[1]["id"]], "saved")

    def test_edit_pending_line_before_accepting(self):
        lines = self._fill_lines()
        payload = {"topic": "Docker", "id": lines[1]["id"],
                   "command": "docker logs --tail 20 <container>",
                   "content": "Shows the last 20 log lines."}
        edited = notes.edit_topic_line(payload)["suggestions"][1]
        self.assertEqual(edited["command"], payload["command"])
        self.assertEqual(len(notes.list_notes({})["notes"]), 1)
        notes.accept_topic_line(payload)
        saved = next(item for item in notes.list_notes({})["notes"] if item["origin"] == "ai")
        self.assertEqual(saved["exact_excerpts"][0]["content"], payload["command"])
        with self.assertRaises(ValueError):
            notes.edit_topic_line(payload)

    def test_edit_topic_entry_preserves_original_capture(self):
        note = notes.create_note({"raw_content": "docker ps lists running containers"})["note"]
        result = notes.edit_topic_entry({"topic": "Docker", "note_id": note["id"],
                                         "key": "fallback", "value": "Lists currently running containers."})
        self.assertEqual(result["note"]["raw_content"], note["raw_content"])
        self.assertEqual(result["note"]["display_edits"]["fallback"], "Lists currently running containers.")
        changed = notes.update_note({"id": note["id"], "raw_content": "docker ps -a lists all containers"})["note"]
        self.assertEqual(changed["display_edits"], {})
        with self.assertRaises(ValueError):
            notes.edit_topic_entry({"topic": "Git", "note_id": note["id"],
                                    "key": "fallback", "value": "Wrong topic"})

    def test_edit_accepted_command_preserves_exact_ai_source(self):
        lines = self._fill_lines()
        command_id = lines[1]["id"]
        notes.accept_topic_line({"topic": "Docker", "id": command_id})
        saved_id = next(item["note_id"] for item in notes.learning_list({"topic": "Docker"})["suggestions"]
                        if item["id"] == command_id)
        notes.edit_topic_entry({"topic": "Docker", "note_id": saved_id,
                                "key": "command:0:0", "value": "docker logs --tail 20 <container>"})
        notes.edit_topic_entry({"topic": "Docker", "note_id": saved_id,
                                "key": "essential:0", "value": "Shows the last 20 log lines."})
        stored = notes.get_note({"id": saved_id})["note"]
        self.assertEqual(stored["exact_excerpts"][0]["content"], "docker logs <container>")
        self.assertEqual(stored["display_edits"]["command:0:0"], "docker logs --tail 20 <container>")
        self.assertEqual(stored["display_edits"]["essential:0"], "Shows the last 20 log lines.")

    def test_invalid_line_does_not_save_partial_suggestions(self):
        notes.create_note({"raw_content": "docker ps"})
        response = json.dumps([{"section": "overview", "content": "Useful fact", "command": ""},
                               {"section": "commands", "content": "Missing command", "command": ""}])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            with self.assertRaises(ValueError):
                notes.fill_topic({"topic": "Docker"})
        self.assertEqual(notes.learning_list({"topic": "Docker"})["suggestions"], [])

    def test_fill_topic_ignores_facts_already_in_source(self):
        notes.create_note({"raw_content": "docker ps lists running containers"})
        response = json.dumps([
            {"section": "overview", "content": "docker ps lists running containers", "command": ""},
            {"section": "commands", "content": "Lists stopped containers.", "command": "docker ps -a"},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            result = notes.fill_topic({"topic": "Docker"})
        self.assertEqual([item["command"] for item in result["suggestions"]], ["docker ps -a"])


if __name__ == "__main__":
    unittest.main()
