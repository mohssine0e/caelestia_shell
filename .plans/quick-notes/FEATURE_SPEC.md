# Quick Notes & AI Organizer

**Status:** Compact autosave, background triage, and single-window review implemented
**Created:** 2026-11-12
**Updated:** 2026-11-13
**Scope:** An isolated capture and review system for technical notes, personal thoughts, and ideas

## 1. Product decisions

- Use one Quick Notes window with two modes: a `600 × 150` compact capture and a `900 × 620` review mode.
- `Super+/` opens capture. `Super+Shift+/` opens review.
- Compact mode contains only the editor and the user's text. It has no title, placeholder, buttons, status text, spinner, or keyboard hints.
- Focus enters the editor automatically. Enter inserts a normal newline.
- Save locally after 600 ms of inactivity. Never wait for AI before preserving the raw note.
- Start AI triage after 2.8 seconds of inactivity, or when the capture closes.
- Keep every raw note. AI may mark meaningless input as `skip`, but it cannot delete it.
- Preserve personal thoughts and ideas verbatim. AI formatting applies only to technical and reference material.
- Reuse the Assistant HUD provider configuration and transport. Keep note prompts, state, storage, and UI separate from Assistant chat and memory.
- Keep MemoryView and Gauntlet untouched. Learning-system integrations remain a future, explicit bridge.

## 2. Implementation progress

- [x] **Step 1 — Private storage:** SQLite schema, migrations, create/list/get/update, soft-delete, restore, search, and private filesystem permissions.
- [x] **Step 2 — QML service:** JSON process boundary, coalesced draft saves, background triage queue, stale-response protection, retries, and refresh actions.
- [x] **Step 3 — Compact capture:** one empty editor surface, automatic focus, multiline typing, idle autosave, delayed analysis, Escape flush-and-close, and responsive active-monitor placement.
- [x] **Step 4 — AI triage:** classify notes as technical, reference, personal, idea, or noise; produce concise bullets for technical content; preserve personal content verbatim; label limited AI-added context.
- [x] **Step 5 — Review UI:** search, category filters, raw/formatted display, editing, copying, retrying analysis, soft deletion, undo, and narrow/wide layouts.
- [x] **Step 6 — Single-window behavior:** capture and review resize the same Hyprland client instead of opening multiple windows.
- [x] **Step 7 — Shell integration:** screen state, Caelestia global shortcuts, IPC methods, shell loading, Hyprland bindings, and script packaging.
- [x] **Step 8 — Verification:** eight backend tests, QML convention checks, diff validation, live shell reload, focus/save/restart checks, real provider triage, and live capture/review resizing.
- [x] **Step 8.1 — Developer knowledge model:** technical subtypes, generated titles, tool/language metadata, suggested tags, exact source excerpts, duplicate suggestions, local secret detection, Inbox bulk analysis, and a content-first review layout.
- [x] **Step 8.2 — Topic knowledge view:** canonical topics, local topic hints for legacy notes, grouped captures, ordered overview/command/code/configuration/error/reference sections, and semantic duplicate reduction.
- [x] **Step 8.3 — Focused review redesign:** single-pane reader, compact search and topic/tag strip, quiet topic actions, structured command table with copy feedback, raw-source drawer, and keyboard navigation.
- [ ] **Step 9 — Optional learning bridge:** reviewable fact extraction and explicit export to Gauntlet/Knowledge Nodes.

## 3. User experience

### Compact capture

| Event | Behavior |
|---|---|
| Open with `Super+/` | Center on the active monitor, clear the capture editor, and focus it immediately |
| Type | Show only the text being typed |
| Pause for 600 ms | Save or update the raw draft locally |
| Pause for 2.8 seconds | Queue background AI triage after the local save |
| Enter | Insert a newline |
| Escape | Flush the latest text, queue analysis, and close |
| Switch to review | Flush the latest text, queue analysis, and expand the same window |
| Blank capture | Do not create a note |
| Save error | Keep the draft available and show an external error toast; a red border is the only compact-mode error decoration |

Autosaves are coalesced. If the first database create is still running while the user continues typing, the next save updates the returned note ID instead of creating a duplicate.

### Background triage

| Classification | Stored result |
|---|---|
| Technical | At most six short Markdown bullets containing essential information |
| Reference | The same concise bullet treatment as technical content |
| Incomplete technical fact | Up to three directly implied, well-established facts under `**AI-added context**` |
| Personal thought | Raw text unchanged; no generated formatted copy |
| Idea | Raw text unchanged; no generated formatted copy |
| Meaningless/noise | Mark `skip` but retain the raw note for recovery |

The AI must not invent credentials, paths, project details, personal preferences, or user intent. A request token prevents late output from overwriting newer text.

### Review mode

- Use the same Quick Notes window in its expanded size.
- Filter by `Notes`, `Technical`, `Personal`, `Ideas`, or `Skipped`.
- Group results as Inbox, Technical, Reference, Personal, Ideas, and Skipped.
- Search raw text, formatted text, and literal hashtags.
- Show formatted bullets for technical/reference notes and exact raw text for personal/idea notes.
- Keep skipped notes visible through the Skipped filter so an incorrect AI decision is recoverable.
- Allow copying, analyzing again, deleting with undo, and restoring notes.
- Disclose the configured primary and fallback providers in review mode without exposing credentials.

## 4. Architecture

```text
Super+/ capture       Super+Shift+/ review
       │                         │
       └─────────────┬───────────┘
                     ▼
          QuickNote.qml (one window)
          ├── compact capture mode
          └── NotesView.qml review mode
                     │
                     ▼ stdin/stdout JSON
              services/Notes.qml
                     │
                     ▼
             notes_backend.py ─────▶ notes.sqlite3
                     │
                     └── delayed triage request
                              │
                              ▼
                 Assistant provider transport
                 and configured credentials
```

### Separation of concerns

- `QuickNote.qml` owns capture-window behavior and mode switching.
- `NotesView.qml` owns review presentation and actions.
- `services/Notes.qml` owns asynchronous processes, save coalescing, and request queues.
- `scripts/notes_backend.py` owns validation, migrations, persistence, prompts, and triage state.
- Existing Assistant modules own provider credentials and HTTP/streaming transport.
- Notes never read or write `assistant_memory.json`.
- Notes never write to Gauntlet or Knowledge Nodes in this release.

## 5. Storage

Database location:

```text
$XDG_DATA_HOME/caelestia/notes/notes.sqlite3
```

The notes directory uses mode `0700`; the database uses `0600`.

| Field | Purpose |
|---|---|
| `id` | Locally generated UUID |
| `created_at`, `updated_at` | UTC timestamps |
| `raw_content` | User text; AI never overwrites it |
| `formatted_content` | Concise technical Markdown, otherwise empty |
| `tags` | Literal hashtags and user-managed metadata |
| `status` | Inbox/processing/completed/failure state |
| `category` | `unclassified`, `technical`, `reference`, `personal`, `idea`, or `noise` |
| `keep_decision` | `pending`, `keep`, or recoverable `skip` |
| `triage_error`, `triage_attempts` | Retry and diagnostic state |
| `triage_token` | Rejects stale provider output |
| `title` | Short AI-generated title for retrieval |
| `technical_type` | Command, code, concept, error/fix, configuration, tool, reference, or general |
| `technology` | Detected language, CLI, framework, or tool |
| `ai_tags` | Searchable suggested tags stored separately from user tags |
| `local_only`, `sensitive_reason` | Blocks detected credentials and secrets from provider requests |
| `duplicate_of` | Links a likely duplicate without merging or deleting either note |
| `topic` | Stable knowledge topic used to group atomic captures |
| `essentials`, `completions`, `exact_excerpts` | Structured facts and verbatim technical material used by the topic view |
| `deleted_at` | Supports soft deletion and undo |

Schema version 4 migrates existing databases in place and preserves all note IDs and content.

## 6. Backend interface

Implemented commands in `scripts/notes_backend.py` include:

```text
create           Save raw content and return the note
list             Return filtered note summaries
get              Return one complete note
update           Edit raw content or tags and reset stale triage state
delete           Soft-delete a note
restore          Undo soft deletion
triage           Classify and, when appropriate, create concise bullets
organize         Legacy/manual compatibility path
provider-status  Report provider availability without credentials
```

Private note text travels through stdin JSON, never command-line arguments. The backend imports the existing Assistant configuration and provider functions, but supplies its own note-specific prompt and parses strict JSON output.

## 7. Privacy and failure behavior

- Commit raw text locally before starting automatic AI work.
- Automatic triage is part of the requested capture flow and uses the Assistant HUD's configured provider and fallback.
- Do not log raw notes, provider responses, or API keys.
- Preserve raw content on missing credentials, timeout, malformed output, cancellation, or provider failure.
- Store a short local error and allow retry from review mode.
- Ignore provider output if the note changed after the request began.
- Never automatically delete content based on an AI classification.
- Detect common credentials and private keys locally before any provider call. Mark them Local only.
- Existing notes from older schemas remain `unclassified` until the user chooses Analyze Inbox; migration does not silently upload them.

## 8. Files

### Feature files

- `modules/notes/QuickNote.qml`
- `modules/notes/NotesView.qml`
- `services/Notes.qml`
- `scripts/notes_backend.py`
- `tests/test_notes_backend.py`

### Integration files

- `CMakeLists.txt`
- `shell.qml`
- `components/ScreenState.qml`
- `daemons/Shortcuts.qml`
- `/home/mohssine/.config/hypr/hyprland/keybinds.lua`

### Explicitly excluded

- `modules/assistant/AssistantHUD.qml`
- `modules/assistant/MemoryView.qml`
- `services/Memory.qml`
- Gauntlet UI and grading logic
- `assistant_memory.json`

## 9. Verified acceptance criteria

- [x] `Super+/` opens one focused compact window on the active monitor.
- [x] Compact mode has no visible text except what the user types.
- [x] Typing autosaves locally without requiring a submit key.
- [x] Enter creates multiline notes.
- [x] AI work starts only after raw content is stored.
- [x] Capture remains responsive during Python and network work.
- [x] Continued typing coalesces saves instead of creating duplicate notes.
- [x] Late AI responses cannot overwrite a newer note version.
- [x] Personal thoughts and ideas remain verbatim.
- [x] Technical results are concise bullets and AI-added context is labeled.
- [x] AI skip decisions are recoverable and never delete raw content.
- [x] A saved note survives shell restart and provider failure.
- [x] Capture and review use one Hyprland client and resize correctly.
- [x] No feature code reads or writes Assistant memory or Gauntlet data.

## 10. Verification record

- Ten backend tests pass, including migration-safe storage behavior, private permissions, personal-note preservation, technical metadata and exact excerpts, local secret blocking, duplicate suggestions, recoverable noise classification, provider failure preservation, and stale-response rejection.
- Repository QML convention checks pass for `services/Notes.qml`, `modules/notes/QuickNote.qml`, and `modules/notes/NotesView.qml`.
- `git diff --check` passes.
- The live shell reloads and registers the notes/assistant IPC targets and both shortcuts.
- Live capture autosaved continued typing into one database row.
- Synthetic technical and personal notes completed through the configured provider with their raw content preserved; the disposable test notes were soft-deleted afterward.
- The existing notes database migrated to schema version 4 without losing existing rows.

The system `qmllint` does not understand the repository's existing `pragma ComponentBehavior: Bound` syntax. The repository convention checker and the live Quickshell parser are therefore the applicable QML validation gates.

## 11. Next phase

Add the learning bridge only after the notes workflow has been used long enough to establish useful categories and review habits:

1. Extract one to five local fact candidates from a selected technical note.
2. Show the candidates for editing and selection.
3. Export selected facts through a narrow Gauntlet adapter.
4. Add Knowledge Node promotion as a separate explicit action.

No automatic promotion should occur, and personal/idea notes should be excluded by default.

## 12. Topic learning gaps (2026-11-14)

Historical implementation record. Replaced by the inline topic workflow in
Section 13 below; the answer-checking panel and its actions were removed.

Checkpoint before this phase: `73972cf6` — grouped topic review, typography,
search/Escape handling, draggable header, and separate topic/tag banner.

- [x] Add **What am I missing?** and **Add note** actions for named topics.
- [x] Keep the learning panel inside the existing review window.
- [x] Request up to five concise gaps using only eligible notes from the selected
  topic; exclude private/local-only, personal, idea, skipped, and detected-secret
  captures. Bound the request context to 24,000 characters.
- [x] Reuse the configured assistant provider and fallback through the existing
  notes provider adapter, without assistant conversation or memory context.
- [x] Persist suggestions and dismissals in a separate SQLite table. Exclude
  previous suggestions from later requests; provide **Restore dismissed**.
- [x] Offer **Explain**, **Write my own**, and **Dismiss** for each suggestion.
- [x] Check a **Write my own** answer with AI before saving it. Correct answers
  save automatically; incomplete or incorrect answers show brief feedback and
  a corrected version for retry. Edited answers require a new check. Sensitive
  text is rejected locally before any provider call.
- [x] Show the AI explanation as a preview; require **Save to topic** to create
  a note. Label AI-origin notes in the topic content and source drawer.
- [x] Keep manually added notes linked to their chosen topic through edits and
  later analysis. Writing an answer to a gap marks that gap as saved.
- [x] Make saving a suggestion idempotent and keep provider failures from changing
  saved notes. Prevent late results from appearing under another topic.
- [x] Protect unsaved editor text when closing the learning panel.
- [x] Add schema version 6 with additive migrations and backend regression tests.

Usage: open a named topic, choose **What am I missing?**, then **Suggest gaps**.
Choose **Explain** to preview a concise explanation before saving, **Write my
own** to record your understanding, or **Dismiss** to hide that suggestion.
**Add note** directly saves your own topic-linked capture without an AI call.

Validation: 22 backend tests use temporary databases and mocked provider output.
The new QML panel passes the repository convention checker; the live shell loads
it without Notes errors and the empty learning panel has been visually checked.
Live provider output quality has not been evaluated in this phase. Context is
bounded, so suggestions can miss coverage in older or very long notes; semantic
deduplication depends partly on the model. Existing NotesView formatting warnings
predate this phase; no broad reformat was performed.

## 13. Inline topic completion (2026-11-14)

- [x] **Fill gaps** makes one provider request for concise, section-specific
  candidate lines using only eligible notes from the selected topic.
- [x] Pending candidates appear within Overview, Commands, Code,
  Configuration, Errors & Fixes, or References. Each has Accept and Delete.
- [x] **Accept all** saves the remaining pending lines in one transaction.
  Accepted commands retain their exact command and a short explanation.
- [x] Delete dismisses only the candidate; it does not delete a saved note.
- [x] Pending candidates have only Accept and Delete actions. Saved knowledge
  lines are read-only; Overview uses bullets. Only command rows have copy icons.
- [x] Remove visible AI provenance labels and edit controls from the topic view
  and Sources drawer. Keep original captures and any previously saved display
  edits in storage.
- [x] Remove the learning drawer, user-answer grading flow, and unused backend
  endpoints. Keep existing saved notes and dismissed candidates in the database.
- [x] Run 20 backend tests against temporary databases and mocked provider
  output. Check the new QML components and load the live shell.

Usage: choose a topic and click **Fill gaps**. Accept useful lines individually,
delete unwanted candidates, or choose **Accept all**. Copy a command with its
left-side icon, or copy the whole topic with the text action in the header.
Sources shows the original captures.

Limit: provider quality still needs real-use review. Sources retains the raw
text for provenance.

## 14. Topic overview and notes sections (2026-11-14)

- [x] Make the command copy glyph slightly smaller while keeping its 28px hit area,
  and reduce the review window from 920×640 to 900×620.
- [x] Add **Notes** between Overview and Commands for captured concept facts and
  accepted AI notes. Keep Overview for short topic-level bullets.
- [x] Ask Fill gaps to prioritize an overview bullet and useful notes, with a
  focused second request only when the first reply omits an unsaved overview.
- [x] Persist the accepted line's section so overview and notes stay separate
  after refresh; migrate existing databases without discarding saved notes.
- [x] Back up the live notes database and soft-delete three clearly identified
  Docker test captures: `what is docker`, `docke is mn3rf`, and
  `test adding a note`. Other captures remain unchanged.
- [x] Run backend tests and reload the shell.
