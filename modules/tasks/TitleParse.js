// Parse capture/edit prefixes out of a string, e.g.
//   "do A @4 #work !github.com/foo https://x.com"
// Shared by DataManager, TaskCard and SubtaskCard so the "is the title
// empty?" check stays consistent with the parsing itself.
// Returns { title, minutes, category, link }:
//   - @minutes  — existing behaviour.
//   - #category  — first match is the category, every match is stripped from
//                   the title. Must start with a letter so "#42" in
//                   "Fix issue #42" is left alone. Stored lowercased.
//   - !link     — explicit link prefix, mirroring @minutes. The value is the
//                   link and is stripped from the title. If the value has no
//                   scheme, https:// is prepended so a bare domain
//                   ("!github.com/foo") opens in a browser. Only values that
//                   look like a link are honoured (scheme or a dot), so
//                   "Fix the !bug" is left untouched.
//   - bare URL  — a bare https?:// URL is also auto-detected and stripped,
//                   filling in only when no explicit !link was given.
// URLs are stripped before @minutes so a URL's "@digits" can't be mistaken
// for an estimate (e.g. "https://x.com/@42").
.pragma library

function parseCapturePrefix(text) {
    var title = text.trim();
    var minutes = 0;
    var category = "";
    var link = "";

    // Explicit link prefix, mirroring @minutes: "!value" is the link and is
    // stripped from the title. A value without a scheme gets https://
    // prepended so a bare domain ("!github.com/foo") opens in a browser.
    // Only values that look like a link are honoured (scheme or a dot), so
    // "Fix the !bug" is left untouched.
    var bangMatch = title.match(/!(\S+)/);
    if (bangMatch) {
        var raw = bangMatch[1].replace(/[.,;:!?)\]}'"]+$/, "");
        if (raw && (/^https?:\/\//i.test(raw) || /\./.test(raw))) {
            link = /^https?:\/\//i.test(raw) ? raw : "https://" + raw;
            title = title.replace("!" + bangMatch[1], " ");
        }
    }

    // bare URL — fills in only when no explicit link was given. Stripped
    // before @minutes so a URL's "@digits" can't be mistaken for an estimate.
    if (!link) {
        var linkMatches = title.match(/https?:\/\/\S+/g);
        if (linkMatches && linkMatches.length > 0) {
            link = linkMatches[0].replace(/[.,;:!?)\]}'"]+$/, "");
            if (link)
                title = title.replace(/https?:\/\/\S+/g, " ");
        }
    }

    // @minutes — existing behaviour.
    var minutesMatch = title.match(/@(\d+)/);
    if (minutesMatch) {
        minutes = parseInt(minutesMatch[1]) || 0;
        var before = title.slice(0, minutesMatch.index);
        var after = title.slice(minutesMatch.index + minutesMatch[0].length);
        title = (before + " " + after).trim();
    }

    // #category — first match is the category; strip every occurrence so a
    // title can't leak a stray "#tag" token. Must start with a letter.
    var catMatches = title.match(/#[A-Za-z][A-Za-z0-9_-]*/g);
    if (catMatches && catMatches.length > 0) {
        category = catMatches[0].slice(1).toLowerCase();
        title = title.replace(/#[A-Za-z][A-Za-z0-9_-]*/g, " ");
    }

    title = title.replace(/\s+/g, " ").trim();

    return { title: title, minutes: minutes, category: category, link: link };
}

// True when the text contains a usable title (i.e. not blank and not
// just a prefix like "@5", "#work", "!github.com" or a bare URL).
function hasTitle(text) {
    return parseCapturePrefix(text).title.length > 0;
}