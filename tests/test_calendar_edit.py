import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("calendar_edit", Path(__file__).resolve().parents[1] / "scripts/calendar_edit.py")
calendar_edit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calendar_edit)


class CalendarEditTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name) / "config"
        self.cache = Path(self.temp.name) / "cache"
        self.config.mkdir()
        self.cache.mkdir()
        self.day = "2026-11-16"
        self.local = {"id": "local_1", "title": "Review", "time": "14:00", "all_day": False, "is_local": True, "location": "Office"}
        self.remote = {"id": "remote_1", "title": "Review", "time": "14:00", "is_local": False}
        self.local_path = self.config / "local_events.json"
        self.cache_path = self.cache / "gcal.json"
        self.completed_path = self.config / "calendar_completed.json"
        self.local_path.write_text(json.dumps({"events": {self.day: [self.local]}}))
        self.cache_path.write_text(json.dumps({"configured": True, "events": {self.day: [self.local, self.remote]}}))
        self.completed_path.write_text(json.dumps({self.day + "_Review": True}))
        self.payload = {"date": self.day, "id": "local_1", "original_title": "Review", "original_time": "14:00", "title": "Design review", "time": "15:00"}

    def edit(self):
        calendar_edit.edit_event(self.payload, self.config, self.cache)

    def test_edit_preserves_identity_location_remote_and_completion(self):
        self.edit()
        events = json.loads(self.cache_path.read_text())["events"][self.day]
        self.assertEqual(len(events), 2)
        self.assertIn(self.remote, events)
        updated = next(e for e in events if e["id"] == "local_1")
        self.assertEqual((updated["title"], updated["time"], updated["location"]), ("Design review", "15:00", "Office"))
        self.assertTrue(json.loads(self.completed_path.read_text())[self.day + "_Design review"])

    def test_unreadable_cache_does_not_overwrite_any_data(self):
        self.cache_path.write_text("{broken")
        before = self.local_path.read_bytes(), self.completed_path.read_bytes()
        with self.assertRaises(ValueError):
            self.edit()
        self.assertEqual(before, (self.local_path.read_bytes(), self.completed_path.read_bytes()))
        self.assertEqual(self.cache_path.read_text(), "{broken")

    def test_stale_edit_rejected(self):
        self.payload["original_title"] = "Outdated title"
        before = self.local_path.read_bytes()
        with self.assertRaises(ValueError):
            self.edit()
        self.assertEqual(self.local_path.read_bytes(), before)

    def test_ambiguous_legacy_event_rejected(self):
        legacy = dict(self.local)
        del legacy["id"]
        self.local_path.write_text(json.dumps({"events": {self.day: [legacy, legacy]}}))
        with self.assertRaises(ValueError):
            self.edit()

    def test_edit_never_creates_missing_event(self):
        self.payload["id"] = "remote_1"
        with self.assertRaises(ValueError):
            self.edit()

    def test_all_day_edit(self):
        self.payload["time"] = "All day"
        self.edit()
        self.assertTrue(json.loads(self.local_path.read_text())["events"][self.day][0]["all_day"])


if __name__ == "__main__":
    unittest.main()
