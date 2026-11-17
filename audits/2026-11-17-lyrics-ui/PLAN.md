# Lyrics overlay and dashboard UI: technical plan

This is a plan, not an implementation. No QML, C++ or Python file is changed on this branch. It is based on a read of `main` at commit `713ff0ad` (pushed 2026-11-16 22:54 UTC), plus a few small offline checks described in each section. Nothing was run in the live shell, so every visual claim below is either a static code finding or is marked as needing a screenshot.

The main conclusion: the bug you reported (lyrics staying on screen after the music stops while the visualiser bars go away) comes from the two components using different visibility rules. Fixing that, and making the timing data honest, will matter more for quality than any new animation. The visual work after that is mostly tightening: one spacing rhythm, fixed line slots, clearer colour roles. Your palette itself stays.

Legend used below:

- **Static**: read directly in the code.
- **Tested offline**: the function was run outside the shell on sample input.
- **Needs live check**: depends on wallpaper, fonts, compositor or real players; confirm with a screenshot or a run.

## 1. The reported bug: lyrics stay after the music stops

### Root cause (static)

`modules/background/Visualiser.qml` line 20:

```qml
shouldBeActive: Config.background.visualiser.enabled && (!autoHide || !hasToplevels) && root.isMusicPlaying
```

`isMusicPlaying` is `Players.active.isPlaying`, which Quickshell defines as `playbackState == Playing`. So the bars fade out on **pause and on stop**.

`modules/background/DesktopLyrics.qml` line 70:

```qml
shown: !!root.player && !root.shouldHide && ((root.activeHasLyrics && root.hasText) || root.activeLoading)
```

There is no playback-state term. As long as an MPRIS player object exists and has lyrics, the overlay stays at full opacity. Only the 200 ms update `Timer` (line 168) checks `isPlaying`, so on pause or stop the overlay **freezes on the last line** instead of hiding.

### What happens in each state today

| State | Visualiser | Lyrics overlay (today) |
|---|---|---|
| Playing | shown | shown, updates every 200 ms |
| Paused | hidden | shown, frozen on current line |
| Stopped (metadata kept) | hidden | shown, frozen |
| No player | hidden | hidden (`!!root.player` fails); `Lyrics` C++ service is not cleared, only `BetterLyrics` is (line 88) |
| End of track | hidden once player leaves Playing | last lyric line stays, because `BetterLyrics.apply()` drops empty timestamp lines, including the usual empty end marker (LRCLIB's own example ends with `[03:25.72] `) |
| Track switch | follows new state | old lines cleared only when new fetch starts; "Loading lyrics..." shows even if paused |
| Tiled or fullscreen window on workspace | hidden (if autoHide) | hidden (own `shouldHide`, not tied to `autoHide`) |

### Recommended policy

There is no universal industry rule for this. Hiding lyrics when playback stops is your preference, and it also matches what your visualiser already does, so the two layers will finally agree.

1. **Playing**: show.
2. **Paused**: fade out after a short grace period (suggest 1.5 s, configurable, so a quick pause and play does not flicker). On resume, recompute the line first, then fade in.
3. **Stopped**: hide immediately and clear the displayed lines.
4. **No player**: hide and clear both `BetterLyrics` and `Lyrics`.
5. **End of track**: hide when the player leaves Playing; while still playing past the last line, hide once the last line's end time passes (TTML gives end times) or a fixed time after the last line when only LRC is available.
6. **Track switch**: clear old lines immediately. Show "Loading lyrics..." only while playing and only after about 400 ms, so a cached hit never flashes it.
7. **Window cover rule**: share one `shouldHide` helper with the visualiser and respect the same `autoHide` setting.

Implementation sketch (for later): add `readonly property bool playing: root.player?.playbackState === MprisPlaybackState.Playing` and a `pauseGrace` `Timer`; `shown` becomes `playingOrInGrace && !shouldHide && (...)`.

### Acceptance criteria

- Pause: lyrics opacity reaches 0 within grace + one fade duration; bars and lyrics are both gone.
- Resume after a 10 s pause: the first visible line is the correct one for the current position (no frame of the old line).
- Stop from `playerctl stop`: overlay hidden within one fade, `displayedLyric` empty.
- Close the player: both services cleared (no lyrics reappear when another player starts with a different song).
- Skip track while paused: no "Loading lyrics..." text appears.
- Pause and resume within 1 s: no flicker.

## 2. Data and sync problems found (verified against the current code)

Each item from the earlier review was rechecked on `713ff0ad`.

1. **AI invents lyrics and timing (static, still true).** `scripts/ai_lyrics.py` `query_gemini()` asks Gemini to write the lyrics and per-word times when nothing is found, and `query_gemini_with_real_lyrics()` asks it to invent timings for LRCLIB plain lyrics. When everything fails it prints `[{"time": 0.0, "text": "♪"}]`, which the overlay renders as dancing notes for the whole song instead of hiding.
2. **Stale AI result can land on the next song (static, new finding).** In `services/BetterLyrics.qml`, `aiProc.onExited` applies its output with `root.requestSerial`, the serial current at exit time, not the one that started it. If you skip while the Python script runs, the previous song's lyrics are applied to and cached under the new song. Also, `fail()` refuses to start a new AI run while one is running, so the new song goes straight to failure. `setTrack()` never stops `aiProc` (only `clearTrack()` does).
3. **Wrong version selection (static, still true).** `fetch_lrclib()` only uses `/api/search`, accepts a duration difference under 6 s, then falls back to the first result that has synced lyrics regardless of duration. LRCLIB's docs say `/api/get` matches the duration within ±2 s and that "the provided duration is crucial" ([LRCLIB API docs](https://lrclib.net/docs)). Note: the C++ `Lyrics` service already uses `/api/get` first; only the Python path is weak.
4. **Version labels removed (tested offline).** `clean_title("Song (Live Acoustic Video)")` returns `"Song"`, and `"Song (Remastered 2011)"` returns `"Song"`. `"Song (Acoustic Version)"` survives. The regex deletes the whole bracket when it contains words like video or remaster.
5. **Python LRC parser gaps (tested offline).** `parse_lrc("[00:10.00][01:10.00]Chorus")` returns one line at 10 s with text `"[01:10.00]Chorus"`; the repeat at 70 s is lost. `[offset:]` is ignored and empty timestamp lines (gap and end markers) are dropped. The C++ parser in `plugin/src/Caelestia/Services/lyrics.cpp` does handle multiple timestamps correctly, but also ignores `[offset:]`.
6. **Offset is split across two systems (static).** The overlay has its own `userOffset` (line 46), reset to 0 on every track change (line 76) and with no control anywhere. The C++ `Lyrics` service has a persisted per-track `offset`, shown in `modules/dashboard/media/LyricsInfo.qml`, but the overlay prefers BetterLyrics, which ignores it. Also, `Lyrics.offset` is in seconds (`time - m_offset`) while the label reads `"Offset: %1 ms"`; check the unit.
7. **Two pipelines, two answers (static).** The dashboard media tab (`LyricList.qml`) uses the C++ `Lyrics` service; the desktop overlay prefers `BetterLyrics`. The same song can show different lyrics and timing in the two places.
8. **Instrumental detection by substring (tested offline).** `isInstrumental()` in `DesktopLyrics.qml` (and the same list in `ai_lyrics.py`) returns true for "Don't break my heart", "Breakfast at Tiffany's", "Let me introduce myself" and "I'm going solo tonight". Those real lyric lines are replaced with dancing notes. LRCLIB returns an explicit `instrumental` boolean per record; use that, and treat only exact marker lines (`♪`, empty) as gaps.
9. **Instrumental gaps behave differently per source (static).** The BetterLyrics path drops empty lines, so a long instrumental break keeps showing the previous line. The C++ path keeps empty lines, so gaps show dancing notes.
10. **Word timing is estimated, and not displayed anyway (static).** `ai_lyrics.py` spreads words evenly across the line (`step = real_span / len(words)`, around line 388). The overlay never reads `words`. Real word timing exists in TTML (BetterLyrics) and in LRCLIB records where `hasWordSync` is true ([LRCLIB API docs](https://lrclib.net/docs)). Only show word highlighting when the source has real word timing.
11. **Position sampling (static).** Quickshell documents that `position` does not update reactively but reading it returns the current value, and suggests a `FrameAnimation` or `Timer` while playing ([MprisPlayer docs](https://quickshell.org/docs/v0.2.1/types/Quickshell.Services.Mpris/MprisPlayer/)). The overlay polls every 200 ms, so a line can change up to 200 ms late. The C++ path adds a 0.1 s lead (`k_indexFudge`), BetterLyrics adds none, so the two sources feel different.
12. **Player choice (static).** `Players.active` is the configured default player or `list[0]`, not the one that is playing. With a paused browser tab and a playing music app, the overlay can follow the wrong one. Both overlay and visualiser share this.
13. **Committed symlink (static).** `scripts/lyrics_fetch.py` points to `/home/mohssine/.config/...`, which breaks in any other checkout.

### Fix order and acceptance tests

1. **Remove invented content.** Drop Gemini lyric and timing generation. No lyrics found means the overlay hides (or shows a short "No synced lyrics" once, then hides). Plain lyrics may appear in the dashboard media tab, unsynced, never with fake timing. Test: a track with no LRCLIB record shows no overlay and makes no Gemini request.
2. **Cancel stale work.** Capture the serial when `aiProc` (or any fetch) starts and stop the process in `setTrack()`. Test: skip during a slow fetch; the new song never receives the old song's lines.
3. **One lyrics source of truth.** Make the overlay and the media tab read one service (extend the C++ `Lyrics` service with the BetterLyrics TTML source, or the reverse). Test: overlay and media tab show the same line at the same position.
4. **Exact match first.** `/api/get` with title, artist, album and duration; then `/api/search` limited to ±2 s and the same version label; otherwise nothing. Keep labels like live, acoustic, remix. Test: "Song (Live Acoustic Video)" never picks the studio version.
5. **Parser.** Multiple timestamps, `[offset:]`, keep empty lines as gap markers, store times in milliseconds. Tests: the samples above, plus `[mm:ss]`, `[mm:ss.xxx]` and a file with an offset tag.
6. **One persisted offset.** Use the existing per-track `Lyrics.offset`, add earlier and later controls (for example 100 ms steps) and a reset, and define the sign in one place. Note that the LRC `[offset:]` tag convention is community-defined rather than standardised; pick one sign for the user control and document it. Test: set +300 ms, change track and come back; the offset is still +300 ms.
7. **Timing loop.** Drive line changes from a `FrameAnimation` while playing, or schedule a single-shot timer for the next line start, and use the same lead in every source. Test: on a known LRC, the highlighted line changes within 50 ms of its timestamp (measure with a debug log of position against index).
8. **Player choice.** Prefer the player that is Playing; fall back to default or first. Test: paused Firefox plus playing Spotify follows Spotify.
9. **Instrumental and end handling.** Use the `instrumental` flag and real gap markers. Test: the four lyric lines above stay as text.
10. **Remove the symlink** and reference the script by repo path.

## 3. Lyrics overlay visuals: colour, alignment and motion

Your colours come from the Material palette (`Colours.palette`): active line `m3primary` Bold 25 px (30 px Arabic), previous and next `m3onSurfaceVariant` Medium 16 px (20 px Arabic) at opacity 0.55, dancing notes `m3primary`, and one drop shadow on the whole layer. The visualiser uses `m3primary` and `m3inversePrimary` at 0.7 alpha. That is a coherent palette, so the suggestions keep it and change hierarchy and layout.

### Findings

1. **Height and position jump (static).** The column is `anchors.centerIn` in a fixed `implicitHeight: 120` item, and the previous and next rows use `visible: text.length > 0`. On the first and last lines, and whenever the active line wraps from one to two lines, the whole block re-centres and moves. The instrumental row is a fixed 38 px, a different height from a text row, so switching to notes also jumps.
2. **Arabic can overflow (estimate, needs live check).** Two-line Arabic active text at 30 px with line height 1.4 is about 84 px, plus two 20 px side lines and spacing, roughly 140 to 150 px in a 120 px box with `clip: false`. It would spill above and below and eat into the 32 px bottom margin.
3. **Size changes per line (static).** `isArabic(text)` is evaluated per line, so a song mixing Darija in Arabic and Latin script switches between 25 and 30 px on each line.
4. **Declared animations never run (static).** The `Behavior on opacity` of the side lines and `Behavior on color` of the active line watch values that never change (0.55 and `m3primary`), so line changes are instant swaps. Only the whole-overlay fade works.
5. **Off-centre relative to the visualiser (static, needs live check for size).** The overlay is centred on the full screen (`Background.qml` line 172), while the visualiser starts after the bar's exclusive zone (`Visualiser.qml` line 65). With your side bar, the lyrics sit about half a bar width left of the bars' centre.
6. **Side-line legibility (needs live check).** `m3onSurfaceVariant` at 0.55 opacity over an arbitrary wallpaper is the most likely readability failure. As a yardstick, WCAG 1.4.3 asks 4.5:1 for normal text and 3:1 for large text (24 px, or about 18.5 px bold) ([WCAG Understanding 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)). The active line qualifies as large; the 16 px side lines do not. WCAG is a web guideline; here it is only a measuring stick.
7. **Font family string (needs live check).** `font.family: "Rubik, Noto Kufi Arabic, sans-serif"` is a CSS-style list. Confirm in a screenshot that Arabic actually renders in Noto Kufi; otherwise use the shell's font token for Latin and set the Arabic family explicitly.
8. **Motion settings (static).** `DancingNotes.qml` loops forever with fixed 320 to 340 ms durations and ignores `Tokens.anim.durations.scale`, which other components respect. If you set animations to 0, the notes keep dancing.

### High-impact tweaks that keep your look

1. **Fixed slots.** Keep three rows always in the layout (empty rows at opacity 0, not `visible: false`), give the active row a fixed two-line height and the notes the same height, and anchor the column to the bottom instead of the centre. Size the item from its content instead of 120. Test: stepping through a whole song, the active line's baseline never moves when there is no wrap change.
2. **One size per track.** Decide Arabic or Latin sizing once per track (majority script), or use one size with a fixed Arabic scale. Test: a mixed-script song keeps the same row heights.
3. **Real line transition.** On index change, cross-fade the old and new lines (about 150 to 250 ms, scaled by `Tokens.anim.durations.scale`) with a small upward move; skip the move when the scale is 0.
4. **Stronger side lines, same colours.** Raise side-line opacity to about 0.7, or keep 0.55 and add a soft `m3surface` backdrop at low alpha behind the block, only if screenshots show low contrast on your wallpapers. Keep `m3primary` for the active line.
5. **Align with the bars.** Offset the overlay's centre by half the bar exclusive zone, as the visualiser does, and keep a clear gap between text and bar tops.
6. **Respect motion settings** in `DancingNotes.qml`: a static note when the scale is 0.

## 4. Dashboard tab (top popout with calendar)

The top popout is the dashboard drawer (`modules/drawers/Panels.qml` holds it; content in `modules/dashboard/Content.qml` and `Tabs.qml`). Its first tab is `modules/dashboard/Dash.qml`: weather card (`dash/SmallWeather.qml`) and user card (`dash/User.qml`) on the top row, calendar (`dash/Calendar.qml`, redesigned in `1431fe6c`) spanning the bottom row.

### Findings (static unless marked)

1. **Magic numbers break the 4 px rhythm.** The theme's spacing, padding and rounding tokens are a clean 4, 8, 12, 16, 20, 28 scale (`plugin/src/Caelestia/Config/tokens.hpp`). `Calendar.qml` mixes in raw values: grid `spacing: 3`, day cell `+ 4` and `- 4`, agenda rows `+ 12` and `+ 10`, `width: agendaView.width - 10`, time field `66`, add button `padding: 2`, fade `18`, today indicator `- 1`. `Tabs.qml` uses `topMargin: 5`. These odd values are the usual source of "slightly off" alignment.
2. **Fixed sizes.** `Calendar.qml` sets `implicitHeight: 360` and a 330 px month column; `Dash.qml` overrides the token widths with `Math.max(token, 350)` and `Math.max(token, 450)` (tokens are 275 and 340). Sizes now live in two places, and the fixed height either clips the agenda or leaves empty space depending on the month (needs live check).
3. **Mixed button sizes in one row.** In the agenda header, close and add use `padding: extraSmall` while sync uses `padding: small`; the month arrows use `small`. Icons in one row end up different sizes and centres.
4. **Colour roles overlap.** `m3tertiary` marks weekends, event dots and event bars. `m3primary` marks the month title, the today shape and the agenda headings. Selection is `m3primaryContainer` at 0.7 opacity. So "weekend" and "has events" look the same, and three primary elements compete for attention.
5. **Inconsistent radii.** The weather card uses `rounding.extraLarge * 1.5` (42 px); the user and calendar cards use `extraLarge` (28 px).
6. **One widget styled differently.** The quick-add box is the only element with a 1 px `m3outlineVariant` border on `m3surfaceContainerHigh`; everything else is a borderless tonal surface.
7. **User card colour load.** `User.qml` uses `m3primaryContainer`, `m3tertiaryContainer` and `m3secondaryContainer` (three separate elements), plus several negative margins (`-padding.extraLargeIncreased`, `-padding.medium`, `-padding.small`) to pull pieces into place. That is four tonal families in one card (screenshot needed to judge how busy it reads).
8. **Code hygiene.** `Calendar.qml` indentation does not match its real nesting (for example the sync button is written at a shallower indent than its parent row). The structure is correct, but this makes later layout edits risky; run `qmlformat` before the visual changes.

### Prioritised tweaks

1. **Snap to tokens** in `Calendar.qml` and `Tabs.qml`: 3 to `spacing.extraSmall`, 10 and 12 to `padding.small` or `padding.medium`, 66 to a width derived from the field's text, 18 to `spacing.large`. Test: every gap in a screenshot measures a multiple of 4 px.
2. **One icon button size per row** (pick `padding.small` everywhere in the calendar header and agenda header). Test: icon centres in a row share one y value.
3. **Clarify colour roles, same palette:** `m3primary` only for "now" (today and the month title); agenda headings in `m3onSurfaceVariant` or `m3secondary`; weekends as a quieter `m3onSurfaceVariant` tint; `m3tertiary` reserved for events; selection as a full `m3secondaryContainer` (or an outline ring) so it never looks like today.
4. **Unify radii** on `Dash.qml` cards (use `rounding.extraLarge` for all three).
5. **Restyle quick-add** as a borderless `m3surfaceContainerHigh` field with `rounding.medium`, matching other inputs.
6. **Move sizes into tokens:** put the 350 and 450 widths and the 330 month column in `DashboardTokens`, and derive the calendar height from the grid plus header.
7. **Calm the user card:** use one container role for the small chips (for example all `m3secondaryContainer`) and replace negative margins with layout spacing.

## 5. What needs a live check

- Overlay contrast on your actual wallpapers (take screenshots on a light and a dark wallpaper and measure text against the area behind it).
- Arabic overflow and font fallback.
- Lyrics and visualiser centre offset with your bar width.
- Calendar height with a six-week month and a long agenda.
- Whether today, selection and event dots read as distinct at normal viewing distance.
- Behaviour with real players: Spotify, a browser tab, mpv, and `playerctl stop`.

## 6. Suggested commit sequence (later, each with its tests)

1. Visibility policy (section 1).
2. Stale request cancellation and removal of invented lyrics.
3. Single lyrics service and exact matching.
4. Parser and persisted offset.
5. Overlay layout slots, transitions and motion settings.
6. Dashboard token cleanup, colour roles, radii.

## Sources

- [LRCLIB API documentation](https://lrclib.net/docs): `/api/get` duration matching (±2 s), `instrumental`, `hasWordSync`, `User-Agent` requirement, rate limits.
- [Quickshell MprisPlayer](https://quickshell.org/docs/v0.2.1/types/Quickshell.Services.Mpris/MprisPlayer/): `isPlaying`, `playbackState`, position polling guidance, track-change signals.
- [WCAG 2.2 Understanding 1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html): contrast thresholds used as a yardstick.
