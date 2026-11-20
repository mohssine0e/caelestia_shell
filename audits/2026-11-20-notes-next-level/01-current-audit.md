# Current implementation audit

Priority describes implementation order. “Reproduced” means a temporary database with mocked provider responses; production data was not mutated for the test.

## Content and storage: fix first

| Priority | Finding and evidence | Required outcome |
|---|---|---|
| P0 | **Reproduced:** `smart_upsert()` accepts an invalid merge target and falls back to `existing_summary[0]`. [Backend](../../scripts/notes_backend.py) `smart_upsert`, around line 2052. | An unknown/mismatched target must never change another note. Keep the capture and propose an explicit target or create a separate concept. |
| P0 | **Reproduced:** the merge branch changes `formatted_content` and `subconcept`, but leaves `raw_content`, `essentials_json`, and `excerpts_json` unchanged. The main view primarily consumes the latter fields. | Preserve the incoming capture independently, atomically update structured blocks, and retain a reversible revision. Merged additions must appear in the view. |
| P0 | **Reproduced:** sensitive input reaches `_run_provider()` through `smart_upsert()` before `_detect_sensitive_content()` is applied. The guard exists in `triage_note()`, but that happens too late for this entry path. | Save locally and apply the same eligibility gate before every external call, including upsert, triage, generation context, and gap completion. |
| P1 | **Observed in stored Java data:** one long capture becomes one subsection with six essential bullets. `_parse_triage_response()` and `smart_upsert()` cap mechanics at six; `_clean_exact_excerpts()` caps excerpts at eight. | Split a capture into several concept blocks while preserving every original section. Concision belongs to Recall presentation, not destructive extraction limits. |
| P1 | **Reproduced classification error:** `infer_subconcept()` tests Docker `stack` before image/layer rules. Java modern-feature matches similarly outrank memory/concurrency for a mixed capture. | Use structured source sections and stable concept identities; weak keywords can suggest routing, but must not silently reclassify an entire multi-concept document. |
| P1 | **Confirmed in source:** `connect()` invokes `_refactor_subconcepts_internal()` when any live row has an empty subsection; that function rewrites classifications across all rows, including rows outside the trigger. | Make opening/listing read-only after explicit versioned migrations. Normalize only the intended records; keep user-confirmed placement. |
| P1 | **Confirmed in source:** smart-upsert's prompt always describes technical notes and its create branch stores category `technical`. Unlike triage, it lacks a reliable personal/idea preservation path. | One capture policy regardless of save timing or entry point; personal text remains verbatim and separate. |

Passing tests currently cover the expected paths, not these contradictions. New regression cases should be added before fixing each branch.

## AI intelligence and retrieval

1. **“All gaps” cannot discover a missing subsection.** `fill_topic()` builds targets only from the current context and rejects unknown subsection names. It accepts at most six items per response. `_topic_context()` truncates each note to 4,000 characters with a 24,000-character total budget, newest first. An omitted older section may therefore look missing. Track what was actually inspected; distinguish a content gap, an unseen area, and a proposed new subsection.
2. **Repeated generation does not establish completeness.** One extra overview pass may add introductions while omitting important rules or examples. A blank result means no suggestion was returned for the supplied context, not that the subject is mastered or complete.
3. **Link/merge retrieval is recency-limited.** Smart-upsert considers the newest 50 technical/reference records; triage links consider 40. Relevant older material can be excluded. Search by topic, aliases, symbols, and content before presenting a bounded set to AI.
4. **Relations are untyped IDs.** `_save_related_links()` validates and reciprocates IDs, which is useful. It merges links cumulatively and does not explain or distinguish prerequisite, example, alternative, or contradiction. Typed links need directional inverse handling, revision support, and removal of obsolete proposals.
5. **There is no reliable evidence/version layer.** Existing AI-origin rows and source captures are not authoritative verification. Acceptance means “keep this”; it must not mean “fact checked.” Preserve evidence links, applicable tool/runtime versions, and the distinction between a direct capture and generated explanation in the source inspector.
6. **Apparent exactness is uneven.** Triage's excerpt guard accepts normalized similarity or the first ten words, while smart-upsert accepts returned snippet text directly. A familiar opening is not proof the rest matches the source. Track original spans/hashes and store AI corrections separately.

## Window and interaction

The live review screenshot shows a readable themed window, useful topic/subsection strips, and a large content area. Git opens to a long sequence of equally weighted bullets; each claim looks equally important. There is no clear path from “what is this?” to “why?” to “what do I type?”

| Finding | Consequence | Recommendation |
|---|---|---|
| Topic pills move the selected topic to the front; groups also sort by note count/update time. | Positions change while navigating. | Stable order with pinned/recent shortcuts; keep the selected item visible without moving it. |
| Search computes matching groups, but `pillItems` uses all groups and the content remains aggregated. | A search can select a topic without revealing the matching fact. | Show ranked result rows with a matching excerpt and jump to a stable block ID. |
| `navigateToNote()` changes topic/subsection, then scrolls to the top. | “Related” does not reliably locate the referenced material. | Exact concept/block anchor, brief highlight, and Back history. |
| Recency uses a 24-hour timestamp test, not last-seen state. | A dot cannot tell you what you have not read; time does not necessarily cause a reactive reevaluation. | Track changed revision versus last-seen revision at block/concept level. |
| `conciseExplanation()` cuts at 110 characters and removes everything after “along with”. | Details can vanish during rendering/export. | Keep full text; use deliberate summaries plus expansion, never string surgery. |
| `buildKnowledge()` and `buildSubconceptBlocks()` are competing transformations. | Section names, export, links, and displayed content can diverge. | One normalized presentation model for both UI and Markdown export. |
| A Flickable/Column with nested Repeaters eagerly creates the content. | Scaling risk as notes and examples grow; no measured slowdown claimed yet. | Flatten the visible blocks into a ListView, lazy-load expanded details, and measure. |

Relevant files: [NotesView.qml](../../modules/notes/NotesView.qml), [QuickNote.qml](../../modules/notes/QuickNote.qml), [Notes.qml](../../services/Notes.qml), [TopicInline.qml](../../modules/notes/TopicInline.qml).

## Command help needs command context

[FlagCatalog.js](../../modules/notes/FlagCatalog.js) keys help by executable and flag. The same flag can mean different things for different subcommands. For example, `git add -p` selects changes interactively, whereas `git log -p` displays patches. The catalog gives a generic interactive-patch explanation. Use `(tool, subcommand, flag, applicable version)` and an honest unknown state. See the primary [git-add](https://git-scm.com/docs/git-add) and [git-log](https://git-scm.com/docs/git-log) manuals.

`CommandWithFlags.qml` sends window coordinates via `mapToItem(null, ...)`, while `NotesView.qml` calls `mapFromGlobal(...)`. This is a coordinate-space mismatch in code; inspect it during UI work. Long unbroken tokens and related-pill titles also need width bounds. Neither was visually reproduced in this audit.

## Scope limits

No claim that every saved technical statement is wrong or right. The source review found uneven preservation and presentation. Existing `docker run -d` examples lack an image argument; existing snippets also include shell-invalid comment syntax such as `//`. A future system should retain these originals while offering a clearly inspectable correction, instead of presenting every copied string as a ready-to-run command.
