import QtQuick
import QtTest

// Exercises services/BetterLyrics.qml with stub Quickshell modules (tests/qml/stubs).
// run_qml_tests.sh copies the service without its "pragma Singleton" line so it can be created
// here. The checks are synchronous, so no network reply can arrive while they run.
TestCase {
    id: tc

    name: "BetterLyrics"

    property var svc: null

    function init() {
        const c = Qt.createComponent(Qt.resolvedUrl("generated/services/BetterLyricsUnderTest.qml"));
        verify(c.status === Component.Ready, c.errorString());
        svc = c.createObject(tc);
        verify(svc !== null);
    }

    function cleanup() {
        if (svc) {
            svc.clearTrack();
            svc.destroy();
        }
        svc = null;
    }

    function syncedState(text) {
        return {
            status: "synced",
            lines: [
                {
                    time: 1,
                    text: text
                }
            ],
            plain: "",
            source: "test",
            approximate: false,
            match: null
        };
    }

    function test_staleResultIsDroppedAndNotCached() {
        svc.setTrack("Artist A", "Song A", "", 200);
        compare(svc.status, "loading");
        const serialA = svc.requestSerial;
        const keyA = svc.trackKey;

        svc.setTrack("Artist B", "Song B", "", 180);
        verify(svc.requestSerial !== serialA);

        // A's answer arrives late.
        svc.finish(serialA, syncedState("A's line"));
        verify(svc.applyTimed(serialA, [
            {
                time: 2,
                text: "A's other line"
            }
        ], "test"));
        compare(svc.status, "loading");
        compare(svc.lines.length, 0);
        verify(svc.cache[keyA] === undefined, "stale result must not be cached under A");
        verify(svc.cache[svc.trackKey] === undefined, "stale result must not be cached under B");

        // B's own answer is applied and cached under B.
        svc.finish(svc.requestSerial, syncedState("B's line"));
        compare(svc.status, "synced");
        compare(svc.lines[0].text, "B's line");
        verify(svc.cache[svc.trackKey] !== undefined);
    }

    function test_clearTrackInvalidatesPending() {
        svc.setTrack("Artist", "Song", "", 200);
        const serial = svc.requestSerial;
        svc.clearTrack();
        svc.finish(serial, syncedState("late"));
        compare(svc.status, "idle");
        compare(svc.lines.length, 0);
    }

    function test_plainResultHasNoTiming() {
        svc.setTrack("Artist", "Song", "", 200);
        svc.finish(svc.requestSerial, {
            status: "plain",
            lines: [],
            plain: "one\ntwo",
            source: "LRCLIB (not synced)"
        });
        compare(svc.status, "plain");
        compare(svc.lines.length, 0);
        verify(!svc.hasLyrics);
        compare(svc.plainText, "one\ntwo");
    }

    function test_missIsNotCached() {
        svc.setTrack("Artist", "Song", "", 200);
        svc.finish(svc.requestSerial, {
            status: "none",
            reason: "no matching recording"
        });
        compare(svc.status, "none");
        verify(svc.cache[svc.trackKey] === undefined);
    }

    function test_cachedTrackIsRestored() {
        svc.setTrack("Artist", "Song", "", 200);
        svc.finish(svc.requestSerial, syncedState("hello"));
        svc.setTrack("Other", "Track", "", 100);
        svc.setTrack("Artist", "Song", "", 200);
        compare(svc.status, "synced");
        compare(svc.lines[0].text, "hello");
    }

    function test_markersBecomeGapsAndOnlyMarkersFallThrough() {
        svc.setTrack("Artist", "Song", "", 200);
        // Nothing sung: the chain must go on to the next source.
        verify(!svc.applyTimed(svc.requestSerial, [
            {
                time: 1,
                text: "[Instrumental]"
            },
            {
                time: 5,
                text: "\u266A"
            }
        ], "test"));
        compare(svc.status, "loading");
        verify(svc.applyTimed(svc.requestSerial, [
            {
                time: 1,
                text: "Don't break my heart"
            },
            {
                time: 5,
                text: "[Instrumental]"
            },
            {
                time: 9,
                text: "Let me introduce myself"
            }
        ], "test"));
        compare(svc.texts, ["Don't break my heart", "", "Let me introduce myself"]);
    }

    function test_parseTtml() {
        const ttml = '<tt><body><div>' + '<p begin="00:00:01.000" end="00:00:03.000"><span>Hello</span> <span>there</span></p>' + '<p begin="00:00:10.000" end="00:00:12.000">Again</p>' + '</div></body></tt>';
        const lines = svc.parseTtml(ttml);
        compare(lines.length, 2);
        compare(lines[0].time, 1);
        compare(lines[0].end, 3);
        compare(lines[1].text, "Again");
    }

    function test_parseQrcAndLrcRows() {
        const qrc = '<QrcInfos><LyricInfo><Lyric_1 LyricType="1" LyricContent="[1000,2000]Hel(1000,500)lo(1500,500)\n[5000,1000]World(5000,1000)"/></LyricInfo></QrcInfos>';
        const lines = svc.parseQrc(qrc);
        compare(lines.length, 2);
        compare(lines[0].text, "Hello");
        compare(lines[0].end, 3);
        const lrc = svc.parseQrc("[00:01.00][00:20.00]Twice");
        compare(lrc.length, 2);
        compare(lrc[1].time, 20);
        compare(lrc[1].text, "Twice");
    }
}
