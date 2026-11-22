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

    def test_semantic_duplicate_filter_keeps_policy_contrasts(self):
        saved = "Defaults to Always when the image tag is :latest or omitted, and IfNotPresent for all other tags."
        paraphrase = "If the image tag is omitted or set to latest, imagePullPolicy defaults to Always; for any other tag, it defaults to IfNotPresent."
        reordered_paraphrase = "When the image tag is explicitly set to :latest or is completely omitted, imagePullPolicy defaults to Always. For any other explicit tag, it defaults to IfNotPresent."
        partial = "When using the :latest image tag or omitting the tag entirely, imagePullPolicy defaults to Always."
        contrast = "Use Never when the image must only come from the node's local cache."
        self.assertTrue(backend._is_duplicate_knowledge(paraphrase, [saved]))
        self.assertTrue(backend._is_duplicate_knowledge(reordered_paraphrase, [saved]))
        self.assertTrue(backend._is_duplicate_knowledge(partial, [saved]))
        self.assertFalse(backend._is_duplicate_knowledge(contrast, [saved]))

    def test_gap_endpoint_does_not_persist_semantic_duplicate(self):
        saved = "Defaults to Always when the image tag is :latest or omitted, and IfNotPresent for all other tags."
        paraphrase = "When the image tag is explicitly set to :latest or is completely omitted, imagePullPolicy defaults to Always. For any other explicit tag, it defaults to IfNotPresent."
        with backend.database() as db:
            backend._insert_concept_with_blocks(db, {
                "id": "k8s-image-policy", "topic": "Kubernetes", "area": "Images",
                "title": "imagePullPolicy", "definition": "Controls image pull behavior."
            }, [{"kind": "rule", "content": saved}])
        suggestion = {"kind": "block", "area": "Images", "title": "Default image pull behavior",
                      "content": paraphrase, "reason": "Explains the default policy.",
                      "related_concept_id": "k8s-image-policy", "block_kind": "rule"}
        partial = dict(suggestion, title="Latest tag default",
                       content="When using the :latest image tag or omitting the tag entirely, imagePullPolicy defaults to Always.")
        result, _ = self._suggest({"scope": "concept", "id": "k8s-image-policy"}, [suggestion, partial])
        self.assertEqual(result["suggestions"], [])
        self.assertEqual(backend.list_gap_proposals_rpc(
            {"scope": "concept", "id": "k8s-image-policy"})["proposals"], [])

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
        self.assertEqual(result["suggestions"][0]["evidence_status"], "unverified")
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

    def test_proposals_persist_accept_and_undo_block(self):
        suggestion = {"kind": "block", "area": "Memory", "title": "Rebinding boundary",
                      "content": "Rebinding a local parameter does not reassign the caller variable.",
                      "reason": "Clarifies reference semantics.", "related_concept_id": "java-ref",
                      "block_kind": "caveat"}
        generated, _ = self._suggest({"scope": "concept", "id": "java-ref"}, [suggestion])
        proposal_id = generated["suggestions"][0]["proposal_id"]
        stored = backend.list_gap_proposals_rpc({"scope": "concept", "id": "java-ref"})
        self.assertEqual(stored["proposals"][0]["id"], proposal_id)
        self.assertEqual(stored["proposals"][0]["proposal_id"], proposal_id)
        self.assertEqual(stored["proposals"][0]["evidence_status"], "unverified")
        with self.assertRaisesRegex(ValueError, "different concept"):
            backend.accept_gap_proposal_rpc({"proposal_id": proposal_id,
                "scope": "concept", "id": "java-list"})
        scoped = {"proposal_id": proposal_id, "scope": "concept", "id": "java-ref"}
        added = backend.accept_gap_proposal_rpc(scoped)
        self.assertEqual(added["state"], "accepted")
        self.assertEqual(backend.list_gap_proposals_rpc({"scope": "concept", "id": "java-ref"})["proposals"][0]["state"], "accepted")
        undone = backend.undo_gap_proposal_rpc(scoped)
        self.assertEqual(undone["state"], "undone")
        with backend.database() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM blocks WHERE id=?", (added["block_id"],)).fetchone()[0], 0)

    def test_topic_proposal_adds_concept_in_suggested_new_area_and_undoes(self):
        item = {"kind": "new_area", "area": "Errors", "title": "Exception handling",
                "content": "Java exceptions represent failures that callers can handle or propagate.",
                "reason": "Important for backend development.", "related_concept_id": "", "block_kind": "",
                "applicability": "Java 21+"}
        generated, _ = self._suggest({"scope": "topic", "topic": "Java"}, [item])
        proposal_id = generated["suggestions"][0]["proposal_id"]
        listed = backend.list_gap_proposals_rpc({"scope": "topic", "topic": "Java"})
        self.assertEqual(listed["proposals"][0]["area"], "Errors")
        self.assertEqual(listed["proposals"][0]["destination_area"], "Errors")
        scoped = {"proposal_id": proposal_id, "scope": "topic", "topic": "Java"}
        added = backend.accept_gap_proposal_rpc(scoped)
        with backend.database() as db:
            concept = db.execute("SELECT topic, area, title, applicability FROM concepts WHERE id=?", (added["concept_id"],)).fetchone()
            self.assertEqual(tuple(concept), ("Java", "Errors", "Exception handling", "Java 21+"))
            block = db.execute("SELECT applicability, evidence_status FROM blocks WHERE id=?", (added["block_id"],)).fetchone()
            self.assertEqual(tuple(block), ("Java 21+", "unverified"))
        backend.undo_gap_proposal_rpc(scoped)
        with backend.database() as db:
            self.assertIsNone(db.execute("SELECT id FROM concepts WHERE id=?", (added["concept_id"],)).fetchone())

    def test_dismiss_and_accept_all(self):
        one = {"kind": "block", "area": "Memory", "title": "Boundary A", "content": "A concise new point.",
               "reason": "Useful boundary.", "related_concept_id": "java-ref", "block_kind": "caveat"}
        two = dict(one, title="Boundary B", content="A second concise new point.")
        generated, _ = self._suggest({"scope": "concept", "id": "java-ref"}, [one, two])
        dismissed = generated["suggestions"][0]["proposal_id"]
        backend.dismiss_gap_proposal_rpc({"proposal_id": dismissed, "scope": "concept", "id": "java-ref"})
        ids = [s["proposal_id"] for s in generated["suggestions"][1:]]
        result = backend.accept_all_gap_proposals_rpc({"proposal_ids": ids,
            "scope": "concept", "id": "java-ref"})
        self.assertEqual(result["count"], 1)
        self.assertEqual(backend.list_gap_proposals_rpc({"scope": "concept", "id": "java-ref"})["proposals"][0]["state"], "accepted")


if __name__ == "__main__":
    unittest.main()
