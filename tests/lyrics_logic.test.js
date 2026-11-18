// Unit tests for utils/scripts/lyrics.js. Run with: node tests/lyrics_logic.test.js
// The file is a QML ".pragma library" script, so the pragma line is stripped before loading.
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "utils", "scripts", "lyrics.js"), "utf8").replace(/^\.pragma library\s*$/m, "");
const names = ["LEAD_SECONDS", "GAP_MIN_SECONDS", "isInstrumentalMarker", "isArabic", "isMostlyArabic", "parseTime", "parseLrc", "normalizeLines", "hasVocalLines", "indexForTime", "timeForIndex", "msUntilNextLine", "rowsForIndex", "overlayState"];
const L = new Function(src + "\nreturn {" + names.join(",") + "};")();

let passed = 0;
const failures = [];
function test(name, fn) {
    try {
        fn();
        passed++;
    } catch (e) {
        failures.push(name + ": " + e.message);
    }
}
const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) <= eps, `${a} != ${b}`);

// --- LRC parser -----------------------------------------------------------------------------

test("parseLrc: basic lines sorted by time", () => {
    const r = L.parseLrc("[00:10.50]Second\n[00:01.00]First");
    assert.deepStrictEqual(r.lines.map(l => l.text), ["First", "Second"]);
    near(r.lines[1].time, 10.5);
});

test("parseLrc: several timestamps on one line give one entry each, text clean", () => {
    const r = L.parseLrc("[00:12.00][01:30.50]Chorus line\n[00:20.00]Verse");
    assert.deepStrictEqual(r.lines.map(l => [l.time, l.text]), [[12, "Chorus line"], [20, "Verse"], [90.5, "Chorus line"]]);
    assert.ok(!r.lines.some(l => l.text.includes("[")), "no timestamp left in text");
});

test("parseLrc: [mm:ss], [mm:ss.x], [mm:ss.xxx] and [mm:ss:xx] forms", () => {
    const r = L.parseLrc("[00:01]a\n[00:02.5]b\n[00:03.250]c\n[00:04:50]d");
    assert.deepStrictEqual(r.lines.map(l => l.time), [1, 2.5, 3.25, 4.5]);
});

test("parseLrc: metadata tags ignored", () => {
    const r = L.parseLrc("[ar:Artist]\n[ti:Title]\n[length:03:20]\n[00:05.00]Hello");
    assert.deepStrictEqual(r.lines.map(l => l.text), ["Hello"]);
});

test("parseLrc: positive [offset:] shows lyrics earlier", () => {
    const r = L.parseLrc("[offset:+500]\n[00:10.00]Line");
    assert.strictEqual(r.offsetMs, 500);
    near(r.lines[0].time, 9.5);
});

test("parseLrc: negative [offset:] shows lyrics later, times never below 0", () => {
    const r = L.parseLrc("[offset:-250]\n[00:10.00]Line");
    near(r.lines[0].time, 10.25);
    const r2 = L.parseLrc("[offset:2000]\n[00:01.00]Early");
    near(r2.lines[0].time, 0);
});

test("parseLrc: empty timed lines kept as gaps", () => {
    const r = L.parseLrc("[00:01.00]Sing\n[00:30.00]\n[00:45.00]Again");
    assert.deepStrictEqual(r.lines.map(l => l.text), ["Sing", "", "Again"]);
});

test("parseLrc: word-level <mm:ss.xx> tags stripped", () => {
    const r = L.parseLrc("[00:01.00]<00:01.00>Hello <00:01.50>world");
    assert.strictEqual(r.lines[0].text, "Hello world");
});

test("parseLrc: Arabic text preserved", () => {
    const r = L.parseLrc("[00:03.00]\u0645\u0634\u064a\u062a \u0628\u0639\u064a\u062f");
    assert.strictEqual(r.lines[0].text, "\u0645\u0634\u064a\u062a \u0628\u0639\u064a\u062f");
});

// --- Instrumental detection -----------------------------------------------------------------

test("instrumental: normal lyrics with marker words inside stay lyrics", () => {
    for (const line of ["Don't break my heart", "Let me introduce myself", "Solo dancing tonight", "The music of the night", "Breakfast at Tiffany's", "Outrageous"])
        assert.strictEqual(L.isInstrumentalMarker(line), false, line);
});

test("instrumental: whole-line markers detected", () => {
    for (const line of ["", "   ", "\u266A", "\u266A \u266A \u266A", "\u266B", "...", ". . .", "\u2026", "[Instrumental]", "(instrumental)", "Instrumental", "[Guitar Solo]", "(Intro)", "[Outro]", "\u266A Instrumental \u266A", "(Instrumental Break)"])
        assert.strictEqual(L.isInstrumentalMarker(line), true, JSON.stringify(line));
});

// --- normalizeLines -------------------------------------------------------------------------

test("normalizeLines: markers become gaps, repeated gaps merged, leading gap dropped", () => {
    const out = L.normalizeLines([{ time: 0, text: "\u266A" }, { time: 5, text: "One" }, { time: 10, text: "[Instrumental]" }, { time: 12, text: "" }, { time: 20, text: "Two" }]);
    assert.deepStrictEqual(out.map(l => [l.time, l.text]), [[5, "One"], [10, ""], [20, "Two"]]);
});

test("normalizeLines: end times create gaps for long silences only", () => {
    const out = L.normalizeLines([{ time: 1, end: 3, text: "A" }, { time: 4, end: 6, text: "B" }, { time: 20, end: 22, text: "C" }], 40);
    assert.deepStrictEqual(out.map(l => [l.time, l.text]), [[1, "A"], [4, "B"], [6, ""], [20, "C"], [22, ""]]);
});

test("normalizeLines: no trailing gap when the track ends right after the last line", () => {
    const out = L.normalizeLines([{ time: 1, end: 3, text: "A" }], 5);
    assert.deepStrictEqual(out.map(l => l.text), ["A"]);
});

test("hasVocalLines", () => {
    assert.strictEqual(L.hasVocalLines([{ time: 1, text: "" }]), false);
    assert.strictEqual(L.hasVocalLines([{ time: 1, text: "x" }]), true);
});

// --- Timing and offset ----------------------------------------------------------------------

const lines = [{ time: 5, text: "a" }, { time: 10, text: "b" }, { time: 15, text: "c" }];

test("indexForTime: before first line is -1; lead of 100 ms", () => {
    assert.strictEqual(L.indexForTime(lines, 0, 0), -1);
    assert.strictEqual(L.indexForTime(lines, 4.85, 0), -1);
    assert.strictEqual(L.indexForTime(lines, 4.95, 0), 0);
    assert.strictEqual(L.indexForTime(lines, 12, 0), 1);
    assert.strictEqual(L.indexForTime(lines, 100, 0), 2);
});

test("indexForTime: positive offset delays lyrics", () => {
    assert.strictEqual(L.indexForTime(lines, 5.5, 1.0), -1);
    assert.strictEqual(L.indexForTime(lines, 6.0, 1.0), 0);
    assert.strictEqual(L.indexForTime(lines, 5.0, -1.0), 1 - 1 + 0); // 5 + 1 + 0.1 = 6.1 -> line 0
    assert.strictEqual(L.indexForTime(lines, 9.0, -1.0), 1);
});

test("indexForTime: seeking backwards and forwards is stateless", () => {
    assert.strictEqual(L.indexForTime(lines, 14.95, 0), 2);
    assert.strictEqual(L.indexForTime(lines, 6, 0), 0);
    assert.strictEqual(L.indexForTime(lines, 11, 0), 1);
});

test("timeForIndex includes offset and is clamped", () => {
    near(L.timeForIndex(lines, 1, 0.5), 10.5);
    near(L.timeForIndex(lines, 0, -10), 0);
    assert.strictEqual(L.timeForIndex(lines, 7, 0), -1);
});

test("msUntilNextLine respects offset and rate", () => {
    near(L.msUntilNextLine(lines, 9.0, 0, 1), 900, 1e-6);
    near(L.msUntilNextLine(lines, 9.0, 0, 2), 450, 1e-6);
    near(L.msUntilNextLine(lines, 9.0, 0.5, 1), 1400, 1e-6);
    assert.strictEqual(L.msUntilNextLine(lines, 20, 0, 1), -1);
});

test("rowsForIndex: first, middle, last and before start", () => {
    assert.deepStrictEqual(L.rowsForIndex(lines, -1), { previous: "", current: "", next: "a" });
    assert.deepStrictEqual(L.rowsForIndex(lines, 0), { previous: "", current: "a", next: "b" });
    assert.deepStrictEqual(L.rowsForIndex(lines, 2), { previous: "b", current: "c", next: "" });
});

test("isMostlyArabic decides per track", () => {
    assert.strictEqual(L.isMostlyArabic([{ text: "\u062d\u0628\u064a\u0628\u064a" }, { text: "yeah" }]), true);
    assert.strictEqual(L.isMostlyArabic([{ text: "one" }, { text: "two" }, { text: "three" }]), false);
    assert.strictEqual(L.isMostlyArabic([]), false);
});

test("parseTime: TTML forms", () => {
    near(L.parseTime("27.395"), 27.395);
    near(L.parseTime("00:00:27.395"), 27.395);
    near(L.parseTime("1:02.5"), 62.5);
    near(L.parseTime("1250ms"), 1.25);
    near(L.parseTime("12s"), 12);
    assert.ok(isNaN(L.parseTime("")));
});

// --- Overlay visibility ---------------------------------------------------------------------

const synced = { hasPlayer: true, covered: false, playback: "playing", status: "synced", lines, index: 1 };
const mode = s => L.overlayState(Object.assign({}, synced, s)).mode;

test("overlay: playing synced shows lyrics", () => assert.strictEqual(mode({}), "lyrics"));
test("overlay: stop hides immediately", () => assert.strictEqual(mode({ playback: "stopped" }), "hidden"));
test("overlay: pause keeps the line during the grace period, then hides", () => {
    assert.strictEqual(mode({ playback: "paused", pauseGrace: true }), "lyrics");
    assert.strictEqual(mode({ playback: "paused", pauseGrace: false }), "hidden");
});
test("overlay: no player or covered desktop hides", () => {
    assert.strictEqual(mode({ hasPlayer: false }), "hidden");
    assert.strictEqual(mode({ covered: true }), "hidden");
});
test("overlay: loading only while playing and after the delay", () => {
    assert.strictEqual(mode({ status: "loading", loadingDelayPassed: false }), "hidden");
    assert.strictEqual(mode({ status: "loading", loadingDelayPassed: true }), "loading");
    assert.strictEqual(mode({ status: "loading", loadingDelayPassed: true, playback: "paused", pauseGrace: true }), "hidden");
});
test("overlay: gap line shows notes; intro shows notes only when long", () => {
    const g = [{ time: 5, text: "a" }, { time: 10, text: "" }, { time: 20, text: "b" }];
    assert.strictEqual(mode({ lines: g, index: 1 }), "notes");
    assert.strictEqual(mode({ lines: g, index: -1 }), "notes");
    assert.strictEqual(mode({ lines: [{ time: 1, text: "a" }], index: -1 }), "lyrics");
});
test("overlay: plain or missing lyrics show notes without a message", () => {
    assert.strictEqual(mode({ status: "plain" }), "notes");
    assert.strictEqual(mode({ status: "none" }), "notes");
    assert.strictEqual(mode({ status: "none", playback: "paused", pauseGrace: true }), "notes");
});
test("overlay: explicit instrumental track shows notes", () => assert.strictEqual(mode({ status: "instrumental" }), "notes"));
test("overlay: idle hides", () => assert.strictEqual(mode({ status: "idle" }), "hidden"));

console.log(`lyrics_logic: ${passed} passed, ${failures.length} failed`);
if (failures.length) {
    for (const f of failures)
        console.log("FAIL " + f);
    process.exit(1);
}
