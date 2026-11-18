#!/usr/bin/env bash
# Runs the QML tests in tests/qml with Qt's qmltestrunner, offscreen.
# BetterLyrics.qml is copied without "pragma Singleton" so a test can create it, and the real
# Quickshell modules are replaced by the small stubs in tests/qml/stubs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
runner="${QMLTESTRUNNER:-$(command -v qmltestrunner || command -v qmltestrunner6 || echo /usr/lib/qt6/bin/qmltestrunner)}"

gen="$root/tests/qml/generated"
rm -rf "$gen"
mkdir -p "$gen/services" "$gen/utils/scripts"
cp "$root/utils/scripts/lyrics.js" "$gen/utils/scripts/lyrics.js"
grep -v '^pragma Singleton' "$root/services/BetterLyrics.qml" > "$gen/services/BetterLyricsUnderTest.qml"
trap 'rm -rf "$gen"' EXIT

QT_QPA_PLATFORM=offscreen "$runner" -import "$root/tests/qml/stubs" -input "$root/tests/qml" "$@"
