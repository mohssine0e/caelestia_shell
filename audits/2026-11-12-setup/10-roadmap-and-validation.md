# Implementation roadmap and review gates

**Recommendation:** repair trust and behavior first, then layout, then simplify the views. Review one small batch at a time so good existing behavior does not get lost in a large redesign.

These are proposed changes. This audit creates Markdown only. Each implementation batch should end with its own diff, evidence, and a short user review before the next visible redesign.

## Proposed batches

| Order | Scope and issue IDs | Likely files | Visible completion criterion |
|---|---|---|---|
| 1A | Request correctness: U01–U06; M07 delegate/obsolete-reference defects | `services/Assistant.qml`, `scripts/assistant_api.py`, `AssistantHUD.qml`, `ProfileView.qml` | Stop stays stopped, fallback never mixes answers, settings never auto-resend, no finalization/delegate exceptions. |
| 1B | Save/recovery foundation: M01–M04, M08; T01–T02 | `Assistant.qml`, `Memory.qml`, `assistant_common.py`, `assistant_api.py`, `memory_engine.py`, task/note persistence | Unreadable data is preserved; saves acknowledge success; concurrent writes and proposal acceptance are recoverable. |
| 1C | Privacy paths: P01–P07/P10; I05–I06 | Context/job settings, helper stdin, voice scripts, separate lock patch | Background jobs obey settings; voice leaves no transcript log; lock entry-point review is completed in a controlled test. |
| 2 | Relevant AI context: A01–A09 | Assistant/memory services, one context-builder module, API adapters, small HUD context detail | General questions remain general; technical context is attached only when relevant; selected-source details explain each inclusion. |
| 3 | Shared layout: W01–W09; T03; I01–I02 | HUD/window and all assistant subviews, Tasks/Commands wrappers, timer wrappers, Hyprland placement helpers | No clipped primary controls, no recursive layout warnings, predictable resize/scroll/focus at all target sizes. |
| 4 | Memory/history UX: M05–M08 | History/Memory/Profile/Practice views and source-linked store operations | Browse all chats, inspect/use/disable memory, understand deletion/forget, and save profile drafts reliably. |
| 5 | Timer correctness: F01–F08 | `FocusTimer.qml`, timer views, task integration, session store | Breaks preserve task effort; sessions survive reload; completion and pause behavior are unambiguous. |
| 6 | Task workspace: T04–T08 | Task store, tasks/habits/notes/commands views | Shared data across monitors; consistent undo, editing and navigation; no sample notes persisted. |
| 7 | Display/desktop behavior: I03–I04, P08–P09 | ProjectMenu, external display helper, reload workflow, Weather/VPN | Display changes can be reverted; scale is preserved; reload cannot discard active work or disrupt a locked session. |
| 8 | Measured simplification: E01–E08, remaining visual polish | View loaders, refresh logic, shared helpers, CI | Less unnecessary hidden work and repeat network activity, with measured comparisons and no feature regressions. |

The directly reproducible break-accounting fix F01 can be moved into the first reliability batch. Full timer persistence depends on the storage foundation. Lint/tooling repair E07 should begin immediately and gate subsequent code batches, rather than waiting until order 8.

## First implementation slice

Keep it small and reviewable:

1. Correct request-exit handling and cancelled-request rejection; clear pending stream work on cancellation.
2. Stop settings saves from resending questions; report actual save success/failure.
3. Fix the known user-bubble geometry and required profile delegate model properties.
4. Add focused offline checks for those behaviors and inspect fresh runtime logs.

Then implement selective context as the next assistant feature. Do not combine a new context engine with a full visual redesign in the same change.

## Required behavior matrix

| Area | Cases | Pass condition |
|---|---|---|
| Geometry | 1920×1080, 1366×768, 960×540 logical areas; larger fonts; fractional scale; monitor offsets | All main text and essential controls reachable; no clipped composer, save, back or close; correct owning monitor. |
| Content | Empty/loading/error, long titles, code/table/URL, mixed Arabic/English, many tags, long recovery message | Stable wrapping/scrolling and no repeated layout errors. |
| Context | Greeting, translation, direct fact, explicit Java/Bash, personal planning, short follow-up, new topic, Arabic topic shift | Only relevant/explicitly attached sources; appropriate answer depth; no invented document access. |
| Requests | Cancel before/during/after chunks, supersede, retry, provider failure after partial output, empty/blocked output, settings save | One correct terminal state and no stale updates, duplicate sends, or mixed attempts. |
| Persistence | Missing/corrupt/wrong schema/permission denied; interrupted save; two writers; accept suggestion then crash | Original data recoverable; no silent overwrite; success is acknowledged truthfully. |
| History/memory | More than 30 chats, reopen topic, undo delete, scoped forget, disable memory for replies | Full browsing, correct topic boundaries and predictable retention. |
| Timer/tasks | Work → break → work, task rename/delete/switch, reset, restart, suspend, local rollover | Correct effort accounting, recoverable sessions, stable task identity. |
| Privacy | Context off, background off, restricted provider, voice cancel, clipboard history, lock entry points | All data paths honor their defined policy; no private-text logs or unintended authentication bypass. |
| Performance | Cold start, first-open, repeated open/close, idle, long streaming, large lists, hidden stopwatch | Comparisons use the same setup; no unsupported claims of savings or leaks. |

Run dangerous/failure scenarios on copied stores and a fake worker first. Screen-mode and lock tests require a controlled session with a recovery route; do not experiment on the user's active work.

## Delivery rules

- Record the starting commit and preserve existing user work. Keep repository and external Hyprland changes separately reviewable.
- For each batch, report changed behavior, changed files, checks and remaining limits. Avoid unrelated cleanup.
- Confirm command exit codes. An empty lint output is not a pass; current local lint returns 255.
- Review screenshots of each changed view/state at the agreed sizes. Geometry numbers alone do not prove that children fit.
- Before reloading after code changes, protect active data/timer/lock state. Then reload the actual shell, as requested, and inspect fresh logs. Do not reload merely for Markdown updates.
- Update this folder's issue status only after acceptance checks pass. Do not treat a suggestion or partial sizing formula as a completed fix.

## Defer until the foundation is reliable

- More automatic memory extraction, autonomous actions or new AI tools.
- A vector database or always-running local model without evidence that simpler relevance selection is inadequate.
- More badges, statistics, animations or mandatory per-message review dialogs.
- Automatic task completion based only on time, and global personalization based on unrelated practice mistakes.

The desired outcome is a calm desktop with predictable controls and a question-aware assistant. Success is fewer irrelevant answers, fewer surprises, and fully reachable content.
