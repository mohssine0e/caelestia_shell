import json
import multiprocessing
import os
import stat
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone

from memory_test_support import SCRIPTS, TempConfig

import user_facts as store


def _add_many(config_dir, prefix, count):
    os.environ["CAELESTIA_CONFIG_DIR"] = config_dir
    for i in range(count):
        store.mutate(lambda d, i=i: store.add_fact(d, {"text": f"{prefix} fact number {i}", "category": "skill"}))


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.cfg = TempConfig()

    def tearDown(self):
        self.cfg.close()

    def add(self, **fields):
        data = {"text": "Knows Java and Spring Boot", "category": "skill"}
        data.update(fields)
        return store.mutate(lambda d: store.add_fact(d, data))

    def test_missing_file_lists_empty(self):
        out = store.list_facts()
        self.assertEqual(out["state"], "missing")
        self.assertEqual(out["facts"], [])

    def test_add_writes_private_file_and_bumps_revision(self):
        res = self.add()
        self.assertTrue(res["success"])
        self.assertEqual(res["revision"], 1)
        mode = stat.S_IMODE(os.stat(store.facts_path()).st_mode)
        self.assertEqual(mode, 0o600)
        fact = store.list_facts()["facts"][0]
        self.assertEqual(fact["status"], "approved")  # typed by the user
        self.assertEqual(fact["source"]["kind"], "manual")
        self.assertEqual(fact["layer"], "durable")

    def test_changing_category_gets_review_date(self):
        self.add(text="Looking for a PFE internship from February 2027", category="goal")
        fact = store.list_facts()["facts"][0]
        self.assertEqual(fact["layer"], "changing")
        self.assertTrue(fact["review_after"])

    def test_invalid_input_rejected(self):
        with self.assertRaises(store.StoreError):
            self.add(text="x")
        with self.assertRaises(store.StoreError):
            self.add(category="mood")
        with self.assertRaises(store.StoreError):
            self.add(review_after="next week")

    def test_duplicate_manual_fact_refused(self):
        self.add()
        with self.assertRaises(store.StoreError) as ctx:
            self.add(text="knows java, and spring boot!")
        self.assertEqual(ctx.exception.code, "duplicate")

    def test_stale_revision_refused(self):
        self.add()
        with self.assertRaises(store.StoreError) as ctx:
            store.mutate(lambda d: store.add_fact(d, {"text": "Plays chess", "category": "background"}),
                         expected_revision=0)
        self.assertEqual(ctx.exception.code, "stale_revision")
        self.assertEqual(len(store.list_facts()["facts"]), 1)

    def test_corrupt_file_is_never_overwritten(self):
        self.cfg.write("user_facts.json", "{not json")
        with self.assertRaises(store.StoreError) as ctx:
            self.add()
        self.assertEqual(ctx.exception.code, "store_corrupt")
        with open(store.facts_path(), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "{not json")
        self.assertEqual(store.approved_facts(), [])
        res = store.recover()
        self.assertTrue(res["recovered"])
        with open(res["backup_path"], encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "{not json")
        self.assertTrue(self.add()["success"])

    def test_wrong_shape_counts_as_corrupt(self):
        self.cfg.write("user_facts.json", json.dumps({"facts": [{"no_id": True}]}))
        self.assertEqual(store.read_document()[1], "corrupt")

    def test_concurrent_writers_lose_nothing(self):
        procs = [multiprocessing.Process(target=_add_many, args=(self.cfg.dir, f"writer{n}", 15)) for n in range(4)]
        for p in procs:
            p.start()
        for p in procs:
            p.join(30)
            self.assertEqual(p.exitcode, 0)
        out = store.list_facts()
        self.assertEqual(len(out["facts"]), 60)
        self.assertEqual(out["revision"], 60)

    def test_cli_round_trip(self):
        env = dict(os.environ)
        script = os.path.join(SCRIPTS, "user_facts.py")
        add = subprocess.run([sys.executable, script, "add", "--stdin-json"], env=env, text=True, capture_output=True,
                             input=json.dumps({"fact": {"text": "Prefers short answers", "category": "preference"}}))
        self.assertEqual(add.returncode, 0, add.stdout + add.stderr)
        listed = subprocess.run([sys.executable, script, "list"], env=env, text=True, capture_output=True)
        data = json.loads(listed.stdout)
        self.assertEqual(data["facts"][0]["text"], "Prefers short answers")
        bad = subprocess.run([sys.executable, script, "status", "--stdin-json"], env=env, text=True, capture_output=True,
                             input=json.dumps({"id": "nope", "status": "approved"}))
        self.assertEqual(json.loads(bad.stdout)["error"], "not_found")


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.cfg = TempConfig()

    def tearDown(self):
        self.cfg.close()

    def test_sensitive_opt_in_defaults_off_and_validates(self):
        self.assertFalse(store.include_sensitive_setting())
        store.mutate(lambda d: store.update_settings(d, {"include_sensitive_in_replies": True}))
        self.assertTrue(store.include_sensitive_setting())
        self.assertTrue(store.list_facts()["settings"]["include_sensitive_in_replies"])
        with self.assertRaises(store.StoreError):
            store.mutate(lambda d: store.update_settings(d, {"include_sensitive_in_replies": "yes"}))
        with self.assertRaises(store.StoreError):
            store.mutate(lambda d: store.update_settings(d, {"something": True}))

    def test_cli_reads_one_line_with_stdin_left_open(self):
        script = os.path.join(SCRIPTS, "user_facts.py")
        proc = subprocess.Popen([sys.executable, script, "add", "--stdin-json"], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, text=True, env=dict(os.environ))
        proc.stdin.write(json.dumps({"fact": {"text": "Likes long walks", "category": "background"}}) + "\n")
        proc.stdin.flush()
        out = proc.stdout.readline()  # must answer without stdin being closed
        proc.stdin.close()
        proc.wait(10)
        self.assertTrue(json.loads(out)["success"])


class ReviewTransitionTests(unittest.TestCase):
    def setUp(self):
        self.cfg = TempConfig()
        self.now = datetime(2026, 11, 17, tzinfo=timezone.utc)

    def tearDown(self):
        self.cfg.close()

    def candidate(self, doc, text, **extra):
        fact = store.build_fact(dict({"text": text, "category": "goal", "source_ai": "chatgpt"}, **extra),
                                source_kind="import", now=self.now)
        doc["facts"].append(fact)
        return fact

    def test_allowed_and_refused_transitions(self):
        doc = store.empty_document()
        fact = self.candidate(doc, "Wants a backend PFE")
        self.assertEqual(fact["status"], "candidate")
        store.set_status(doc, fact["id"], "approved", now=self.now)
        self.assertTrue(fact["last_confirmed"])
        with self.assertRaises(store.StoreError):
            store.set_status(doc, fact["id"], "candidate", now=self.now)
        store.set_status(doc, fact["id"], "archived", now=self.now)
        store.set_status(doc, fact["id"], "approved", now=self.now)
        with self.assertRaises(store.StoreError):
            store.set_status(doc, fact["id"], "deleted", now=self.now)

    def test_approving_conflict_archives_old_value(self):
        doc = store.empty_document()
        old = self.candidate(doc, "Available for a PFE from January 2027")
        store.set_status(doc, old["id"], "approved", now=self.now)
        new = self.candidate(doc, "Available for a PFE from February 2027")
        new["conflicts_with"] = [old["id"]]
        res = store.set_status(doc, new["id"], "approved", now=self.now)
        self.assertEqual(res["archived"], [old["id"]])
        self.assertEqual(old["status"], "archived")
        self.assertIn(old["id"], new["supersedes"])
        self.assertEqual(new["conflicts_with"], [])

    def test_edit_keeps_previous_text_and_validates(self):
        doc = store.empty_document()
        fact = self.candidate(doc, "Learning Docker")
        store.edit_fact(doc, fact["id"], {"text": "Learning Docker networking"}, now=self.now)
        self.assertEqual(fact["text"], "Learning Docker networking")
        self.assertEqual(fact["previous_texts"], ["Learning Docker"])
        with self.assertRaises(store.StoreError):
            store.edit_fact(doc, fact["id"], {"status": "approved"}, now=self.now)
        with self.assertRaises(store.StoreError):
            store.edit_fact(doc, fact["id"], {"category": "nonsense"}, now=self.now)

    def test_confirm_moves_review_date(self):
        doc = store.empty_document()
        fact = self.candidate(doc, "Applying to PFE offers in Casablanca")
        store.set_status(doc, fact["id"], "approved", now=self.now)
        fact["review_after"] = "2026-11-01"
        self.assertTrue(store.is_stale(fact, self.now))
        store.confirm_fact(doc, fact["id"], now=self.now)
        self.assertFalse(store.is_stale(fact, self.now))
        self.assertEqual(fact["review_after"], (self.now + timedelta(days=90)).date().isoformat())

    def test_batch_and_delete_by_source(self):
        doc = store.empty_document()
        a = self.candidate(doc, "Fact one from gpt")
        b = self.candidate(doc, "Fact two from gpt")
        c = self.candidate(doc, "Fact from claude", source_ai="claude")
        res = store.batch_status(doc, "approved", source_ai="chatgpt", only_status="candidate", now=self.now)
        self.assertEqual(sorted(res["changed"]), sorted([a["id"], b["id"]]))
        self.assertEqual(c["status"], "candidate")
        res = store.delete_facts(doc, source_ai="chatgpt")
        self.assertEqual(len(res["deleted"]), 2)
        self.assertEqual([f["id"] for f in doc["facts"]], [c["id"]])
        with self.assertRaises(store.StoreError):
            store.delete_facts(doc)


if __name__ == "__main__":
    unittest.main()
