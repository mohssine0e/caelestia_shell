import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("lrclib_lyrics", Path(__file__).resolve().parents[1] / "scripts/lrclib_lyrics.py")
lrclib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lrclib)


def record(name, artist, duration, synced="[00:01.00]Hello", plain="Hello", **extra):
    item = {"id": abs(hash((name, artist, duration))) % 100000, "trackName": name, "artistName": artist,
            "albumName": "", "duration": duration, "syncedLyrics": synced, "plainLyrics": plain, "instrumental": False}
    item.update(extra)
    return item


class TitleCleaningTest(unittest.TestCase):
    def test_keeps_version_labels(self):
        self.assertEqual(lrclib.clean_title("Song (Live Acoustic Video)"), "Song (Live Acoustic)")
        self.assertEqual(lrclib.clean_title("Song [Official Music Video]"), "Song")
        self.assertEqual(lrclib.clean_title("Song (Remix) [Official Audio]"), "Song (Remix)")

    def test_strips_artist_prefix(self):
        self.assertEqual(lrclib.clean_title("Adele - Hello (Official Video)", "Adele"), "Hello")

    def test_version_labels_only_in_brackets_or_suffix(self):
        self.assertEqual(lrclib.version_labels("Live Forever"), frozenset())
        self.assertEqual(lrclib.version_labels("Song (Live)"), frozenset({"live"}))
        self.assertEqual(lrclib.version_labels("Song - Acoustic Version"), frozenset({"acoustic"}))
        self.assertEqual(lrclib.version_labels("Song (Live Acoustic Video)"), frozenset({"live", "acoustic"}))
        self.assertEqual(lrclib.version_labels("Song (Slowed + Reverb)"), frozenset({"slowed", "reverb"}))

    def test_remaster_is_not_a_version(self):
        self.assertEqual(lrclib.version_labels("Song (Remastered 2011)"), frozenset())
        self.assertEqual(lrclib.clean_title("Song (Remastered 2011)"), "Song")

    def test_arabic_noise_removed(self):
        cleaned = lrclib.clean_title("\u0645\u0634\u064a\u062a (\u0641\u064a\u062f\u064a\u0648 \u0643\u0644\u064a\u0628 \u062d\u0635\u0631\u064a\u0627)")
        self.assertEqual(cleaned, "\u0645\u0634\u064a\u062a")

    def test_normalize_arabic_diacritics(self):
        self.assertEqual(lrclib.normalize("\u0623\u064e\u062d\u0652\u0628\u064e\u0628\u0652\u062a\u064f\u0643"), lrclib.normalize("\u0627\u062d\u0628\u0628\u062a\u0643"))

    def test_lyrics_upload_can_contain_the_real_artist(self):
        track = lrclib.Track("MandemFill", "Screwface Capital - Dave Lyrics", "", 253.581)
        self.assertEqual((lrclib.upload_track_candidates(track)[0].artist,
                          lrclib.upload_track_candidates(track)[0].title), ("Dave", "Screwface Capital"))
        self.assertEqual([(item.artist, item.title) for item in lrclib.upload_track_candidates(
            lrclib.Track("Channel", "Screwface Capital - Dave", "", 253))],
            [("Dave", "Screwface Capital"), ("Screwface Capital", "Dave")])

    def test_mixed_script_quoted_upload_extracts_artist_and_song(self):
        track = lrclib.Track("Idol_Vibes", 'JENNIE(제니) "Like Jennie\' Lyrics (Color Coded)', "", 123.621)
        self.assertEqual([(item.artist, item.title) for item in lrclib.upload_track_candidates(track)],
                         [("JENNIE", "Like Jennie")])

    def test_topic_channel_is_not_treated_as_the_artist(self):
        track = lrclib.Track("Siti Thania - Topic", "Ma Qoul Insak", "", 200)
        self.assertEqual((lrclib.upload_track_candidates(track)[0].artist,
                          lrclib.upload_track_candidates(track)[0].title), ("Siti Thania", "Ma Qoul Insak"))


class SkipTest(unittest.TestCase):
    def test_whole_word_only(self):
        self.assertFalse(lrclib.should_skip_lyrics("Dua Lipa", "Levitating", ""))
        self.assertFalse(lrclib.should_skip_lyrics("Artist", "Good News", ""))
        self.assertTrue(lrclib.should_skip_lyrics("Mishary Alafasy", "Surah Al-Kahf", ""))
        self.assertTrue(lrclib.should_skip_lyrics("Channel", "Episode 4 podcast", ""))


class LrcParserTest(unittest.TestCase):
    def test_multiple_timestamps(self):
        lines = lrclib.parse_lrc("[00:12.00][01:30.50]Chorus\n[00:20.00]Verse")
        self.assertEqual([(l["time"], l["text"]) for l in lines], [(12.0, "Chorus"), (20.0, "Verse"), (90.5, "Chorus")])

    def test_offset_tag(self):
        self.assertEqual(lrclib.parse_lrc("[offset:+500]\n[00:10.00]x")[0]["time"], 9.5)
        self.assertEqual(lrclib.parse_lrc("[offset:-500]\n[00:10.00]x")[0]["time"], 10.5)

    def test_empty_line_kept_as_gap(self):
        lines = lrclib.parse_lrc("[00:01.00]a\n[00:30.00]\n[00:40.00]b")
        self.assertEqual([l["text"] for l in lines], ["a", "", "b"])


class MatchingTest(unittest.TestCase):
    def test_rejects_different_version(self):
        track = lrclib.Track("Artist", "Song (Live Acoustic Video)", "", 200)
        studio = record("Song", "Artist", 200)
        self.assertIsNone(lrclib.choose_best(track, [studio]))
        live = record("Song (Live Acoustic)", "Artist", 201)
        self.assertIs(lrclib.choose_best(track, [studio, live])[0], live)

    def test_rejects_live_for_studio_track(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        self.assertIsNone(lrclib.choose_best(track, [record("Song (Live)", "Artist", 200)]))

    def test_duration_window(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        exact = lrclib.choose_best(track, [record("Song", "Artist", 201.5)])
        self.assertFalse(exact[1])
        approx = lrclib.choose_best(track, [record("Song", "Artist", 210)])
        self.assertTrue(approx[1])
        self.assertEqual(approx[2], 10.0)
        self.assertIsNone(lrclib.choose_best(track, [record("Song", "Artist", 240)]))

    def test_approximate_needs_title_and_artist(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        self.assertIsNone(lrclib.choose_best(track, [record("Song", "Someone Else", 210)]))

    def test_unrelated_title_rejected(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        self.assertIsNone(lrclib.choose_best(track, [record("Other Tune", "Nobody", 200)]))

    def test_prefers_synced_and_exact(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        plain_only = record("Song", "Artist", 200, synced=None)
        synced_far = record("Song", "Artist", 208)
        synced_close = record("Song", "Artist", 199)
        self.assertIs(lrclib.choose_best(track, [plain_only, synced_far, synced_close])[0], synced_close)

    def test_bilingual_title(self):
        track = lrclib.Track("Artist", "\u0645\u0634\u064a\u062a | Mchit", "", 180)
        self.assertIsNotNone(lrclib.choose_best(track, [record("Mchit", "Artist", 180)]))


class ResultTest(unittest.TestCase):
    def test_plain_lyrics_never_get_timing(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        result = lrclib.build_result(track, lrclib.choose_best(track, [record("Song", "Artist", 200, synced=None, plain="a\nb")]))
        self.assertEqual(result["status"], "plain")
        self.assertEqual(result["lines"], [])
        self.assertEqual(result["plain"], "a\nb")

    def test_none(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        self.assertEqual(lrclib.build_result(track, None)["status"], "none")

    def test_instrumental_record(self):
        track = lrclib.Track("Artist", "Song", "", 200)
        item = record("Song", "Artist", 200, synced=None, plain=None, instrumental=True)
        self.assertEqual(lrclib.build_result(track, lrclib.choose_best(track, [item]))["status"], "instrumental")

    def test_lookup_uses_exact_get_first(self):
        calls = []

        def fake(path, params):
            calls.append(path)
            if path == "get":
                return record("Song", "Artist", 200)
            return []

        result = lrclib.lookup(lrclib.Track("Artist", "Song", "", 200), get_json=fake)
        self.assertEqual(result["status"], "synced")
        self.assertEqual(result["reason"], "exact")
        self.assertEqual(calls, ["get"])

    def test_lookup_search_filters_wrong_version(self):
        def fake(path, params):
            if path == "get":
                return None
            return [record("Song (Live)", "Artist", 200), record("Song", "Artist", 200, syncedLyrics=None, synced=None)]

        result = lrclib.lookup(lrclib.Track("Artist", "Song", "", 200), get_json=fake)
        self.assertEqual(result["status"], "plain")

    def test_lookup_network_error(self):
        def fake(path, params):
            raise OSError("offline")

        result = lrclib.lookup(lrclib.Track("Artist", "Song", "", 200), get_json=fake)
        self.assertEqual(result["status"], "none")
        self.assertEqual(result["reason"], "network error")

    def test_lookup_recovers_song_and_artist_from_lyrics_upload(self):
        calls = []

        def fake(path, params):
            calls.append((path, params))
            if path == "get" and params["track_name"] == "Screwface Capital" and params["artist_name"] == "Dave":
                return record("Screwface Capital", "Dave", 253)
            return None if path == "get" else []

        track = lrclib.Track("MandemFill", "Screwface Capital - Dave Lyrics", "", 253.581)
        result = lrclib.lookup(track, get_json=fake)
        self.assertEqual(result["status"], "synced")
        self.assertEqual(result["reason"], "upload title")
        self.assertEqual(result["match"]["artistName"], "Dave")
        self.assertEqual(len(calls), 1)

    def test_lookup_recovers_mixed_script_quoted_upload(self):
        def fake(path, params):
            if path == "get" and params["track_name"] == "Like Jennie" and params["artist_name"] == "JENNIE":
                return record("like JENNIE", "JENNIE", 124)
            return None if path == "get" else []

        track = lrclib.Track("Idol_Vibes", 'JENNIE(제니) "Like Jennie\' Lyrics (Color Coded)', "", 123.621)
        result = lrclib.lookup(track, get_json=fake)
        self.assertEqual(result["status"], "synced")
        self.assertEqual(result["match"]["artistName"], "JENNIE")

    def test_upload_hint_needs_catalog_artist_confirmation(self):
        def fake(path, params):
            if path == "get":
                return record("Screwface Capital", "Someone Else", 253)
            return []

        track = lrclib.Track("MandemFill", "Screwface Capital - Dave Lyrics", "", 253.581)
        self.assertEqual(lrclib.lookup(track, get_json=fake)["status"], "none")

    def test_upload_hint_searches_one_candidate_when_duration_is_approximate(self):
        def fake(path, params):
            if path == "search" and params == {"track_name": "Screwface Capital", "artist_name": "Dave"}:
                return [record("Screwface Capital", "Dave", 251)]
            return None if path == "get" else []

        track = lrclib.Track("MandemFill", "Screwface Capital - Dave Lyrics", "", 253.581)
        result = lrclib.lookup(track, get_json=fake)
        self.assertEqual(result["status"], "synced")
        self.assertTrue(result["approximate"])
        self.assertEqual(result["reason"], "upload title")

    def test_ai_hint_is_used_only_after_catalog_checks_and_verified(self):
        calls = []

        def fake(path, params):
            calls.append((path, params))
            if path == "get" and params["artist_name"] == "JENNIE" and params["track_name"] == "like JENNIE":
                return record("like JENNIE", "JENNIE", 124)
            return None if path == "get" else []

        track = lrclib.Track("Idol_Vibes", "JENNIE performing Like Jennie, color coded", "", 123.621)
        result = lrclib.lookup(track, get_json=fake,
                               metadata_fn=lambda *args: [{"artist": "JENNIE", "title": "like JENNIE"}])
        self.assertEqual(result["status"], "synced")
        self.assertEqual(result["reason"], "verified AI metadata")
        self.assertEqual(calls[-1][1]["artist_name"], "JENNIE")

    def test_ai_hint_without_title_evidence_is_rejected(self):
        calls = []

        def fake(path, params):
            calls.append(params)
            return None if path == "get" else []

        track = lrclib.Track("Channel", "Some unrelated upload", "", 200)
        result = lrclib.lookup(track, get_json=fake,
                               metadata_fn=lambda *args: [{"artist": "Adele", "title": "Hello"}])
        self.assertEqual(result["status"], "none")
        self.assertFalse(any(params.get("artist_name") == "Adele" for params in calls))

    def test_catalog_network_failure_does_not_spend_an_ai_call(self):
        requested = []

        def offline(path, params):
            raise OSError("offline")

        result = lrclib.lookup(lrclib.Track("Channel", "Song title", "", 200), get_json=offline,
                               metadata_fn=lambda *args: requested.append(args))
        self.assertEqual(result["reason"], "network error")
        self.assertEqual(requested, [])

    def test_web_fallback_invoked_when_catalogs_miss(self):
        def fake(path, params):
            return None if path == "get" else []

        track = lrclib.Track("Reda Taliani - Topic", "Sfina", "", 323.0)
        web_called = []
        def fake_web(artist, title):
            web_called.append((artist, title))
            return "Line 1\nLine 2\nLine 3"

        result = lrclib.lookup(track, get_json=fake, metadata_fn=lambda *args: [{"artist": "Reda Taliani", "title": "Sfina"}], web_fallback_fn=fake_web)
        self.assertEqual(result["status"], "plain")
        self.assertEqual(result["source"], "Web")
        self.assertEqual(result["reason"], "web search fallback")
        self.assertEqual(result["plain"], "Line 1\nLine 2\nLine 3")
        self.assertEqual(web_called, [("Reda Taliani", "Sfina")])

    def test_web_fallback_not_invoked_on_network_error(self):
        def offline(path, params):
            raise OSError("offline")

        web_called = []
        result = lrclib.lookup(lrclib.Track("Artist", "Song", "", 200), get_json=offline, web_fallback_fn=lambda *args: web_called.append(args))
        self.assertEqual(result["reason"], "network error")
        self.assertEqual(web_called, [])


if __name__ == "__main__":
    unittest.main()
