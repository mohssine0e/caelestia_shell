pragma Singleton

import Quickshell
import Caelestia.I18n

Singleton {
    property var _regexCache: ({})

    function percent(value: int): string {
        // TRANSLATORS: %1 = a number
        return Tr.tr("%1%").arg(value);
    }

    function percentOne(value: real): string {
        return percent(Math.round(value * 100));
    }

    function cleanNotifBody(raw: string): string {
        if (!raw)
            return "";
        return String(raw)
            .replace(/^\s*<a\b[^>]*>(?:https?:\/\/)?[a-z0-9.-]+\.[a-z]{2,}(?:\/[^<]*)?<\/a>\s*/i, "")
            .replace(/^\s*(?:https?:\/\/)?(?:web\.)?[a-z0-9.-]+\.[a-z]{2,}(?::\d+)?(?:\/\S*)?\s*\n+\s*/i, "")
            .trim();
    }

    function stripHtml(raw: string): string {
        if (!raw)
            return "";
        return cleanNotifBody(raw)
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/<[^>]*>/g, "")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&#39;/g, "'")
            .replace(/&nbsp;/g, " ")
            .replace(/^(?:https?:\/\/)?(?:web\.)?[a-z0-9.-]+\.[a-z]{2,}(?::\d+)?\s+/i, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function testRegexList(filterList: list<string>, target: string): bool {
        const regexChecker = /^\^.*\$$/;
        for (const filter of filterList) {
            if (regexChecker.test(filter)) {
                let re = _regexCache[filter];
                if (!re) {
                    re = new RegExp(filter);
                    _regexCache[filter] = re;
                }
                if (re.test(target))
                    return true;
            } else {
                if (filter === target)
                    return true;
            }
        }
        return false;
    }
}
