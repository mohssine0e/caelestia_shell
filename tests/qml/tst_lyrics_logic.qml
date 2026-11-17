import QtQuick
import QtTest
import "../../utils/scripts/lyrics.js" as Logic

// Loads utils/scripts/lyrics.js in Qt's own JavaScript engine (the one the shell uses), so the
// helpers are checked there and not only under node.
// Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
TestCase {
    name: "LyricsLogic"

    function test_parseLrcMultipleTimestampsAndOffset() {
        const r = Logic.parseLrc("[offset:+500]\n[00:12.00][01:30.50]Chorus\n[00:20.00]Verse");
        compare(r.offsetMs, 500);
        compare(r.lines.length, 3);
        compare(r.lines[0].time, 11.5);
        compare(r.lines[0].text, "Chorus");
        compare(r.lines[2].time, 90);
        compare(r.lines[2].text, "Chorus");
    }

    function test_instrumentalMarkers() {
        verify(!Logic.isInstrumentalMarker("Don't break my heart"));
        verify(!Logic.isInstrumentalMarker("Let me introduce myself"));
        verify(Logic.isInstrumentalMarker("[Instrumental]"));
        verify(Logic.isInstrumentalMarker("\u266A \u266A"));
        verify(Logic.isInstrumentalMarker("(Guitar Solo)"));
    }

    function test_indexAndOffset() {
        const lines = [
            {
                time: 5,
                text: "a"
            },
            {
                time: 10,
                text: "b"
            }
        ];
        compare(Logic.indexForTime(lines, 4.95, 0), 0);
        compare(Logic.indexForTime(lines, 5.5, 1), -1);
        compare(Logic.timeForIndex(lines, 1, 0.5), 10.5);
    }

    function test_overlayState() {
        const base = {
            hasPlayer: true,
            covered: false,
            playback: "playing",
            status: "synced",
            lines: [
                {
                    time: 1,
                    text: "a"
                }
            ],
            index: 0
        };
        compare(Logic.overlayState(base).mode, "lyrics");
        compare(Logic.overlayState(Object.assign({}, base, {
            playback: "stopped"
        })).mode, "hidden");
        compare(Logic.overlayState(Object.assign({}, base, {
            playback: "paused",
            pauseGrace: true
        })).mode, "lyrics");
        compare(Logic.overlayState(Object.assign({}, base, {
            playback: "paused",
            pauseGrace: false
        })).mode, "hidden");
        compare(Logic.overlayState(Object.assign({}, base, {
            status: "loading",
            loadingDelayPassed: true,
            playback: "paused",
            pauseGrace: true
        })).mode, "hidden");
    }

    function test_arabic() {
        verify(Logic.isMostlyArabic([
            {
                text: "\u062d\u0628\u064a\u0628\u064a"
            }
        ]));
        compare(Logic.parseLrc("[00:01.00]\u0645\u0634\u064a\u062a").lines[0].text, "\u0645\u0634\u064a\u062a");
    }
}
