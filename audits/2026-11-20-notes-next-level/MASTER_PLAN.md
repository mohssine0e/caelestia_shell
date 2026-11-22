# Notes upgrade — implementation plan and current status

**Owner:** implementation agent working with Mohssine  
**Created:** 2026-11-20  
**State (2026-11-22):** The familiar Notes review view is active through `NotesView.qml` → `NotesViewLegacy.qml`. Kubernetes is curated into Overview, Pods, Deployments, Services, Images, and Inspect & debug. The practical-depth pass expanded seven explanations and added four commands; 21 notes are now shown across those sections, with all earlier raw captures preserved. Overview now has 21 labeled points covering definitions, components, and the reconciliation path. Three optional, collapsed diagrams illustrate the Overview flow, Deployment ownership, and Service selection. Fill gaps is scoped to the selected subsection, has no application-side suggestion count cap, and checks Kubernetes claims against official documentation excerpts. Ask AI answers questions about the whole selected subsection or topic and stages optional bullets, commands, code, replacements, removals, and diagrams; answers alone do not change notes. Corrections have source-revision validation, transactional acceptance and undo. Refresh reloads local data. Unread dots track semantic revisions. See [06 — Kubernetes stability upgrade](06-kubernetes-stability-upgrade.md), [07 — Kubernetes practical depth](07-kubernetes-practical-depth.md), [08 — Overview and diagrams](08-kubernetes-overview-diagrams.md), and [09 — Ask AI](09-ask-ai.md).

**Next task:** Review another topic's captures and apply the same compact, source-preserving content audit. Exact-block search in the active view and mixed RTL/LTR display remain future work. Keep the selected-subsection layout and do not reintroduce the rejected concept-index screen.

**Primary requirement:** understand deeply now, look up quickly later.

This is the authoritative scope and progress checklist. The other documents in this folder provide audit evidence, examples, and design rationale. Update completion status here as work proceeds.

## 1. What the finished system must do for you

You are a Java backend engineer interested in Linux, DevOps, and cloud. You capture definitions, rules, code, commands, comparisons, and things you do not yet understand. The system must preserve your material, organize it into meaningful concepts, explain those concepts when requested, and make the useful parts easy to retrieve later.

### Your normal workflow

1. Press Super+/, type or paste, and leave. Capture stays quiet and saves locally before AI processing.
2. Open Notes. Find a topic or search for a question, symbol, command, or phrase.
3. Open a topic and area in the familiar review view. Present its essential definition, rules, commands, examples, and caveats in a clear order.
4. Let the user expand into deeper explanations such as why a concept is named that way, how it works, counterexamples, and comparisons. Keep this detail available without crowding the overview.
5. Once comfortable, make quick recall easy: show concise essentials first and let the user reopen the deeper explanation when needed.
6. Use **Fill gaps** for an automatic review of the selected area, or **Ask AI** for a specific question or requested change. Answers stay separate; proposed edits require acceptance.

The result is a personal engineering handbook. It should not require maintaining a folder tree, writing elaborate prompts, or taking a quiz before accessing your own notes.

## 2. Product decisions

| Area | Decision |
|---|---|
| Window | One floating window. Keep the familiar topic/subconcept review layout as the active review view; capture remains a separate mode in the same window. |
| Capture | Empty focused editor, no permanent hints, compact padding, scrolling, local autosave, recoverable draft. |
| Organization | Topic → Area → Concept → Content blocks. Original captures are sources, not the navigation hierarchy. |
| Depth | Understand and Recall read the same stored content. No network request when switching. |
| Default | New concepts open in Understand; remember the user's explicit preference per concept. |
| Content | Short sentences, meaningful structure, full detail retained. No arbitrary six-bullet limit on stored knowledge. |
| AI | Organizes and proposes additions; does not silently replace sources or merge unrelated concepts. |
| Language | Preserve English, French, Arabic, and Darija. Do not translate unless requested. |
| Personal thoughts | Preserve verbatim, separate from technical concept generation. |
| Noise | Skip clear accidental input; uncertain short notes remain recoverable. No permanent “noise concepts.” |
| Controls | Keep common reading/navigation controls visible; occasional maintenance actions in a menu. |
| Trust | Sources and revisions available on demand; no “AI” badge on every line and no constant Edit buttons. |
| Connections | Keep relations and provenance in storage; omit inline related-link pills from the reading surface to protect space. |
| Performance | Local reading/search and lazy rendering. Ask AI sends the entire selected subsection; topic-wide requests send the topic. Large topics depend on the provider's context capacity. |

## 3. Content that supports both learning and recall

### A concept page

Each concept has a stable identity, a short definition, and whichever of these roles are useful:

- **Problem/purpose:** why the concept exists and what it helps solve.
- **Meaning/name:** what the term means; documented naming history when available.
- **Mechanism:** what happens, step by step; a small diagram if it clarifies the process.
- **Rules:** conditions, guarantees, and limits.
- **Example:** code, command, or configuration with prerequisites and expected behavior.
- **Counterexample:** the smallest change that demonstrates a boundary or common misunderstanding.
- **Decision/comparison:** when to use it and why an adjacent alternative may fit another situation.
- **Sources and connections:** evidence, versions, prerequisites, related applications.

These are optional roles, not compulsory empty sections. A simple command and a Java concurrency concept need different depth. The AI must not produce a long textbook explanation for every short capture.

### Understand

Show the definition, problem, mechanism, rules, and example in reading order. Keep secondary history, comparisons, and additional examples expandable. When a prerequisite is unfamiliar, open a focused explanation or navigate to its concept with a Back path. Do not recursively generate every prerequisite.

### Recall

Show the definition, a small set of high-value rules, the main example/command, and indispensable caveats. Store a deliberate summary; never derive it by cutting text at an arbitrary character count. A detail can be hidden, but remains accessible and exportable.

“Recall next time” changes a view preference, not a mastery score. Opening a page repeatedly does not prove that you understand it.

### Active review view behavior

The familiar topic/subconcept view is the active UI. Open on a foundational area and sort advanced areas last; do not include an “All” area. Keep essential bullets and commands visible. Code samples collapse by default and expose a concise language/description row with expand and copy icons. AI completion bullets and links to the area's structured concepts appear in collapsed **Deeper detail**. Opening a concept uses the existing explanation page and its saved Understand/Recall preference and sources. Preserve useful command explanations and merge repeated identical commands without discarding distinct explanations.

### First content pilot

Use a copy of your existing Java capture to demonstrate:

1. Pass-by-value and object references.
2. Equality, hash codes, and collection behavior.
3. Concurrency choices and their conditions.

Preserve the other sections, including CAS, executors, and virtual threads. They must remain reachable even before all concept pages are polished. Use Docker and Git to validate commands, RabbitMQ to validate conceptual relationships, and a personal Darija fixture to validate capture policy.

## 4. The window we will build

```text
┌────────────────────────────────────────────────────────────────┐
│ Java  Git  Docker  RabbitMQ …              Search /          ×  │
│ Memory & References   Collections   Concurrency   All …         │
├────────────────────────────────────────────────────────────────┤
│ ← Pass-by-value                    Understand | Recall     ⋯   │
│ One-sentence definition                                        │
│                                                                │
│ Problem → mechanism → rules → example                          │
│                                                                │
│ ▸ Why this name?   ▸ Counterexample   ▸ Compare                  │
│ Requires: References           Related: Mutation               │
└────────────────────────────────────────────────────────────────┘
```

Keep the established topic strip, subconcept strip, and grouped knowledge sections as the active navigation. Avoid turning the main view into a long list of concept cards. The handbook index/detail components and data model may remain available for continued work, but they are not the default review experience until their information hierarchy is redesigned around the user's preferred workflow.

Remove the persistent generation field from the header. Put topic creation/generation in the add/overflow action. Put Delete, Move, Sources, Reanalyze, and full-page Copy/Export in the menu. Keep copy controls on code and commands. Pending additions show Accept/Dismiss beside the content; Accept all applies only to the visible batch/scope.

The header has a usable drag region. Search and text selection must not initiate dragging. `/` focuses search outside editable fields. Esc dismisses overlays first, then search focus, then the window. Navigation and generation preserve the current reading position.

Search results show topic/area/concept, matching text, and whether the match is a rule, code, command, or source. Opening a result lands on the exact block with a temporary highlight. Preserve Back history.

Code keeps indentation and can scroll horizontally; wrapping is optional and never changes copied bytes. Prose wraps by word. At narrow widths, command explanations stack below syntax. Long titles and tokens must not force controls outside the window.

Unread dots represent **unseen revisions**. They aggregate from changed blocks to concepts and areas. Merely opening a topic does not clear every child's unread status. Reformatting without a meaningful content change should not mark everything new.

## 5. Storage and backend design

Keep SQLite and the current Python/QML process boundary. Avoid adding a server or external database. Share the existing provider credential resolver while keeping Notes prompts, context, jobs, and storage independent from Assistant chat.

The initial schema adds stable concepts, blocks, and source mappings alongside existing note IDs. Subsequent migrations add typed relationships and reading state. Each entity needs:

| Entity | Required information |
|---|---|
| Capture revision | Exact source text, origin, timestamp, hash, local-only status. |
| Concept | Stable ID, title, topic/area, aliases, definition, revision. |
| Block | Stable ID, concept, kind, role, full content, order, revision, applicability/version. |
| Source mapping | Capture revision plus span/hash, or an external citation and supporting passage. |
| Proposal | Scope, base revision, proposed additions/changes, evidence, status, request ID. |
| Relationship | Endpoints, type, reason, evidence, status; explicit inverse where appropriate. |
| Reading state | Preferred depth, expanded sections, last-seen revision, scroll/navigation anchor. |

One capture may support several concepts; several captures may support one concept. Never overwrite original captures to make that organization possible. A correction is a derived revision with provenance.

Use one normalized presentation model for the UI, search destinations, and Markdown export. Replace duplicated QML knowledge-building transformations gradually through an adapter. Preserve legacy note IDs so existing links and assistant-selection saves continue working.

### Request contracts

Names below describe responsibilities, not final CLI spellings:

- **Save capture:** session ID, revision, text → durable capture ID and saved revision.
- **Organize capture:** capture/revision → structured concepts and blocks, with source coverage and unresolved spans.
- **Read/search:** query/scope/cursor → paginated local results and stable destinations.
- **Explain/fill gaps:** explicit scope, content revision, request ID → proposed additions, inspected coverage, and errors.
- **Accept/dismiss/undo:** proposal or revision ID → transactional result, affected IDs, and new revision.

Job states must distinguish queued, running, completed, failed, cancelled, and stale. Navigation can leave a job running for its original scope; its result cannot overwrite the currently displayed scope. Explicit cancellation prevents later automatic acceptance. Retries reuse stable operation identities where appropriate so duplicate completion does not duplicate content.

## 6. AI behavior and gap detection

All capture paths use the same sequence:

```text
Durable local save → eligibility checks → source segmentation
→ relevant existing concepts → extraction/proposals
→ schema + ID + source + revision validation → transaction
```

Sensitive material stays local. Personal/idea content stays verbatim. Deterministic checks may skip clear keyboard mashing, but unfamiliar language or a short technical identifier is not sufficient evidence of noise. Keep recoverable uncertain captures out of the technical topic strip until classified.

Retrieve relevant concepts by topic, aliases, identifiers, and content. Do not limit candidates to the most recent 40–50 records. Start with local full-text retrieval; add semantic retrieval only if measured search failures justify it.

The AI receives the selected material and useful neighboring concepts. It does not receive unrelated personal history or every note. Large sources are segmented with explicit coverage; unseen content is not a knowledge gap.

### Gap types

| Gap | Example of an appropriate addition |
|---|---|
| Missing mechanism | Explain why a copied reference still reaches the same object. |
| Missing example | Add a small example with its expected result and prerequisites. |
| Missing condition | Clarify when a rule holds or where it fails. |
| Missing comparison | Compare two choices using the same criteria. |
| Incomplete command | Propose required arguments/placeholders while retaining the original. |
| Missing area | Propose an area absent from the current topic, with a reason. |

Selected concept/area requests stay within that selection. All requests inspect an inventory of every area, process it in bounded batches, and may propose missing areas. Return a small prioritized batch with destinations and reasons. If inspection is incomplete, say so. Do not equate an empty response with complete knowledge.

For Why/Name/Compare, use saved explanations first. Generate only missing material. Verified claims require supporting evidence; acceptance alone is not verification. If source retrieval is unavailable, keep an unsupported explanation visibly reviewable and do not fabricate citations, exact naming origins, or version guarantees. Store evidence details in Sources rather than adding an AI label to every line.

## 7. Ordered implementation checklist

Every task starts pending. Mark it complete only after its acceptance evidence is recorded. Maintain a working application between phases.

### Phase 0 — Baseline and recovery

- [x] **P0.1** Recheck repository state and applicable instructions; identify concurrent work before edits.
- [x] **P0.2** Create a consistent SQLite backup using the backup API and a test copy. Record counts, source hashes, schema version, and restore instructions.
- [x] **P0.3** Capture the current review/capture behavior and establish isolated fixtures for long Java notes, commands, personal text, errors, and links.
- [x] **P0.4** Add a feature switch/adapter strategy so the old review remains available during conversion.

**Gate:** restore works on a temporary path; baseline source content is accounted for; no production migration has been attempted without a recoverable snapshot. Passed on 2026-11-20.

### Phase 1 — Capture and merge correctness

- [x] **P1.1** Save every capture before AI work; acknowledge only after durable persistence.
- [x] **P1.2** Unify sensitive-content, personal/idea, noise, and language policies across all entry points.
- [x] **P1.3** Replace the single overwriteable pending draft with session/revision-safe scheduling and recoverable unsaved text. Drafts are keyed by capture session, persisted before backend work, restored after FileView recovery loads, and cleared only when exact saved text matches.
- [x] **P1.4** Reject invalid merge targets and accidental cross-topic merges; remove the “newest note” fallback.
- [x] **P1.5** Preserve incoming sources during merge, update all derived structures atomically, and support undo.
- [x] **P1.6** Stop broad content rewriting during database reads; use explicit idempotent migrations.
- [x] **P1.7** Handle deliberate ignores, failures, retries, cancellations, and stale results consistently in QML. Skipped captures remain recoverable; failure/retry/stop/keep/ignore controls are available; late completions are token-checked. Backend cancellation and ignore/restore regression tests pass.

**Gate:** offline capture survives restart; invalid IDs alter no unrelated note; sensitive fixtures make no provider call; concurrent capture sessions do not overwrite each other; the displayed content matches accepted merges. Partially verified in tests/test_notes_upgrade_p1.py.

### Phase 2 — Structured depth without losing detail

- [x] **P2.1** Add concept/block/source-mapping schema and legacy adapters.
- [x] **P2.2** Segment long captures into focused concepts while preserving original source boundaries and snippets.
- [x] **P2.3** Keep unmatched source text reachable as Unplaced material; record extraction coverage.
- [x] **P2.4** Store Recall summaries separately from complete explanations; remove display/export string truncation.
- [ ] **P2.5** Unify the legacy topic/subconcept renderer and concept presentation into one normalized model. Current UI still has separate legacy block aggregation and concept-detail data paths; Markdown export uses the legacy block model.
- [x] **P2.6** Convert the Java pilot on a test copy and verify section/snippet coverage manually and with fixtures.

**Gate:** every original section is mapped or explicitly unplaced; changing depth is local; the old library remains readable; concept naming changes do not break IDs. Verified on 2026-11-20 in tests/test_notes_upgrade_p2.py and pilot migration.

### Phase 3 — Reading, navigation, and finding details

- [ ] **P3.1** Extract the accepted review view into focused components. Concept detail and gap suggestions are components, but the active review remains a large legacy QML file.
- [ ] **P3.2** Keep the established topic/subconcept navigation active. The experimental grouped index was rejected; stable concept-index navigation and Back history are not part of the active screen.
- [x] **P3.3** Add Understand/Recall with saved per-concept preference and expansion state. Both persist per concept; opening and switching modes leave the content revision unchanged. Verified in `tests/test_notes_upgrade_recovery.py`.
- [ ] **P3.4** Wire local search results into the active view and open exact blocks/sources. Backend search and tests exist, but the restored view currently provides topic-level filtering rather than the proposed exact-result flow.
- [ ] **P3.5** Refine the restored header/actions while preserving dragging, close behavior, `/` search focus, and text selection.
- [x] **P3.6** Make commands/code responsive with correct copy behavior and expected-result presentation.
- [ ] **P3.7** Surface unseen revisions in the active topic/subconcept view and navigate to the changed content. Concept detail has reading-state support, but the restored view still uses a time-based recent dot and does not consistently jump to the changed block.
**P3.8 was tried and reverted:** the concept-index grouped-card screen did not fit the user's preferred workflow. Its files are removed.

**Current gate:** backend concept/search tests pass, but the active UI has not been live-reloaded and visually verified in this session. Pointer-driven related-link clicks, display scaling, and mixed RTL/LTR remain manual checks. The active screen is the familiar topic/subconcept review, not the index.

### Phase 4 — Teaching and useful gap completion

- [x] **P4.1** Add contextual Why, Name, Counterexample, and Compare using existing content before generation. A saved answer opens locally; missing answers become reviewable proposals. Verified with `tests/test_notes_concept_details.py` and QML load at 600×400 and 1200×800.
- [x] **P4.2** Implement scope-aware coverage inventory and missing-role detection. The local `coverage-inventory` endpoint pages concept/area/topic/All scopes, reports structured roles and provisional candidates, and marks original captures for review before any gap claim. Verified with `tests/test_notes_coverage_inventory.py` and the live 104-concept library.
- [x] **P4.3** Let All propose missing areas while selected-scope requests remain confined. `suggest-gaps` inspects every inventory page in the selected topic, offers new-area leads only for topic All, and filters AI output to the exact selected area or concept. Original captures are checked for concept suggestions; private sources never reach the provider. Suggestions are review-only until P4.4. Verified by `tests/test_notes_gap_suggestions.py`, the full 191-test suite, and an isolated 900×620 QML load.
- [x] **P4.4** Add persistent ranked suggestion batches, accept/dismiss/accept-all, evidence details, and undo. Proposals are saved by exact scope and inventory revision; individual operations verify their target scope; accept-all only accepts the displayed scope; undo removes only the exact added block or an otherwise untouched new concept. Verified by `tests/test_notes_gap_suggestions.py` and the full 194-test suite.
- [x] **P4.5** Track version/applicability, distinguish unsupported material, and handle source-retrieval failure honestly. Concepts, blocks, and proposals persist applicability and evidence status. Generated explanations/gap suggestions remain visibly unverified; UI states that external sources were not checked. Version/platform scope is retained only when given by the proposal.
- [x] **P4.6** Add bounded context, caching, stale-result rejection, cancellation, and duplicate-request protection. Detail context is capped at 16 blocks/700 characters and 12K serialized characters; gap context is capped at 18K; oversized source review returns incomplete. Proposals deduplicate by scope/revision, stale revisions reject, and QML jobs can be cancelled or invalidated on scope changes.

**Gate:** repeated requests do not duplicate content; details already present in long sources are not rediscovered as gaps; missing areas can be proposed; late replies cannot alter another concept; unknown naming history stays unknown.

### Phase 5 — Connections, scale, and production migration

- [x] **P5.1** Migrate legacy links conservatively and add typed relationships with explanations and exact destinations. Only one-to-one legacy note→concept mappings migrate; ambiguous links stay untouched. Relations store status, type, reason, evidence, and optional source capture; lookup/navigation works from either endpoint.
- [x] **P5.2** Scope flag help to tool/subcommand/version; fix coordinate spaces and long-token behavior. Cache keys include tool, subcommand, version, and flag. `git add -p` and `git log -p` differ correctly; long tokens stay inside a horizontal scroller; tooltip coordinates map into the window.
- [ ] **P5.3** Measure rendering/search at representative sizes and connect paginated search to the active view. Backend search pages results and has a 1,005-concept regression test; the virtualized concept index was removed, and rendering performance of the restored grouped view is unmeasured.
- [x] **P5.4** Verify export/restore covers sources, concepts, blocks, revisions, links, proposals, and reading state. SQLite backup/restore helpers use the online backup API and integrity checks; round-trip tests include source mappings, concepts, blocks, relations, proposals, and reading state. Markdown export remains available per concept.
- [x] **P5.5** Rehearse migration twice on copies; check idempotence, source hashes, rollback, and interrupted recovery. A v15 snapshot migrated twice to v16; integrity, 104 concept IDs, 3 relations, and 115 raw captures were preserved. A partial-column migration fixture resumes safely; backup restore passed.
- [x] **P5.6** Migrate the live library with the verified procedure and preserve the backup/legacy adapter until checks pass. Live `user_version=16`, `integrity_check=ok`; 115 notes, 104 concepts, 198 blocks, 192 source mappings, 3 relations. Raw capture hashes match the pre-migration backup.
- [ ] **P5.7** Validate the restored live window, reopen/restart behavior, and complete the handoff record below. Prior live verification covered the experimental index, which is no longer active. Relation lookup is tested from both endpoints and concept detail has been loaded in a harness; current window interaction and physical scaling need rechecking.

**Gate:** live v16 integrity/count/hash checks pass, 1,005 synthetic concepts remain searchable across pages, and old note IDs and relations remain available. See the manual interaction note above.

## 8. Regression scenarios required before completion

| Scenario | Expected behavior |
|---|---|
| Large Java capture | Multiple concept pages; all original sections/snippets recoverable. |
| Reopen familiar concept | Remember Recall; one action restores deeper explanation. |
| English/French/Darija capture | Preserve meaning and language; no unwanted translation. |
| Personal idea or accidental typing | Separate personal preservation or recoverable skip; no meaningless concept proliferation. |
| Provider unavailable | Capture/read/search continue; generation retries locally scoped. |
| Unknown merge/link ID | No unrelated mutation; capture retained. |
| Newer source revision arrives during generation | Stale result cannot overwrite it. |
| Change topic during generation | Result belongs to original scope; no focus or scroll hijack. |
| Source too large for one request | Explicit partial coverage and resumable processing. |
| Search finds hidden detail | Opens matching block/source location, even in Recall. |
| `git add -p` versus `git log -p` | Correct contextual flag explanation. |
| Long code, small window, RTL text | Readable and reachable; exact copied bytes. |
| Delete, undo, restore, migrate twice | Consistent links and revisions; no duplicate data. |

## 9. Scope boundaries

Do not modify Assistant HUD chat behavior, MemoryView, or Gauntlet. Preserve assistant-selection capture compatibility. Speech typing and desktop borders are separate tasks.

Do not add quizzes, streaks, a graph dashboard, automatic snippet execution, a vector database, or a permanent sidebar in this upgrade. These may be considered later if actual use demonstrates a need. Do not ask the user to manually tag every capture or maintain a proficiency score.

## 10. Completion and continuation record

The established Notes view and Kubernetes content upgrade have been implemented and inspected. The broader handbook proposals above remain historical design context where they differ from the active compact view. In particular, the active view has no All tab, no separate default Understand/Recall mode, no inline related-link pills, and no exact-block search results yet. Do not mark those proposed features complete.

| Field | Current value |
|---|---|
| Last completed task | Kubernetes six-section curation, documented scoped Fill gaps, guarded corrections and undo, local Refresh, semantic unread dots, collapsed YAML, and long-command hover text |
| Next task | Audit another topic's captures, then test mixed RTL/LTR and narrow-window behavior in the active view |
| Implementation commits | Earlier phases: 63df1b08, 7b3c5d2d, 6249e23f, 9d041c07, 75fc574d, 7b58947f, 122f81f4, c8ae92c5. Current working-tree changes are uncommitted. |
| Active files | `modules/notes/NotesViewLegacy.qml`, `TopicInline.qml`, `PendingLine.qml`, `CommandWithFlags.qml`, `SelectableText.qml`, `services/Notes.qml`, `scripts/notes_backend.py`, `scripts/notes_topic_support.py`, `scripts/refine_kubernetes_notes.py` |
| Verification | Full Python suite: 220 passed; temporary SQLite rehearsal updated 13 and added four with byte-identical raw captures, second pass changed zero. Live Quickshell screenshot showed the six sections and collapsed code. A live provider request for Images on a temporary notebook returned no proposal. See 06 for detail. |
| Backup | `~/.local/share/caelestia/notes/backups/notes_before_reviewed_k8s_20261122T142644Z.sqlite3` |
| Live data | Schema v17; 17 active Kubernetes notes in six sections. Sources keep 13 prior captures verbatim. |
| Remaining limits | Provider/documentation availability affects Fill gaps. Long commands use horizontal scroll/full-text hover. Exact-block search and mixed RTL/LTR remain unverified in the active view. |

Update this record when the next topic is audited; preserve source captures and record a fresh backup before a data migration.
