# Memory, history, profile, and practice

**Judgment:** these features serve different purposes but currently share too much presentation and persistence behavior. Keep them useful and understandable: conversation archive, approved personal preferences, saved knowledge, and optional practice.

## Current → proposed

| ID / priority | Current evidence | Needed change |
|---|---|---|
| M01 · P1 | **Confirmed:** malformed history/chats become empty arrays, and later save functions have no recovery block. Profile has a similar default-on-parse-error path. [Assistant:96](../../services/Assistant.qml#L96), [Assistant:120](../../services/Assistant.qml#L120), [Assistant:156](../../services/Assistant.qml#L156) | Extend memory's backup/recovery behavior to every durable store. Distinguish missing, unreadable, invalid-schema, and healthy data before allowing saves. |
| M02 · P1 | **Confirmed source risk:** QML saves whole memory arrays; Python chat exposure and memory operations also replace the same file, with two Python paths sharing `.tmp`. Atomic replacement cannot prevent lost updates between independent writers. [Memory:301](../../services/Memory.qml#L301), [API:444](../../scripts/assistant_api.py#L444), [Engine:241](../../scripts/memory_engine.py#L241) | Centralize writes or use a shared lock/revision protocol across all writers. Apply operations to the latest valid data. Use unique temporary names and save acknowledgements. |
| M03 · P1 | **Confirmed:** memory recovery's successful-inspection branch calls `root.memoryStorage.reload()` even though `memoryStorage` is an ID, not a root property. [Memory:162](../../services/Memory.qml#L162) | Correct the reference and verify both successful re-read and backed-up-corruption recovery. Preserve the existing recovery design. |
| M04 · P1 | **Confirmed source risk:** accepting a proposal schedules the card save for later, then immediately removes/saves the proposal. The proposal queue also treats valid non-array JSON as empty. [Memory:224](../../services/Memory.qml#L224), [Memory:248](../../services/Memory.qml#L248) | Validate schema; commit the card before removing its proposal, with recovery if either write fails. Approval must not disappear without the saved card. |
| M05 · P2 | **Confirmed:** deleting a chat leaves raw assistant history and derived memory intact. History view explains this but does not make a whole-conversation forget operation available. [Assistant:874](../../services/Assistant.qml#L874), [History:180](../../modules/assistant/HistoryView.qml#L180) | Offer clearly scoped Archive/Delete/Forget actions. “Forget” previews affected history, suggestions and sourced memories; preserve independently approved facts unless the user chooses to remove them. |
| M06 · P2 | **Confirmed:** the history list slices to 30 chats; no control or scroll handler increases `visibleLimit`. Older chats can surface via search but cannot all be browsed normally. [History:88](../../modules/assistant/HistoryView.qml#L88) | Use a virtualized list or real incremental loading, with count and complete search. Preserve selection/scroll when renaming or pinning. |
| M07 · P2 | **Observed/source:** profile repeaters resolve `modelData` to a screen object, producing warnings. HUD Escape also references removed profile editing members. [Profile:864](../../modules/assistant/ProfileView.qml#L864), [HUD:149](../../modules/assistant/AssistantHUD.qml#L149) | Declare delegate model properties; remove obsolete editing references. Make draft/save/discard behavior explicit and preserve drafts on navigation. |
| M08 · P2 | **Confirmed:** profile “Saved” feedback is triggered before persistence completes; the Python API redefines imported profile helpers and uses a direct write. [Profile:1146](../../modules/assistant/ProfileView.qml#L1146), [API:313](../../scripts/assistant_api.py#L313) | Use one profile schema/writer with completion/error feedback. Do not silently reset an unreadable profile to plausible defaults. |

## Clearer views

| View | Keep visible | Put in details or a separate mode | Add/remove |
|---|---|---|---|
| History | Search, chat title, last activity, short preview | Rename, export, delete/forget, source details | Add older-chat browsing and undo; remove permanently visible explanatory boilerplate after the action meanings are clear. |
| Memory | Search, approved knowledge/preferences, compact suggestion count | Full suggestion review, source, scope, last-used date, edit/delete | Add “used for answers” and project/topic scope controls. Avoid several stacked banners above the actual list. |
| Profile/settings | Providers, language/style preferences, relevant environment settings | Optional developer details and privacy settings | Replace “Developer Dossier” framing with plain labels; allow unrelated technical details to stay saved but unused. |
| Practice | Subject, one question, answer, progress, feedback | Detailed scoring/history | Keep practice separate from everyday memory browsing and ordinary chat personalization. |

Do not automatically remove existing knowledge or learner progress. First make it possible to inspect, disable for replies, correct, archive, export, or delete it deliberately.

## Acceptance checks

- Invalid JSON, wrong-shaped valid JSON, permission failure, and missing files each produce distinct safe behavior on fixture copies.
- Save is blocked until required recovery succeeds; original unreadable bytes are preserved and the backup location is visible.
- Two concurrent edits and a background extraction cannot silently erase each other's updates.
- An interrupted proposal acceptance leaves either the proposal or the accepted card recoverable.
- Browse more than 30 chats; search, pin, rename, export, delete and undo maintain the right identity.
- Profile repeaters have no type warnings; Escape/back has defined draft behavior; “Saved” appears only after acknowledgement.
- Turning off a memory for replies actually excludes it from request context while leaving practice/export available.

**Files:** `services/{Assistant,Memory}.qml`, `scripts/{assistant_api,assistant_common,memory_engine}.py`, `modules/assistant/{HistoryView,MemoryView,ProfileView,GauntletView,MemoryCardItem,KnowledgeCardDelegate,FactCardDelegate}.qml`.
