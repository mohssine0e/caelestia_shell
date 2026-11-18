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

    def test_assistant_selection_preserves_exact_capture_and_origin(self):
        selected = "git rebase --interactive HEAD~3\nKeep this command exact."
        note = notes.create_note({"raw_content": selected, "origin": "assistant_selection"})["note"]
        self.assertEqual(note["raw_content"], selected)
        self.assertEqual(note["origin"], "assistant_selection")
        self.assertEqual(note["keep_decision"], "keep")
        self.assertEqual(note["status"], "inbox")
        with mock.patch.object(notes, "_run_provider", return_value=(
                json.dumps({"keep": False, "category": "noise", "technical_type": "general",
                            "canonical_topic": "", "title": "", "technology": "",
                            "suggested_tags": [], "essential_bullets": [],
                            "completion_bullets": [], "exact_excerpts": []}), "gemini")):
            stored = notes.triage_note({"id": note["id"]})["note"]
        self.assertEqual(stored["raw_content"], selected)
        self.assertEqual(stored["keep_decision"], "keep")
        self.assertEqual(stored["category"], "reference")

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

    def test_fill_topic_supports_dynamic_domain_sections(self):
        notes.create_note({"raw_content": "Java public static void main"})
        response = json.dumps([
            {"section": "Overview", "kind": "bullet", "content": "Java is an object-oriented language running on the JVM."},
            {"section": "Stream API", "kind": "code", "content": "Filters list", "code": "list.stream().filter(x -> x > 0)", "language": "java"},
            {"section": "JVM Options", "kind": "command", "content": "Sets max heap to 2GB", "command": "-Xmx2g"},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            suggestions = notes.fill_topic({"topic": "Java"})["suggestions"]
        self.assertEqual([item["section"] for item in suggestions], ["Overview", "Stream API", "JVM Options"])
        self.assertEqual(suggestions[1]["kind"], "code")
        self.assertEqual(suggestions[1]["code"], "list.stream().filter(x -> x > 0)")
        self.assertEqual(suggestions[2]["kind"], "command")
        self.assertEqual(suggestions[2]["command"], "-Xmx2g")

        notes.accept_all_topic_lines({"topic": "Java"})
        saved = [item for item in notes.list_notes({})["notes"] if item["origin"] == "ai"]
        saved_by_section = {item["topic_section"]: item for item in saved}
        self.assertIn("Stream API", saved_by_section)
        self.assertEqual(saved_by_section["Stream API"]["technical_type"], "code")
        self.assertEqual(saved_by_section["Stream API"]["exact_excerpts"][0]["content"], "list.stream().filter(x -> x > 0)")
        self.assertIn("JVM Options", saved_by_section)
        self.assertEqual(saved_by_section["JVM Options"]["technical_type"], "command")
        self.assertEqual(saved_by_section["JVM Options"]["exact_excerpts"][0]["content"], "-Xmx2g")

    def test_generate_topic_creates_structured_notes(self):
        response = json.dumps([
            {"section": "Overview", "kind": "bullet", "content": "Git workflow describes branching and integration strategies."},
            {"section": "Workflows", "kind": "command", "content": "Creates a new feature branch", "command": "git checkout -b feature/xyz"},
            {"section": "Pull Requests", "kind": "command", "content": "Pushes branch and sets upstream", "command": "git push -u origin feature/xyz"},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            res = notes.generate_topic({"topic": "git workflow"})
        self.assertTrue(res["success"])
        self.assertEqual(res["topic"], "Git")  # Inferred via TOPIC_PATTERNS
        self.assertEqual(res["count"], 3)

        created = [n for n in notes.list_notes({})["notes"] if n["topic"] == "Git"]
        self.assertEqual(len(created), 3)
        sections = {n["topic_section"] for n in created}
        self.assertEqual(sections, {"Overview", "Workflows", "Pull Requests"})

    def test_generate_topic_already_covered_skips_insertion(self):
        # 1. Populate Git with 3 notes
        response = json.dumps([
            {"section": "Overview", "kind": "bullet", "content": "Git is a distributed version control system."},
            {"section": "Commands", "kind": "command", "content": "Clone repo", "command": "git clone url"},
            {"section": "Workflows", "kind": "bullet", "content": "Feature branch workflow with pull requests."},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            res1 = notes.generate_topic({"topic": "Git"})
        self.assertEqual(res1["action"], "created")
        self.assertEqual(res1["count"], 3)

        # 2. Querying "Git" again should detect already covered without running provider
        with mock.patch.object(notes, "_run_provider", side_effect=AssertionError("Should not call AI")):
            res2 = notes.generate_topic({"topic": "git"})
        self.assertTrue(res2["success"])
        self.assertEqual(res2["action"], "already_covered")
        self.assertEqual(res2["topic"], "Git")
        self.assertEqual(res2["count"], 0)
        self.assertIn("Already covered in topic 'Git'", res2["message"])

        # 3. Querying subtopic already covered ("git workflow") should also detect coverage
        with mock.patch.object(notes, "_run_provider", side_effect=AssertionError("Should not call AI")):
            res3 = notes.generate_topic({"topic": "git workflow"})
        self.assertTrue(res3["success"])
        self.assertEqual(res3["action"], "already_covered")
        self.assertEqual(res3["topic"], "Git")
        self.assertEqual(res3["count"], 0)

    def test_generate_topic_merges_into_existing_topic(self):
        # 1. Populate Git with basic notes
        response = json.dumps([
            {"section": "Overview", "kind": "bullet", "content": "Git is a distributed version control system."},
            {"section": "Commands", "kind": "command", "content": "Clone repo", "command": "git clone url"},
            {"section": "Commands", "kind": "command", "content": "Commit changes", "command": "git commit -m msg"},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(response, "gemini")):
            notes.generate_topic({"topic": "Git"})

        # 2. Querying an uncovered subtopic ("git bisect") merges into Git
        bisect_response = json.dumps([
            {"section": "Debugging", "kind": "command", "content": "Starts binary search session", "command": "git bisect start"},
            {"section": "Debugging", "kind": "command", "content": "Marks bad commit", "command": "git bisect bad"},
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(bisect_response, "gemini")):
            res = notes.generate_topic({"topic": "git bisect"})
        self.assertTrue(res["success"])
        self.assertEqual(res["action"], "merged")
        self.assertEqual(res["topic"], "Git")
        self.assertEqual(res["count"], 2)
        self.assertIn("Merged 2 notes into existing topic 'Git'", res["message"])

    def test_smart_upsert_create_assigns_subconcept_and_updates_json(self):
        llm_reply = json.dumps({
            "action": "create",
            "domain": "docker",
            "subconcept": "Compose",
            "formatted_content": "### Docker Compose\nRun multi-container apps."
        })
        with mock.patch.object(notes, "_run_provider", return_value=(llm_reply, "gemini")):
            res = notes.smart_upsert({"raw_content": "docker compose up -d"})

        self.assertTrue(res["success"])
        self.assertEqual(res["action"], "create")
        self.assertEqual(res["domain"], "docker")
        self.assertEqual(res["subconcept"], "Compose")
        self.assertEqual(res["note"]["subconcept"], "Compose")

        # Verify notes.json exists and contains the note with subconcept
        json_path = self.db_path.parent / "notes.json"
        self.assertTrue(json_path.exists())
        with open(json_path, "r", encoding="utf-8") as f:
            saved_notes = json.load(f)
        self.assertTrue(any(n["subconcept"] == "Compose" for n in saved_notes))

    def test_smart_upsert_merge_updates_existing_note_and_subconcept(self):
        # 1. Create an initial note
        initial = notes.create_note({"raw_content": "docker run -d nginx", "topic": "docker", "subconcept": "Core"})["note"]

        # 2. Smart upsert decides to MERGE into initial note
        llm_reply = json.dumps({
            "action": "merge",
            "existing_id": initial["id"],
            "updated_subconcept": "Containers",
            "updated_content": "### Docker Containers\n`docker run -d nginx`\n`docker stop <id>`"
        })
        with mock.patch.object(notes, "_run_provider", return_value=(llm_reply, "gemini")):
            res = notes.smart_upsert({"raw_content": "docker stop <id>"})

        self.assertTrue(res["success"])
        self.assertEqual(res["action"], "merge")
        self.assertEqual(res["note"]["id"], initial["id"])
        self.assertEqual(res["subconcept"], "Containers")
        self.assertEqual(res["note"]["subconcept"], "Containers")
        self.assertIn("docker stop", res["note"]["formatted_content"])

    def test_smart_upsert_ignore_duplicate(self):
        llm_reply = json.dumps({"action": "ignore"})
        with mock.patch.object(notes, "_run_provider", return_value=(llm_reply, "gemini")):
            res = notes.smart_upsert({"raw_content": "identical repeated command"})

        self.assertTrue(res["success"])
        self.assertEqual(res["action"], "ignore")

    def test_infer_subconcept_rules(self):
        self.assertEqual(notes.infer_subconcept("Docker", "docker compose up", "", "docker compose up"), "Compose")
        self.assertEqual(notes.infer_subconcept("Docker", "docker volume create", "", "docker volume"), "Volumes")
        self.assertEqual(notes.infer_subconcept("Docker", "docker build -t img .", "", "docker build"), "Images & Build")
        self.assertEqual(notes.infer_subconcept("Docker", "docker ps -a", "", "docker ps"), "Containers & CLI")
        self.assertEqual(notes.infer_subconcept("Git", "Setup GitHub Actions workflow", "", "actions"), "GitHub Actions")
        self.assertEqual(notes.infer_subconcept("Git", "Git Rebase Main", "", "git rebase main"), "Branching & Workflows")
        self.assertEqual(notes.infer_subconcept("RabbitMQ", "Exchange Routing", "", "exchange"), "Exchanges & Routing")
        self.assertEqual(notes.infer_subconcept("Rust", "Mutex and Arc synchronization", "", "std::sync::Mutex"), "Synchronization")

    def test_refactor_subconcepts_command(self):
        # Create notes with empty subconcept
        with notes.database() as db:
            db.execute("INSERT INTO notes (id, created_at, updated_at, raw_content, topic, subconcept) VALUES (?, ?, ?, ?, ?, ?)",
                       ("test-1", notes.utc_now(), notes.utc_now(), "docker build -t test .", "Docker", ""))
            db.execute("INSERT INTO notes (id, created_at, updated_at, raw_content, topic, subconcept) VALUES (?, ?, ?, ?, ?, ?)",
                       ("test-2", notes.utc_now(), notes.utc_now(), "git checkout -b new-branch", "Git", ""))

        result = notes.refactor_subconcepts()
        self.assertTrue(result["success"])
        self.assertGreaterEqual(result["refactored_count"], 2)

        note1 = notes.get_note({"id": "test-1"})["note"]
        note2 = notes.get_note({"id": "test-2"})["note"]
        self.assertEqual(note1["subconcept"], "Images & Build")
        self.assertEqual(note2["subconcept"], "Branching & Workflows")

    def test_generate_topic_clean_structure(self):
        llm_reply = json.dumps([
            {
                "section": "Overview",
                "subconcept": "Volumes",
                "kind": "bullet",
                "content": "Volumes persist data outside the container lifecycle.",
                "command": "",
                "code": ""
            },
            {
                "section": "Commands",
                "subconcept": "Volumes",
                "kind": "command",
                "content": "Creates a named volume.",
                "command": "docker volume create my-vol",
                "code": ""
            }
        ])
        with mock.patch.object(notes, "_run_provider", return_value=(llm_reply, "gemini")):
            res = notes.generate_topic({"topic": "Docker"})

        self.assertTrue(res["success"])
        stored = notes.list_notes({})["notes"]
        vol_notes = [n for n in stored if n.get("subconcept") == "Volumes"]
        self.assertGreaterEqual(len(vol_notes), 2)
        for n in vol_notes:
            self.assertFalse(n["title"].startswith(("notes: ", "overview: ", "commands: ")))

    def test_delete_and_restore_topic(self):
        notes.create_note({"raw_content": "docker ps", "topic": "DockerTest"})
        notes.create_note({"raw_content": "docker run nginx", "topic": "DockerTest"})

        del_res = notes.delete_topic({"topic": "DockerTest"})
        self.assertTrue(del_res["success"])
        self.assertEqual(del_res["deleted_count"], 2)

        # Confirm notes are deleted
        all_notes = notes.list_notes({})["notes"]
        self.assertFalse(any(n["topic"] == "DockerTest" for n in all_notes))

        # Restore
        res_res = notes.restore_topic({"topic": "DockerTest"})
        self.assertTrue(res_res["success"])
        self.assertEqual(res_res["restored_count"], 2)

        # Confirm restored
        all_notes = notes.list_notes({})["notes"]
        self.assertEqual(len([n for n in all_notes if n["topic"] == "DockerTest"]), 2)

    def test_explain_flag(self):
        res = notes.explain_flag({"tool": "docker", "flag": "-d"})
        self.assertTrue(res["success"])
        self.assertIn("detached", res["explanation"].lower())

        git_res = notes.explain_flag({"tool": "git", "flag": "--rebase"})
        self.assertTrue(git_res["success"])
        self.assertIn("commits", git_res["explanation"].lower())

    def test_infer_subconcept_rules_java_and_k8s(self):
        self.assertEqual(notes.infer_subconcept("Java", "Pattern matching for instanceof", "", "instanceof User other"), "Modern Language Features")
        self.assertEqual(notes.infer_subconcept("Java", "Virtual threads in Loom", "", "Thread.ofVirtual()"), "Modern Language Features")
        self.assertEqual(notes.infer_subconcept("Java", "CompletableFuture async execution", "", "ExecutorService"), "Concurrency")
        self.assertEqual(notes.infer_subconcept("Java", "Stream filter and collect", "", "Collectors.toList()"), "Stream API & Lambdas")
        self.assertEqual(notes.infer_subconcept("Java", "Try with resources", "", "BufferedReader reader"), "Exception Handling")
        self.assertEqual(notes.infer_subconcept("Java", "Spring Transactional Service", "", "@RestController @Service"), "Spring & Framework")
        self.assertEqual(notes.infer_subconcept("Kubernetes", "Deploy pod replicas", "", "deployment spec"), "Workloads & Traffic")
        self.assertEqual(notes.infer_subconcept("Kubernetes", "ConfigMap and secrets", "", "volumeMounts"), "Config & Storage")
        self.assertEqual(notes.infer_subconcept("Kubernetes", "kubectl rollout restart", "", "kubectl drain"), "CLI & Operations")

    def test_smart_upsert_developer_note_with_snippets_and_mechanics(self):
        raw = (
            "The syntax instanceof User other is a feature called pattern matching for instanceof, which was introduced in Java 16.\n"
            "Checks if object is User and automatically casts it to variable other.\n"
            "Legacy:\nif (!(obj instanceof User)) { return false; }\nUser other = (User) obj;\n"
            "Modern:\nif (obj instanceof User other) { return true; }"
        )
        llm_reply = json.dumps({
            "action": "create",
            "domain": "Java",
            "subconcept": "Modern Language Features",
            "title": "Pattern Matching for instanceof",
            "technology": "Java 16+",
            "technical_type": "code",
            "summary": "Simplifies type checks and safe casting into a single atomic expression.",
            "mechanics": [
                "Tests if object matches target type and casts simultaneously",
                "Scoped variable is only available when predicate succeeds"
            ],
            "snippets": [
                {
                    "label": "Modern (Java 16+)",
                    "language": "java",
                    "code": "if (obj instanceof User other) {\n    return true;\n}",
                    "role": "after"
                },
                {
                    "label": "Legacy (Java < 16)",
                    "language": "java",
                    "code": "if (!(obj instanceof User)) {\n    return false;\n}\nUser other = (User) obj;",
                    "role": "before"
                }
            ],
            "suggested_tags": ["#java", "#pattern-matching"]
        })
        with mock.patch.object(notes, "_run_provider", return_value=(llm_reply, "gemini")):
            res = notes.smart_upsert({"raw_content": raw})

        self.assertTrue(res["success"])
        self.assertEqual(res["domain"], "Java")
        self.assertEqual(res["subconcept"], "Modern Language Features")
        note = res["note"]
        self.assertEqual(note["title"], "Pattern Matching for instanceof")
        self.assertEqual(note["technology"], "Java 16+")
        self.assertEqual(note["technical_type"], "code")
        self.assertEqual(note["raw_content"], raw)
        self.assertEqual(len(note["exact_excerpts"]), 2)
        self.assertEqual(note["exact_excerpts"][0]["label"], "Modern (Java 16+)")
        self.assertEqual(note["exact_excerpts"][1]["label"], "Legacy (Java < 16)")
        self.assertIn("Tests if object matches target type", note["essentials"][0])
        self.assertIn("if (obj instanceof User other)", note["formatted_content"])
        self.assertIn("if (!(obj instanceof User))", note["formatted_content"])

    def test_detect_code_snippets_heuristic(self):
        raw = "Check this code:\nif (!(obj instanceof User)) {\n    return false;\n}\nUser other = (User) obj;\nDone."
        detected = notes._detect_code_snippets(raw, default_lang="java")
        self.assertTrue(len(detected) >= 1)
        self.assertIn("if (!(obj instanceof User))", detected[0]["content"])
        self.assertEqual(detected[0]["language"], "java")

    def test_clean_exact_excerpts_drops_hallucinated_code(self):
        raw = "Using git rebase -i HEAD~3 to squash commits interactively."
        # AI returns an excerpt that never existed in raw
        hallucinated = [{"language": "python", "content": "import os\ndef malicious(): pass"}]
        cleaned = notes._clean_exact_excerpts(hallucinated, raw)
        self.assertEqual(cleaned, [])

        # Real excerpt in raw
        real = [{"language": "bash", "content": "git rebase -i HEAD~3"}]
        cleaned_real = notes._clean_exact_excerpts(real, raw)
        self.assertEqual(len(cleaned_real), 1)
        self.assertEqual(cleaned_real[0]["content"], "git rebase -i HEAD~3")

    def test_triage_parses_and_persists_topic_section(self):
        note = notes.create_note({"raw_content": "kubectl get pods -A"})["note"]
        reply = json.dumps({
            "keep": True,
            "category": "technical",
            "technical_type": "command",
            "topic_section": "commands",
            "canonical_topic": "Kubernetes",
            "title": "List all pods",
            "technology": "Kubernetes",
            "suggested_tags": ["#k8s"],
            "essential_bullets": ["List all pods across all namespaces."],
            "completion_bullets": [],
            "exact_excerpts": [{"language": "bash", "content": "kubectl get pods -A"}]
        })
        with mock.patch.object(notes, "_run_provider", return_value=(reply, "gemini")):
            res = notes.triage_note({"id": note["id"]})
        self.assertTrue(res["success"])
        stored = notes.get_note({"id": note["id"]})["note"]
        self.assertEqual(stored["topic_section"], "commands")
        self.assertEqual(stored["technical_type"], "command")

    def test_smart_upsert_relations_are_validated_and_bidirectional(self):
        response_a = json.dumps({
            "action": "create", "domain": "Docker", "subconcept": "Images",
            "title": "Docker images", "technology": "Docker",
            "summary": "Images package application layers.", "mechanics": [],
            "snippets": [], "suggested_tags": ["#docker"], "related_note_ids": [],
        })
        with mock.patch.object(notes, "_run_provider", return_value=(response_a, "test")):
            a = notes.smart_upsert({"raw_content": "Docker images package application layers."})["note"]

        response_b = json.dumps({
            "action": "create", "domain": "Docker", "subconcept": "Containers",
            "title": "Docker containers", "technology": "Docker",
            "summary": "Containers run images.", "mechanics": [], "snippets": [],
            "suggested_tags": ["#docker"],
            "related_note_ids": [a["id"], "hallucinated-id"],
        })
        with mock.patch.object(notes, "_run_provider", return_value=(response_b, "test")) as provider:
            b = notes.smart_upsert({"raw_content": "Docker containers run Docker images."})["note"]
        prompt = provider.call_args.args[1]
        self.assertIn(a["id"], prompt)
        self.assertIn(a["title"], prompt)
        self.assertEqual(b["related_note_ids"], [a["id"]])
        stored_a = notes.get_note({"id": a["id"]})["note"]
        self.assertIn(b["id"], stored_a["related_note_ids"])
        self.assertNotIn("hallucinated-id", stored_a["related_note_ids"])

    def test_triage_relations_are_bidirectional_and_receive_context(self):
        existing = notes.create_note({"raw_content": "A Redis cache can reduce database reads."})["note"]
        with notes.database() as db:
            db.execute("UPDATE notes SET category = 'technical', title = 'Redis cache overview' WHERE id = ?",
                       (existing["id"],))
        pending = notes.create_note({"raw_content": "Redis cache invalidation strategies."})["note"]
        response = json.dumps({
            "keep": True, "category": "technical", "technical_type": "concept",
            "topic_section": "notes", "canonical_topic": "Redis",
            "title": "Cache invalidation", "technology": "Redis",
            "suggested_tags": ["#redis"], "essential_bullets": ["Invalidation keeps cached data fresh."],
            "completion_bullets": [], "exact_excerpts": [],
            "related_note_ids": [existing["id"], "unknown-id"],
        })
        with mock.patch.object(notes, "_run_provider", return_value=(response, "test")) as provider:
            result = notes.triage_note({"id": pending["id"]})
        self.assertIn(existing["id"], provider.call_args.args[0])
        self.assertEqual(result["note"]["related_note_ids"], [existing["id"]])
        self.assertIn(pending["id"], notes.get_note({"id": existing["id"]})["note"]["related_note_ids"])


if __name__ == "__main__":
    unittest.main()
