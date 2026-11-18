import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("lyrics_metadata", Path(__file__).resolve().parents[1] / "scripts/lyrics_metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class LyricsMetadataTest(unittest.TestCase):
    def test_rejects_malformed_and_oversized_candidates(self):
        with self.assertRaises(ValueError):
            metadata.validate_candidates({"something_else": []})
        self.assertEqual(metadata.validate_candidates({"candidates": [
            {"artist": "JENNIE", "title": "like JENNIE"},
            {"artist": "JENNIE", "title": "like JENNIE"},
            {"artist": "Bad\nInstruction", "title": "Song"},
            {"artist": "Artist", "title": "x" * 200},
        ]}), [{"artist": "JENNIE", "title": "like JENNIE"}])

    def test_only_track_metadata_is_sent_to_gemini(self):
        seen = []

        def fake_post(url, payload, headers):
            seen.append((url, payload, headers))
            return {"candidates": [{"content": {"parts": [{"text": '{"candidates":[{"artist":"JENNIE","title":"like JENNIE"}]}' }]}}]}

        track = {"artist": "Idol_Vibes", "title": "JENNIE Like Jennie", "album": "", "duration_seconds": 124}
        with patch.object(metadata, "_post", fake_post):
            result = metadata._gemini("private-key", track)
        self.assertEqual(result, [{"artist": "JENNIE", "title": "like JENNIE"}])
        self.assertEqual(__import__("json").loads(seen[0][1]["contents"][0]["parts"][0]["text"]), track)
        self.assertEqual(seen[0][2]["x-goog-api-key"], "private-key")
        self.assertNotIn("private-key", str(seen[0][1]))
        schema = seen[0][1]["generationConfig"]["responseSchema"]
        self.assertNotIn("additionalProperties", schema)
        self.assertNotIn("additionalProperties", schema["properties"]["candidates"]["items"])

    def test_provider_fallback_and_cached_empty_result(self):
        calls = []

        def failed(key, track):
            calls.append("gemini")
            raise OSError("offline")

        def empty(key, track):
            calls.append("groq")
            return []

        with tempfile.TemporaryDirectory() as directory, patch.object(metadata, "CACHE_DIR", directory):
            args = ("Channel", "Unclear song", "", 100)
            cfg = {"primary": "gemini", "gemini_key": "gemini-secret", "groq_key": "groq-secret"}
            providers = {"gemini": failed, "groq": empty}
            self.assertEqual(metadata.guess_candidates(*args, config=cfg, providers=providers), [])
            self.assertEqual(metadata.guess_candidates(*args, config=cfg, providers=providers), [])
            self.assertEqual(calls, ["gemini", "groq"])


if __name__ == "__main__":
    unittest.main()
