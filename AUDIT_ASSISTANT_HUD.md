# Assistant HUD Audit

**Goal:** Make the floating assistant a fast, trustworthy reading companion that explains selected text, supports follow-up questions, and helps save useful knowledge.

| Area | Before this implementation | Issue | Suggested improvement |
|---|---|---|---|
| Header and navigation | Chat, provider, profile, history, memory, and window controls share a compact header. | Crowded; important actions compete for attention. | Simplify the header; group less-used destinations in a menu. |
| Window layout | Fixed widths and content-driven height. | Can feel cramped or clipped on smaller displays or with long content. | Adapt dimensions to the screen; scroll long sections and keep the composer accessible. |
| Reading replies | Markdown replies use small text; code appears in the same reading flow. | Long explanations and code are hard to scan or copy. | Increase text and spacing; style code blocks distinctly and add code-copy controls. |
| Selection context | Selected text can be previewed and used for actions. | It is not always clear what text is included or truncated. | Show a concise source preview and clearly indicate what will be sent. |
| Action choice | Actions include translate, explain, summarize, rephrase, and examples. | Some require a selection but are offered without one; recommendations use simple heuristics. | Always offer **Ask**; enable selection actions only when applicable; recommend an action with a short reason. |
| Request review | The user can review request context before sending. | Draft or chat state can be cleared before approval; cancel may lose work. | Preserve the draft and conversation until **Send**; **Cancel** should discard only the pending request. |
| Closing the HUD | Active requests are canceled on close. | A pending review can remain and reappear later. | Clear pending reviews when closing or starting a new chat. |
| Clipboard recovery | Error view offers a clipboard capture action. | The action may do nothing while the HUD is open. | Make it a clear, user-triggered one-time capture that works while open. |
| Errors and retry | Errors can replace the chat view. | Conversation context disappears when a request fails. | Keep the chat visible; show the error and retry beside the failed reply. |
| Answer-to-source link | Reply actions use the current selection or prompt. | Saving an older answer can attach the wrong source. | Store each message's original source and use it for copy, follow-up, and memory actions. |
| Context mode | The chip switches between standalone and follow-up modes. | It can show Standalone while the service is set to follow-up without a thread. | Show Standalone when no thread exists; offer Follow-up only when available. |
| Context transparency | Profile, memory, and history can inform requests. | Users cannot easily see which information influenced an answer. | Add a per-answer **Used** disclosure for selection, chat, profile, and memory. |
| Privacy controls | Review shows context categories; API keys and speech have separate flows. | Actual context may be unclear; HUD key fields appear unmasked; speech may use an online service. | Show the content to be sent, mask keys, and disclose online speech with a local option where available. |
| Learning flow | Replies can be copied, spoken, and saved to memory. | The HUD offers few relevant next steps after an answer. | Offer optional **Simpler**, **Show an example**, **Quiz me**, and **Save as a card** actions. |

## Recommended order

| Priority | Work | Main files |
|---|---|---|
| 1. Reliability | Preserve drafts; clear stale reviews; fix clipboard capture, errors, and source tracking. | `modules/assistant/AssistantHUD.qml`, `modules/assistant/AssistantFloating.qml`, `services/Assistant.qml`, `modules/assistant/MessageActionBar.qml` |
| 2. Trust | Show sent context; mask keys; disclose speech behavior; improve safe text handling. | `modules/assistant/AssistantHUD.qml`, `services/Assistant.qml`, `services/Memory.qml`, `scripts/assistant_tts.py` |
| 3. Intelligence | Improve action recommendations and add relevant follow-ups. | `modules/assistant/AssistantHUD.qml`, `services/Assistant.qml`, `scripts/assistant_api.py`, `scripts/assistant_common.py` |
| 4. Visual polish | Simplify navigation; improve typography, code display, and screen adaptation. | `modules/assistant/AssistantHUD.qml`, `modules/assistant/AssistantFloating.qml`, `modules/assistant/README.md` |

## Success checks

- Cancel preserves the draft and conversation; closing leaves no pending review.
- Clipboard capture works when requested, and errors do not hide the chat.
- Every reply action uses that reply's original source.
- Users can see what context will be sent and read the HUD comfortably on smaller screens.

## Implementation plan — 8 November 2026

| Step | Concrete work | Verification | Status |
|---|---|---|---|
| 1 | Stage requests without changing chat or draft; commit on Send; cancel pending review on close/new chat; retry the original request. | Exercise cancel, send, double-send, retry, and new-chat transitions without contacting a provider. | Partially implemented: failed requests retain the thread; retry uses its original source. Review/commit flow is not implemented. |
| 2 | Attach source and prompt to each answer and persist them; keep errors visible inside the conversation; fix explicit clipboard capture. | Check saving/reloading source metadata, failed-turn rendering, and capture with listening disabled. | Partially implemented: source and prompt persist with chat messages and completed requests use a frozen source snapshot. Clipboard capture and full error-state work remain. |
| 3 | Improve action ranking, always provide Ask, correct mode labels and shortcuts, mask setup keys, and use the clipboard API for export. | Test representative prose, code, mixed-language errors, and empty selections; check QML syntax. | Not implemented |
| 4 | Prepare exact optional context before review; persist consent choices; show actual per-answer provenance; disclose speech transport and harden memory transport. | Compare reviewed context with the provider payload; test each opt-out and local speech. | Partially implemented: credentials resolve from Secret Service and request input travels over stdin. Reviewable context consent remains. |
| 5 | Add relevant follow-up suggestions; simplify header; make HUD/review fit the screen; improve code blocks and keyboard navigation. | Review live behavior at several window sizes and exercise keyboard-only navigation. | Not implemented; visual layout was left unchanged. |

Implementation is limited to behavior and data handling. The current visual layout and component structure were left unchanged.

| Important detail | Result |
|---|---|
| Selection and chat | Requests now capture their original text and prompt. A failed topic change does not discard the existing thread before a successful answer. |
| Saved answers | New messages retain source and prompt through chat save/load. Older messages without source metadata cannot safely be saved as cards. |
| Credentials and transport | Credentials are loaded from Secret Service or the private fallback. Request text, thread, memory context, and replacement keys are sent to helper processes over stdin rather than command-line arguments. |
| Cache | Response replay is disabled because the prior cache key omitted thread and memory context. |
| Verification | Python compilation, QML parsing, and `git diff --check` passed. Isolated checks passed for stdin request parsing, secure credential fallback permissions, and metadata-only status output. The live shell reloaded successfully; the assistant message binding errors are gone. |
| Limits | No provider request or visual layout change is included in this pass. Existing ProfileView screen-type warnings remain. |
