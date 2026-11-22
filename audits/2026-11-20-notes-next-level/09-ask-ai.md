# Ask AI in Notes — 2026-11-22

## Interaction

- **Ask AI** opens a compact inline composer in the existing Notes window. The selected subsection is the default scope; **Whole topic** is available in the composer. Ctrl+Enter sends a question.
- The reply always contains an answer. It may also contain proposed note changes when the user requested editing, expansion, shortening, commands, code, or a diagram. A question such as “What is missing?” can return an answer with no proposals.
- A proposal remains separate from saved notes until **Accept** or **Accept all**. **Delete** dismisses it. **Undo** reverses the latest accepted batch when the saved content has not since changed.
- Fill gaps suggestions and Ask AI proposals have separate sources and request IDs. There is no application-side count cap on either proposal list. The provider's output size still limits what one response can contain.

## Storage and safety

- The original capture remains in `raw_content`. Accepted replacement text lives in `display_edits_json`; accepted removal proposals hide specific display entries through `hidden_entries_json`; accepted additions are new locked notes. Native diagram proposals are validated before storage in `diagrams_json`.
- The backend validates subsection scope, exact replacement IDs and keys, content revision, syntax length, and sensitive content. Invalid proposals are skipped. A malformed provider response is retried once and never writes notes.
- Ask AI sends the complete selected subsection's shareable note inventory, including existing diagrams and section labels. A topic-wide question sends the complete shareable topic. Personal, local-only, skipped, and sensitive captures are excluded.

## Verification

- `python3 -m unittest discover -s tests -p 'test_notes*.py' -q`: 119 Notes tests passed on 2026-11-22. The full repository suite passed 231 tests.
- A temporary database call to the configured Gemini provider returned an answer and two staged bullet proposals for “Add two brief facts about Docker images”; no new notes were stored before acceptance.
- Quickshell reloaded and the Notes review window rendered with the Ask AI action. No Notes QML errors appeared in the live log.

## Current limits

- AI answers are transient in the composer; closing it or switching scope clears them. The reviewable proposals are stored in SQLite.
- Requested edits support add, replace, and hide at the note-entry level. A move or manual reorder operation for an entire subsection is not implemented yet.
