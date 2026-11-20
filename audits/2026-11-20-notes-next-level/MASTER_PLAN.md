# Notes upgrade — complete implementation plan

**Owner:** implementation agent working with Mohssine  
**Created:** 2026-11-20  
**State:** planned; application implementation has not started  
**Next task:** P0.1  
**Primary requirement:** understand deeply now, look up quickly later.

This is the authoritative scope and progress checklist. The other documents in this folder provide audit evidence, examples, and design rationale. Update completion status here as work proceeds.

## 1. What the finished system must do for you

You are a Java backend engineer interested in Linux, DevOps, and cloud. You capture definitions, rules, code, commands, comparisons, and things you do not yet understand. The system must preserve your material, organize it into meaningful concepts, explain those concepts when requested, and make the useful parts easy to retrieve later.

### Your normal workflow

1. Press Super+/, type or paste, and leave. Capture stays quiet and saves locally before AI processing.
2. Open Notes. Find a topic or search for a question, symbol, command, or phrase.
3. Open a concept in **Understand**: see its purpose, meaning, mechanism, rules, and example in a sensible order.
4. Expand **Why?**, **Why this name?**, **Counterexample**, or **Compare** where needed. Saved explanations open immediately; missing explanations are generated as reviewable additions.
5. Once comfortable, choose **Recall next time**. Later visits show the definition, useful rules, main example, and critical caveats. The full explanation remains available.
6. Use **Fill gaps** to improve the selected concept or area. Choose All to inspect the topic's areas, including possible missing areas.

The result is a personal engineering handbook. It should not require maintaining a folder tree, writing elaborate prompts, or taking a quiz before accessing your own notes.

## 2. Product decisions

| Area | Decision |
|---|---|
| Window | One floating window with capture and review modes, using existing global styling. |
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
| Connections | A few useful labeled links with exact navigation and Back; no mandatory graph screen. |
| Performance | Local reading/search, bounded AI context, cached saved explanations, lazy rendering. |

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

The top topic strip keeps a stable order. An area opens an index of its concepts; All opens a grouped topic index rather than concatenating every note. A concept opens within the same pane. No permanent sidebar is required.

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
- [ ] **P1.3** Replace the single overwriteable pending draft with session/revision-safe scheduling and recoverable unsaved text.
- [x] **P1.4** Reject invalid merge targets and accidental cross-topic merges; remove the “newest note” fallback.
- [x] **P1.5** Preserve incoming sources during merge, update all derived structures atomically, and support undo.
- [x] **P1.6** Stop broad content rewriting during database reads; use explicit idempotent migrations.
- [ ] **P1.7** Handle deliberate ignores, failures, retries, cancellations, and stale results consistently in QML.

**Gate:** offline capture survives restart; invalid IDs alter no unrelated note; sensitive fixtures make no provider call; concurrent capture sessions do not overwrite each other; the displayed content matches accepted merges. Partially verified in tests/test_notes_upgrade_p1.py.

### Phase 2 — Structured depth without losing detail

- [ ] **P2.1** Add concept/block/source-mapping schema and legacy adapters.
- [ ] **P2.2** Segment long captures into focused concepts while preserving original source boundaries and snippets.
- [ ] **P2.3** Keep unmatched source text reachable as Unplaced material; record extraction coverage.
- [ ] **P2.4** Store Recall summaries separately from complete explanations; remove display/export string truncation.
- [ ] **P2.5** Build a single presentation model and faithful Markdown export.
- [ ] **P2.6** Convert the Java pilot on a test copy and verify section/snippet coverage manually and with fixtures.

**Gate:** every original section is mapped or explicitly unplaced; changing depth is local; the old library remains readable; concept naming changes do not break IDs.

### Phase 3 — Reading, navigation, and finding details

- [ ] **P3.1** Extract focused QML components for navigation, concept page, blocks, proposals, and Sources.
- [ ] **P3.2** Implement stable topic/area navigation, grouped All index, concept page, and Back history.
- [ ] **P3.3** Add Understand/Recall with saved per-concept preference and expansion state.
- [ ] **P3.4** Implement local search results that open an exact block, including raw-source matches.
- [ ] **P3.5** Simplify the header/actions; preserve dragging, close behavior, search shortcut, and text selection.
- [ ] **P3.6** Make commands/code responsive with correct copy behavior and expected-result presentation.
- [ ] **P3.7** Add unseen-revision indicators and exact navigation to changed content.

**Gate:** learn pass-by-value in Understand, reopen it in Recall, and find the exact `computeIfAbsent` example through search. Verify 600×400, 900×620, and 1200×800 plus display scaling and mixed RTL/LTR text.

**First usable release:** phases 0–3. This is a milestone, not completion of the whole upgrade.

### Phase 4 — Teaching and useful gap completion

- [ ] **P4.1** Add contextual Why, Name, Counterexample, and Compare using existing content before generation.
- [ ] **P4.2** Implement scope-aware coverage inventory and missing-role detection.
- [ ] **P4.3** Let All propose missing areas while selected-scope requests remain confined.
- [ ] **P4.4** Add ranked suggestion batches, accept/dismiss/accept-all, evidence details, and undo.
- [ ] **P4.5** Track version/applicability, distinguish unsupported material, and handle source-retrieval failure honestly.
- [ ] **P4.6** Add bounded context, caching, stale-result rejection, cancellation, and duplicate-request protection.

**Gate:** repeated requests do not duplicate content; details already present in long sources are not rediscovered as gaps; missing areas can be proposed; late replies cannot alter another concept; unknown naming history stays unknown.

### Phase 5 — Connections, scale, and production migration

- [ ] **P5.1** Migrate legacy links conservatively and add typed relationships with explanations and exact destinations.
- [ ] **P5.2** Scope flag help to tool/subcommand/version; fix coordinate spaces and long-token behavior.
- [ ] **P5.3** Measure rendering/search at representative sizes; use virtualization and pagination to avoid hidden library limits.
- [ ] **P5.4** Verify export/restore covers sources, concepts, blocks, revisions, links, proposals, and reading state.
- [ ] **P5.5** Rehearse migration twice on copies; check idempotence, source hashes, rollback, and interrupted recovery.
- [ ] **P5.6** Migrate the live library with the verified procedure and preserve the backup/legacy adapter until checks pass.
- [ ] **P5.7** Validate the live window, reopen/restart behavior, and complete the handoff record below.

**Gate:** all agreed flows work on the real library, old IDs still resolve, no source material disappears, and 1,000+ synthetic concepts remain searchable without a silent 500-row cutoff.

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

The upgrade is complete only when the concept model, both reading modes, precise search, scoped explanations/gaps, recoverable migration, and regression scenarios above have been implemented and verified. A visually finished window alone is insufficient.

After each work session, update this block and tick only verified task IDs:

| Field | Current value |
|---|---|
| Last completed task | P0.1 - P0.4 (Phase 0 complete) |
| Next task | P1.1 — Save every capture before AI work |
| Implementation commits | 87d15e17 docs(notes): add engineering handbook audit and master plan |
| Application files changed | None for this upgrade yet |
| Baseline checks | 155 existing tests pass + 4 new P0 fixture tests pass |
| Backup / restore path | ~/.local/share/caelestia/notes/backups/notes_baseline_20261120.sqlite3 (114 notes, verified) |
| Migration state | Baseline snapshot verified; Phase 0 complete |
| Remaining blockers | None |
| Product direction | Confirmed: understand deeply now, look up quickly later |

For every completed phase, append its changed files, verification results, remaining limitations, and the next task. Keep this record current so a later session can continue without guessing.
