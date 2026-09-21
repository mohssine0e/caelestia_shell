// Parse "@minutes" out of a capture/edit string, e.g. "do A @4".
// Shared by DataManager, TaskCard and SubtaskCard so the "is the title
// empty?" check stays consistent with the parsing itself.
.pragma library

function parseCapturePrefix(text) {
    var title = text.trim();
    var minutes = 0;
    var match = title.match(/@(\d+)/);
    if (match) {
        minutes = parseInt(match[1]) || 0;
        var before = title.slice(0, match.index);
        var after = title.slice(match.index + match[0].length);
        title = (before + " " + after).trim();
        title = title.replace(/\s+/g, " ");
    }
    return { title: title, minutes: minutes };
}

// True when the text contains a usable title (i.e. not blank and not
// just an "@minutes" suffix like "@5" or "   @10  ").
function hasTitle(text) {
    return parseCapturePrefix(text).title.length > 0;
}
