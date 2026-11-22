"""Small, bounded context helpers for the compact Notes view."""

import hashlib
import json
import re
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen


KUBERNETES_SECTIONS = ["Overview", "Pods", "Deployments", "Services", "Images", "Inspect & debug"]
KUBERNETES_ALIASES = {
    "core concepts": "Overview", "core kubernetes": "Images",
    "cluster inspection": "Inspect & debug", "debugging & logs": "Inspect & debug",
    "cli & operations": "Inspect & debug", "declarative deployments": "Deployments",
    "resource management": "Deployments", "networking & exposure": "Services",
    "workloads & traffic": "Services",
}
DOC_ROOT = "https://kubernetes.io/docs/"
KUBERNETES_DOCS = {
    "Overview": ["concepts/overview/", "concepts/overview/components/"],
    "Pods": ["concepts/workloads/pods/", "concepts/overview/working-with-objects/labels/"],
    "Deployments": ["concepts/workloads/controllers/deployment/", "concepts/overview/working-with-objects/object-management/"],
    "Services": ["concepts/services-networking/service/"],
    "Images": ["concepts/containers/images/"],
    "Inspect & debug": ["tasks/debug/debug-application/debug-running-pod/", "tasks/access-application-cluster/configure-access-multiple-clusters/"],
}


def canonical_kubernetes_section(value):
    text = str(value or "").strip()
    return next((s for s in KUBERNETES_SECTIONS if s.casefold() == text.casefold()),
                KUBERNETES_ALIASES.get(text.casefold(), text))


def content_revision(note):
    # Status retries and read markers are not content changes.
    fields = ("title", "topic", "subconcept", "technical_type", "topic_section",
              "raw_content", "essentials", "completions", "exact_excerpts", "diagrams", "display_edits")
    data = {key: note.get(key) for key in fields}
    if note.get("hidden_entries"):
        data["hidden_entries"] = note["hidden_entries"]
    if not note.get("essentials") and not note.get("exact_excerpts"):
        data["formatted_content"] = note.get("formatted_content")
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def note_inventory(note):
    edits = note.get("display_edits") or {}
    hidden = set(note.get("hidden_entries") or [])
    facts = []
    for field, prefix in (("essentials", "essential"), ("completions", "completion")):
        for i, text in enumerate(note.get(field) or []):
            key = f"{prefix}:{i}"
            if key in hidden:
                continue
            facts.append({"key": key, "text": str(edits.get(key, text))})
    excerpts = []
    for i, excerpt in enumerate(note.get("exact_excerpts") or []):
        command = note.get("technical_type") == "command"
        lines = str(excerpt.get("content") or "").splitlines() if command else [excerpt.get("content") or ""]
        for j, line in enumerate(lines):
            if not line.strip():
                continue
            key = f"command:{i}:{j}"
            if key in hidden:
                continue
            excerpts.append({"key": key, "content": str(edits.get(key, line)),
                             "kind": "command" if command else "code", "language": excerpt.get("language", "")})
    if not facts and not excerpts and "fallback" not in hidden and not (note.get("essentials") or note.get("exact_excerpts")):
        facts.append({"key": "fallback", "text": str(edits.get("fallback") or note.get("formatted_content") or note.get("raw_content") or "")})
    content = "\n".join([f["text"] for f in facts] + [e["content"] for e in excerpts])
    return {"id": note["id"], "title": note.get("title", ""), "subconcept": note.get("subconcept", ""),
            "revision": content_revision(note), "facts": facts, "excerpts": excerpts, "content": content}


class _ArticleText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.depth = 0
        self.parts = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if not self.depth:
            if "td-content" in dict(attrs).get("class", "").split():
                self.depth = 1
        elif tag not in {"br", "hr", "img", "input", "meta", "link", "wbr", "source"}:
            self.depth += 1
        if self.depth and tag in {"script", "style", "nav"}:
            self.skip += 1
        if self.depth and tag in {"p", "li", "h1", "h2", "h3", "h4", "pre", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if self.skip and tag in {"script", "style", "nav"}:
            self.skip -= 1
        if self.depth and tag not in {"br", "hr", "img", "input", "meta", "link", "wbr", "source"}:
            self.depth -= 1

    def handle_data(self, text):
        if self.depth and not self.skip:
            self.parts.append(text)


def topic_references(topic, subsection, cache_dir):
    if str(topic).casefold() not in {"kubernetes", "k8s"}:
        return []
    # Only fixed official URLs are fetched. Model-provided URLs are never fetched.
    paths = KUBERNETES_DOCS.get(canonical_kubernetes_section(subsection), KUBERNETES_DOCS["Overview"])
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    result = []
    for path in paths:
        url = DOC_ROOT + path
        cache = cache_dir / (hashlib.sha256(url.encode()).hexdigest() + ".json")
        try:
            saved = json.loads(cache.read_text()) if cache.exists() else {}
            if time.time() - saved.get("fetched_at", 0) < 86400 and saved.get("text"):
                result.append({"url": url, "text": saved["text"]})
                continue
            request = Request(url, headers={"User-Agent": "Caelestia-Notes/1.0"})
            with urlopen(request, timeout=12) as response:
                if not response.url.startswith(DOC_ROOT):
                    continue
                html = response.read(2000000).decode("utf-8", errors="replace")
            parser = _ArticleText()
            parser.feed(html)
            article = re.sub(r"[ \t]+", " ", "".join(parser.parts))
            article = re.sub(r"\n\s*\n+", "\n", article).strip()[:14000]
            if len(article) < 200:
                continue
            cache.write_text(json.dumps({"text": article, "fetched_at": time.time()}))
            cache.chmod(0o600)
            result.append({"url": url, "text": article})
        except (OSError, ValueError):
            continue
    if not result:
        raise ValueError("Kubernetes documentation could not be loaded. Try Fill gaps again when connected.")
    return result
