# Lyrics branch: what was applied

Branch `plan/lyrics-ui`, built on `main` at 713ff0ad. The plan is in `PLAN.md` next to this file.
This file lists what is **applied** on the branch. Anything under "Not done" is still only planned.
The dashboard and calendar polish from the same plan is on its own branch, `ui/dashboard-polish`
(see its `audits/2026-11-17-dashboard-polish/CHANGES.md`).

Nothing here was run inside the shell. Everything below was checked by unit tests, by parsing
the QML with Qt's own tools, and by reading the code. The checklist at the end is what still needs
your PC.

## Applied changes

### 1. Shared lyrics logic: `utils/scripts/lyrics.js` (new)
Pure JavaScript, no QML types, so it is tested under node and under Qt's engine.
- `parseLrc`: several timestamps on one line (`[00:12.00][01:30.50]Chorus` gives two lines, and
  no timestamp is left in the text), `[mm:ss]`, `[mm:ss.x]`, `[mm:ss.xxx]`, `[mm:ss:xx]`, metadata
  tags ignored, word tags `<mm:ss.xx>` stripped, and the `[offset:]` tag applied (LRC rule: a
  positive value shows lyrics earlier). Empty timed lines are kept as instrumental gaps.
- `isInstrumentalMarker`: only a whole line counts (`[Instrumental]`, `(Guitar Solo)`, `♪ ♪`,
  `...`). "Don't break my heart" and "Let me introduce myself" stay lyrics. Before, any line
  containing `break`, `intro`, `solo`, `music`... became notes.
- `normalizeLines`: sorts, turns marker lines into gaps, adds a gap after a line whose end time
  leaves 4 s or more of silence, merges repeated gaps.
- `indexForTime`, `timeForIndex`, `msUntilNextLine`: one timing rule with the 100 ms lead the
  C++ service already uses (`k_indexFudge`), so both lyric sources change line at the same moment.
  Offset in seconds, positive delays the lyrics.
- `overlayState`: the overlay visibility decision as one pure function (see section 4).

### 2. No AI lyrics, stale results dropped: `services/BetterLyrics.qml`, `scripts/lrclib_lyrics.py` (new)
- The Gemini step is gone. Order is now Better Lyrics TTML, Better Lyrics QQ, then LRCLIB.
  `scripts/ai_lyrics.py` is deleted. When only plain lyrics exist, the status is `plain` and they
  are shown unsynced, with no made-up timestamps. When nothing matches, the status is `none`:
  no dancing notes for the whole song. An LRCLIB record marked instrumental gives `instrumental`.
- Stale results: each request carries the serial of its track. A reply that arrives after the
  track changed is dropped before it is shown or cached, for both the HTTP calls and the LRCLIB
  process. A track change also aborts the running request and stops the LRCLIB process. Before,
  a slow Gemini reply for song A was shown on song B and cached under B.
- Only real answers (`synced`, `plain`, `instrumental`) are cached. Misses and network errors are
  tried again on the next play.
- `scripts/lrclib_lyrics.py` (replaces the AI script, no API key):
  - tries LRCLIB's exact `/api/get` first (title, artist, album, duration), then searches;
  - keeps version labels: "Song (Live Acoustic Video)" is cleaned to "Song (Live Acoustic)", and
    a result must carry the same labels (live, acoustic, remix, slowed, sped up...). A studio
    track never gets live lyrics and the other way round. A bare word in the title ("Live
    Forever") is not a label;
  - accepts a result within 2 s of the track length, or within 15 s only when title, artist and
    version all match (marked approximate, for music videos with a longer intro). Anything else
    is rejected instead of falling back to the first result;
  - parses several timestamps per line and `[offset:]` (same rules as `lyrics.js`);
  - skips recitations, podcasts and trailers by whole word only, so "Dua Lipa" or "Good News"
    are not skipped;
  - caches in a new folder, `~/.cache/caelestia/lrclib_lyrics`, so old Gemini results in
    `~/.cache/caelestia/ai_lyrics` are never shown again. You can delete that old folder.
- `scripts/lyrics_fetch.py` is deleted. It was a symlink to a folder on one PC and nothing in
  the repo used it.

### 3. One source for the overlay and the media tab: `services/LyricsSource.qml` (new)
- It is now the only place that tells BetterLyrics and the C++ `Lyrics` service which track is
  playing (before, a binding in `LyricList.qml` did it, so the overlay only got lyrics once the
  dashboard had been created). Track changes are debounced by 150 ms so one change makes one
  request instead of one per metadata field.
- It picks one provider: Better Lyrics/LRCLIB timed lyrics first, then the C++ service's timed
  lyrics, then plain lyrics. `DesktopLyrics.qml`, `LyricList.qml` and `LyricsInfo.qml` all read
  it, so the overlay and the media tab show the same lines.
- Click-to-seek in the media tab now uses the times of the lines on screen. Before, it used the
  C++ times even when Better Lyrics lines were listed.
- Timing offset: one offset for both views, the C++ service's per-track offset, which it already
  saves per "artist - title" in its lyrics map. The overlay's own offset, which reset on every
  track change, is removed. Note: it is saved per artist and title, so two versions with exactly
  the same title share one offset.
- `LyricsInfo.qml`: the offset was shown as "0.5 ms" while the value is in seconds. It now shows
  milliseconds with a sign and has `-`, reset and `+` buttons (250 ms steps). The panel shows the
  source actually on screen, and says when lyrics are not synced or the match is approximate.
- `LyricList.qml`: plain lyrics are listed without a highlight and cannot be clicked to seek;
  an instrumental track shows "Instrumental track".
- `shell.qml` creates `LyricsSource` at startup next to `BetterLyrics`.

### 4. Overlay visibility and layout: `modules/background/DesktopLyrics.qml`, `Background.qml`
- Follows playback like the visualiser: hidden at once on stop; on pause the line stays for
  1.5 s and then fades out, so a quick pause does not flicker; cleared when the player closes or
  has no track; hidden while a tiled or fullscreen window covers the desktop (unchanged rule).
- "Loading lyrics…" only while playing, and only after 400 ms of loading, so fast lookups do not
  flash it.
- Plain or missing lyrics: a short notice for 3 s ("Lyrics for this track are not synced" or "No
  lyrics found for this track"), then nothing. Notes only show for real gaps, an intro of 3 s or
  more before the first line, or an instrumental track.
- Fixed rows anchored at the bottom: previous and next rows are one line each, the current row
  always has room for two lines. The block no longer jumps on the first or last line, on a
  wrapping line or in a gap.
- Arabic: the size is decided once per track (40% or more of lines in Arabic), with a 1.4 line
  height; the current row is sized from the font's real line spacing, so two Arabic lines fit.
  Before, about 140 px were needed in a fixed 120 px box.
- Fades: line changes cross-fade through `StyledText`'s `animate`, and the notes fade in and
  out. Before, the fade animations never ran.
- Timing: it wakes up when the next line is due (at most every 250 ms, so a seek is picked up
  quickly) instead of polling every 200 ms and switching up to 200 ms late. It follows the
  player's rate.
- Centring: shifted by half the bar's exclusive zone plus the visualiser spacing, the same
  values `Visualiser.qml` uses for its left margin, so the lyrics are centred on the bars and
  not on the whole screen.
- Colours unchanged: current line `m3primary`, side lines `m3onSurfaceVariant`, same shadow.

## Commits (oldest first)
- `lyrics: shared timing, LRC parser and visibility logic with tests`
- `lyrics: real lyrics only, no Gemini; drop stale fetch results`
- `lyrics: one source for the overlay and the media tab, per-track offset controls`
- `lyrics overlay: follow playback, stable layout, real fades, centred on the bars`
- `tests: qmlformat the QML test files`
- `docs: list applied lyrics changes` (this file)

## Tests run (on a Linux VM, Qt 6.4 tools, node 18, Python 3)
- `node tests/lyrics_logic.test.js`: 32 passed, 0 failed. Parser (multiple timestamps, all
  timestamp forms, offset tag both signs, gaps, word tags, Arabic), instrumental markers,
  normalisation, index/offset/seek, rows, Arabic detection, overlay states (stop, pause grace,
  loading delay, gaps, intro, plain/none notice, instrumental).
- `python3 -m unittest tests.test_lrclib_lyrics`: 24 tests, OK. Title cleaning and version
  labels, skip rules, LRC parsing, wrong-version rejection, duration window, approximate
  matches, bilingual titles, plain lyrics never timed, exact-get-first, network errors.
- `bash tests/run_qml_tests.sh` (qmltestrunner, offscreen, stub Quickshell modules): 15 passed,
  0 failed. Runs `lyrics.js` in Qt's engine, and the real `BetterLyrics.qml`: a late reply for
  the previous track is dropped and not cached under either track, `clearTrack` cancels pending
  replies, plain results have no timing, misses are not cached, cache restore, marker-only lines
  fall through, TTML and QRC/LRC parsing.
- Existing Python tests (`python3 -m unittest discover -s tests -p "test_*.py"`): all pass.
- Live LRCLIB check of the new script (real network): "Hello (Official Music Video)" by Adele,
  "Wonderwall (Live)" by Oasis, "Bohemian Rhapsody" and "Shape of You (Acoustic)" all returned
  timed lyrics from the exact lookup, and the live and acoustic tracks matched the live and
  acoustic records.
- `qmlformat` parses every changed QML file, and they are in the repo's format. `qmllint` from
  Qt 6.4 cannot resolve Quickshell or the Caelestia plugin here, so only syntax was checked, not
  types or property names against those modules.

## Not done
- The C++ `Lyrics` service (`plugin/src/Caelestia/Services/lyrics.cpp`) was not changed. Its own
  LRC parser still keeps only the first timestamp on a line and ignores `[offset:]`, and its
  LRCLIB search can still pick the first timed result. `LyricsSource` now uses it only after
  Better Lyrics and LRCLIB through the new script found nothing timed, and its lines go through
  the whole-line marker check. Fixing it means rebuilding the plugin, which I could not do or
  test here.
- Audio transcription or forced alignment for tracks with no timed lyrics anywhere: out of scope.

## Check on your PC
1. Rebuild and restart the shell, then play a song with known lyrics: the overlay shows three
   rows, and the block stays in place on the first line, the last line and long wrapping lines.
2. Stop the player: lyrics disappear at once. Pause: the line stays about 1.5 s, then fades.
   Resume within a second: no flicker. Close the player: nothing is left on screen.
3. Skip quickly through three or four tracks: the overlay never shows the previous song's
   lines, and the media tab and the overlay show the same line.
4. A song with an instrumental break: notes show during the break; lines containing "break" or
   "intro" still show as text.
5. A track LRCLIB only has plain lyrics for: the overlay shows "not synced" for 3 s, then hides;
   the media tab lists the plain text without a highlight.
6. A live or acoustic upload: either the matching version's lyrics or none, never the studio
   ones.
7. In the media tab's info panel, press `+` a few times: lyrics come later in both views. Skip
   away and back: the offset is still there.
8. An Arabic or Darija song: two lines fit in the current row and the Arabic font loads.
9. Check that the lyrics are centred under the bars, and readable on your usual wallpapers.
10. Optional: delete `~/.cache/caelestia/ai_lyrics`, which only holds old Gemini results.
