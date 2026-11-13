# Assistant request behavior and HUD UX

**Judgment:** keep the familiar HUD, but repair request ownership before adding more AI actions. The current implementation has useful request IDs and states, yet several paths bypass their intended guarantees.

## Bugs and required behavior

| ID / priority | Current evidence | Needed change |
|---|---|---|
| U01 · P1 | **Observed:** `onExited` throws `Cannot read property 'running' of undefined`. `apiProc` is an object ID, but the handler uses `root.apiProc.running`. [Assistant:660](../../services/Assistant.qml#L660) | Reference the actual process and identify which request exited. Handle an exit without a terminal event without touching a newer request. |
| U02 · P1 | **Confirmed source risk:** cancellation stops the process but does not invalidate `_activeRequest.id`, stop the batch timer, or clear its buffered text. The chunk handler checks ID equality without rejecting cancelled/completed states. [Assistant:542](../../services/Assistant.qml#L542), [Assistant:686](../../services/Assistant.qml#L686) | Finalize cancellation once; invalidate the active generation token; stop/clear buffered work; mark its message stopped. Accept chunks only in waiting/streaming states for that generation. |
| U03 · P1 | **Confirmed source risk:** after a provider fails partway through a response, the outer provider loop can start the next provider using the same request and existing text. Provider `start` does not clear/separate the partial answer. [API:857](../../scripts/assistant_api.py#L857), [Assistant:554](../../services/Assistant.qml#L554) | Track attempt IDs as well as request IDs. Retry automatically only before visible output, or explicitly replace/separate a partial attempt. Never join two providers' answers. |
| U04 · P2 | **Confirmed:** stream completion can report success without requiring any usable text or checking why generation ended. [API:186](../../scripts/assistant_api.py#L186), [API:874](../../scripts/assistant_api.py#L874) | Distinguish completed, empty, blocked, truncated and interrupted results. Preserve readable partial text and provide an appropriate action. |
| U05 · P1 | **Confirmed:** saving settings reruns the current action whenever `activeAction` is set, regardless of save exit status. Settings controls trigger “Saved” feedback immediately. [Assistant:739](../../services/Assistant.qml#L739), [Profile:350](../../modules/assistant/ProfileView.qml#L350) | A settings save should report its actual result and never send a question implicitly. Offer Retry explicitly after fixing a failed request. |
| U06 · P2 | **Confirmed:** Retry restores action/prompt/selection but resolves thread, mode, preferences and memory again. [Assistant:701](../../services/Assistant.qml#L701), [Assistant:1318](../../services/Assistant.qml#L1318) | Keep an immutable request snapshot, including context manifest. Retry the same question predictably; make an intentional context change visible. Avoid accumulating duplicate user bubbles. |
| U07 · P2 | **Confirmed:** unfocused clipboard polling can replace the selection, cancel the request and clear the thread. [Assistant:473](../../services/Assistant.qml#L473), [Assistant:504](../../services/Assistant.qml#L504) | Capture when invoked or explicitly requested. If watching is retained, show new text as an available attachment without discarding the conversation. |
| U08 · P2 | **Source risk:** one HUD is instantiated per screen, but visibility/focus/close handlers update shared flags and cancel the shared request. [Floating:14](../../modules/assistant/AssistantFloating.qml#L14) | Define one active assistant window/request owner or aggregate visibility centrally. Closing another monitor's HUD must not cancel the active one. Test on a second monitor. |

## UI changes worth making

| Current | Proposed |
|---|---|
| Header contains many badges and several navigation icons | Title/chat name, New chat, a clearly labeled view/menu entry, Close. Provider details remain available without occupying the whole header. |
| Context preview competes with the answer | A compact attachment row; expand it to inspect the full text. Show whether it will be sent. |
| “Personal on” is broad and opaque | A compact “Context: Auto” control with a detail list of selected sources and a way to exclude one. Its exact policy follows [02](02-assistant-context-and-intelligence.md). |
| Action strip remains prominent during conversation | Keep text actions near an attached selection; give conversation the main space once a chat starts. |
| Single-line question input | A composer that grows to a few lines, then scrolls. Enter sends; Shift+Enter inserts a line, with IME composition handled correctly. |
| Error text may appear both as a message and an error panel | One message-scoped error with Retry/Copy where useful; keep previous conversation visible. |
| Routine Done/metrics chips occupy the footer | Show active progress and actionable failures; put diagnostic counts and latency in details. |
| Multiple tiny message actions compete with the answer | Keep Copy easy to find; group speech/save-to-memory and secondary actions. Make keyboard focus and accessible names explicit. |

Do not add a large review modal to every request. The earlier user feedback clearly favors a compact HUD and reviewable, gradual improvements.

## Acceptance checks

- Cancel before the first chunk, during a batch, and immediately before completion. No subsequent event updates the answer or writes it as a completed turn.
- Start request B after A; delayed A chunk/exit events cannot fail or overwrite B.
- Fail the primary provider after emitting text; fallback cannot append an unrelated answer to the partial output.
- Change a provider setting or key: exactly zero chat requests until an explicit send/retry action.
- Close and reopen the HUD; drafts and partial answers follow an explicit policy. Closing another screen's window does not affect the active request.
- Scroll upward during streaming; the viewport stays there. A visible “latest” action returns to the end.
- Run these with a fake local worker first, without sending private data or consuming provider requests.

**Files:** `services/Assistant.qml`, `scripts/assistant_api.py`, `modules/assistant/{AssistantHUD,AssistantFloating,MessageActionBar,ProfileView}.qml`. Layout fixes are owned by [01](01-layout-and-design.md), context selection by [02](02-assistant-context-and-intelligence.md).
