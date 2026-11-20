# Implementation plan and continuation checklist

> Superseded as the progress tracker by [MASTER_PLAN.md](MASTER_PLAN.md). This document retains the original architecture/phase outline for reference. Mark implementation progress only in the master plan; its scope and task IDs take precedence.

**Only the audit and plan are complete. All application work below is pending.**

- [x] Inspect current UI and logic.
- [x] Inspect real technical captures using read-only SQLite queries.
- [x] Confirm preferred workflow: understand deeply, look up quickly later.
- [x] Run 43 existing tests and isolated reproductions of uncovered defects.
- [x] Write product, interface, architecture, and verification plan.

## Target data model

Extend SQLite incrementally. Keep existing IDs and the current Notes service while adapters provide the new presentation model. Do not bulk-regenerate the library with AI.

| Entity | Minimum purpose |
|---|---|
| Capture | Original text, capture origin, timestamp, content hash, local-only flag. Immutable revisions retain later edits; one capture can support several concepts. |
| Concept | Stable ID, title, topic/area IDs, aliases, one-line definition. Titles can change without breaking references. |
| Block | Stable ID, concept ID, kind (rule, explanation, code, command, comparison, reference), role, order, full content, revision, applicable version/context. |
| Block source | Capture revision and source span/hash, or external citation. Separate original excerpts from proposed corrections. |
| Relation | Source ID, target ID, type, explanation, evidence, status. Requires/used-by are directional inverses; comparison is symmetric. |
| Proposal/revision | Target scope and revision, suggested patch, state, evidence, and undo information. Accepted and verified are separate states. |
| View state | Per-concept depth preference, last-seen revision, expanded blocks, and navigation anchor. No automatic mastery score. |

Not every entity needs its own table in the first slice. Start with captures, concepts, blocks, and source mappings; migrate relations/state when their features land. Keep the mapping to old note IDs throughout.

## AI and storage pipeline

```text
Capture → durable local save → eligibility/noise checks
       → segment by source structure → retrieve relevant existing concepts
       → propose extraction/links/merge → validate against source + revision
       → transactional persistence → one normalized view model

Gap request → explicit scope + complete inventory + bounded source excerpts
            → ranked missing explanation/example/area proposals
            → accept/dismiss → append revision, refresh affected blocks
```

All capture routes must share this pipeline: typing, autosave, assistant selection, and pasted long notes. Do not let pause timing decide whether a note bypasses classification or goes directly through AI upsert.

AI calls receive the selected concept, relevant prerequisites, and a small set of retrieved neighboring concepts. Do not send all personal/profile/history context. Use IDs and revisions in responses; reject hallucinated IDs and stale patches. Long sources are processed in bounded segments with explicit coverage, not silently clipped to the first few thousand characters.

An AI explanation of “why” needs an applicable source or an honest unsupported state. Sources/versions live in the inspector to preserve a clean view. Names and historical rationale require evidence; plausible stories are not evidence. No web citation should be invented when retrieval is unavailable.

## Phase 1 — Reliable capture and merges

- [ ] Add tests for invalid merge IDs and cross-topic targets before changing behavior.
- [ ] Persist incoming raw captures before AI; return success only after durable save.
- [ ] Unify sensitive-input, noise, personal/idea, and language-preservation checks across entry points.
- [ ] Remove the fallback merge into the newest note. Preserve an unresolved capture instead.
- [ ] Make merges update the complete structured representation and create a reversible revision.
- [ ] Stop broad reclassification during reads; make migrations explicit, versioned, and idempotent.
- [ ] Handle `action=ignore` consistently in draft completion; do not display a failed-save message for a deliberate skip.
- [ ] Ensure a queued draft from a different capture session cannot overwrite or disappear behind another pending draft.

**Gate:** save succeeds offline; stale AI output cannot replace newer content; invalid merge targets change nothing; secrets never reach the mocked provider; every capture survives a merge/undo/restart. Use temporary databases and synthetic fixtures.

## Phase 2 — Preserve detail and build the first concept pages

- [ ] Introduce stable concepts, blocks, and capture-source mappings behind an adapter.
- [ ] Split the seven-area Java capture into source-backed concepts without dropping sections/snippets.
- [ ] Preserve unmatched content in an Unplaced section, rather than pretending extraction covered it.
- [ ] Separate Recall summaries from full explanation content. Remove renderer substring truncation.
- [ ] Build one presentation model for QML, search, Markdown export, and copying.
- [ ] Pilot pass-by-value, equality/hashCode, and concurrency choices on a copy of the library.

**Gate:** every source section maps to a block or explicit unplaced source; both retained original snippets and derived examples are distinguishable in Sources. Switching depth makes no network request. Export includes full selected content with correct fenced code.

## Phase 3 — Understand/Recall and retrieval

- [ ] Implement the concept index and page in the existing floating window.
- [ ] Keep stable topic order and remember the selected concept/mode/scroll anchor.
- [ ] Add inline explanations, expected-output blocks, and comparisons only where content exists.
- [ ] Move rare actions into overflow; remove the always-visible generation input.
- [ ] Add local full-text result rows with stable block destinations and Back navigation.
- [ ] Make code/command rendering responsive and preserve copied bytes.
- [ ] Implement unseen-revision dots and navigation to changed blocks.

**Gate:** the user can find a specific rule/example from a long capture without opening the raw-source drawer; the UI works at the stated minimum dimensions; updates do not move the reading position or steal keyboard focus.

**First release milestone:** phases 1–3. Evaluate this against actual learning and lookup sessions before adding further features.

## Phase 4 — Scoped teaching and gap filling

- [ ] Support Why, Meaning/name, Counterexample, and Compare as contextual requests.
- [ ] Use source-backed concept coverage to identify missing explanations, prerequisites, and examples.
- [ ] For a selected area/concept, restrict every proposal to that scope.
- [ ] For All, inspect every area's inventory and allow proposals for new areas; keep new-area creation reviewable.
- [ ] Mark partially inspected scopes as partial and avoid “nothing missing” claims for incomplete context.
- [ ] Show a small batch with destination and reason; accept/dismiss is idempotent and undoable.
- [ ] Reject stale results after navigation/content edits; avoid duplicate requests for the same revision.

**Gate:** current incomplete Docker syntax leads to a useful correction proposal; the long Java source does not trigger rediscovery of material merely omitted by the current renderer; repeated gap requests do not duplicate accepted or dismissed proposals.

## Phase 5 — Trustworthy connections and scale

- [ ] Migrate related IDs into typed, evidence-bearing relationships; preserve existing links as untyped until reviewed.
- [ ] Add exact link navigation and remove obsolete links through revisions.
- [ ] Key flag explanations by command/subcommand/version and fix tooltip coordinate spaces.
- [ ] Profile representative libraries; virtualize/lazy-load heavy content and replace whole-library refreshes where measurement justifies it.
- [ ] Add a documented full export and backup/restore path covering source captures, revisions, relations, and view state.

**Gate:** deleting/restoring a concept does not corrupt relations; bidirectional navigation lands on the right block; unknown flag help stays unknown; 1,000+ synthetic concepts remain searchable without silently disappearing behind the current default 500-row list limit.

## Migration and rollback

Use SQLite's backup API for a consistent snapshot, including WAL state, before any production migration. Develop against that copied database first. Preserve the original tables/IDs until the new renderer has been verified. Migration must be resumable and idempotent, with counts and source hashes checked before/after. A failed conversion leaves the old view usable.

Do not normalize, delete, merge, or reclassify the user's existing notes merely to make the demo look clean. Show proposed repairs for misclassified Docker/Java content and duplicate concepts. Keep deletions and corrections reversible.

## Tests that demonstrate the intended experience

| Scenario | Required result |
|---|---|
| Large Java reference pasted once | Multiple focused concepts; every original section reachable. |
| Familiar concept reopened | Remembered Recall view; full explanation one expansion away. |
| “Why this name?” without a historical source | Explain literal meaning; do not invent naming history. |
| Search for `computeIfAbsent` | Exact example and rule, not merely the Java topic title. |
| `git log -p` versus `git add -p` | Correct subcommand-specific explanation. |
| AI returns unknown merge/link ID | No unrelated record altered. |
| Capture contains a credential | Durable local storage; no external call. |
| Personal Darija thought | Preserved verbatim; not forced into a technical concept. |
| All gaps with a missing area | New-area proposal possible; incomplete inspection disclosed. |
| Topic changed while generation runs | Result stored under its original scope; current reading view remains stable. |
| Concurrent autosave, failure, and retry | No loss or cross-session overwrite; recoverable state. |

## Resume here

Start with **Phase 1**. Record each completed task and the actual checks run in this file. Do not mark the whole feature complete after a single visual prototype. The decisive first product demonstration is the same Java concept viewed deeply once and recalled quickly later.
