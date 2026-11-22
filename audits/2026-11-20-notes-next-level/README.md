# Notes handbook: current state and design record

**Updated:** 2026-11-22
**Current UI:** the established topic/subconcept review view (`NotesViewLegacy.qml`) is active through the `NotesView.qml` wrapper. The experimental concept-index/search shell was rejected and removed.
**Current implementation and continuation checklist:** [MASTER_PLAN.md](MASTER_PLAN.md).

## What is active now

- Quick capture remains in `QuickNote.qml`; backend capture, triage, structured concepts, source mappings, scoped gap suggestions, and concept detail remain available. Related links remain stored but are not shown as pills.
- Notes opens the familiar topic strip, subconcept strip, and grouped content view. Commands, code, notes, configuration, errors, references, completion bullets, and pending additions are presented from the restored view model.
- Completion facts appear as ordinary bullets in the selected subsection. Sources and concept detail remain available on demand; the default reading surface stays compact.
- The subsection strip opens on a foundational area; Kubernetes has six stable sections from Overview through Inspect & debug. There is no “All” tab, so “Fill gaps” targets the selected section.
- Related links remain stored, and the inline pills are removed to keep the reading area focused. New-content dots track semantic revisions and clear after the content is viewed. Refresh reloads local data without AI triage.
- Code samples start collapsed. Their language badge, one-line explanation, expand control, and icon-only copy action share one compact header.
- Original captures remain accessible through Sources. Personal and skipped captures remain separate from technical topics.
- Current UI logic retains full command explanations and combines duplicate commands without discarding distinct explanations. Long commands scroll horizontally and reveal their full text on hover.
- Ask AI uses the selected subsection by default, with an explicit whole-topic scope. It can return an answer alone or an answer with optional staged note changes, including native diagrams. Accepted changes preserve captures and support undo. Fill gaps and Ask AI proposals remain separate, with no application-side suggestion count cap.

## Deliberately not active

The separate grouped concept-index screen and dedicated handbook navigation/search-result components were removed because they did not match the user's preferred review layout. Backend concept search remains available, but the restored review view does not currently expose the proposed exact-block search-results flow. Do not report that flow as complete.

## Design records

| File | Use |
|---|---|
| [01 — Audit](01-current-audit.md) | Findings from the 2026-11-20 source/data audit; historical findings with current status. |
| [02 — Learning model](02-learning-model.md) | Product principles for deep learning and quick recall; design goals, not implementation claims. |
| [03 — Window design](03-window-design.md) | A proposal; the concept-index layout is not active. |
| [04 — Implementation plan](04-implementation-plan.md) | Original architecture/acceptance scenarios; the master plan is the only live checklist. |
| [05 — Kubernetes pilot](05-kubernetes-pilot.md) | Historical first pilot and preservation procedure; superseded for live Kubernetes content by 06. |
| [06 — Kubernetes stability upgrade](06-kubernetes-stability-upgrade.md) | Six-section structure, scoped Fill gaps, correction safety, and read markers. |
| [07 — Kubernetes practical depth](07-kubernetes-practical-depth.md) | Current details, commands, preservation checks, and live verification. |
| [08 — Overview and diagrams](08-kubernetes-overview-diagrams.md) | Detailed Overview, native diagram pilot, storage rules, and verification. |
| [09 — Ask AI](09-ask-ai.md) | Current answer and optional proposal flow, scope, acceptance, and verification. |

## Next work

Keep the established layout. Apply the verified subsection procedure to another topic after inspecting its captures. Exact-block search remains outside the active view; do not claim it is complete. No Assistant HUD, MemoryView, or Gauntlet changes are in scope.
