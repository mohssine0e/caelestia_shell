# Assistant Audit

**Scope:** Audit of the restored `2ca4cf5` checkout and follow-up fixes in the current working tree. Runtime behavior, network traffic, and on-disk permissions have not been tested.

## Summary

The assistant combines clipboard capture, local conversation/history/profile/memory storage, and requests to external AI providers. The highest-priority fixes below are now implemented in the working tree. The remaining suggestions focus on persistent preferences, exact context inspection, and third-party TTS disclosure.

## Implemented fixes

- **Sensitive IPC now uses stdin.** API keys, profile JSON, chat-title input, assistant request text/thread/context, and speech text are no longer placed in their launching process argument lists. Quickshell `Process.stdinEnabled` and `write()` carry payloads; the Python script reads a JSON line. See [services/Assistant.qml](services/Assistant.qml), [scripts/assistant_api.py](scripts/assistant_api.py), and [scripts/assistant_tts.py](scripts/assistant_tts.py).
- **Credential and assistant JSON writes are atomic and private.** The shared writer creates mode-`0600` files, replaces them atomically, and backs up malformed JSON before replacing it. Config, profile, history, chats, and memory writes use it. See [scripts/assistant_common.py](scripts/assistant_common.py).
- **Clipboard capture now starts off.** Users must turn it on in the assistant HUD; the existing toggle controls capture for the current shell session.
- **Every uncached provider request now opens a review panel.** It displays the prompt text, destination preference and fallback behavior, and switches for conversation turns, memory cards, prior history, assistant profile, learner profile, and workspace context. The user can cancel or send. Chat-title generation is also disclosed in the panel.
- **Malformed history/chat/memory data is backed up before save.** Missing history/chat/memory files are no longer initialized by writing `[]` at load time. Profile and settings saves no longer automatically trigger a new request. Saved provider keys can be explicitly removed from Profile settings.
- **Speech text no longer appears in process arguments.** The TTS script reads text from stdin, and the local `espeak-ng` fallback receives text through stdin too.

These are source changes only. They still need runtime verification in Quickshell, especially stdin delivery, the review overlay layout, storage permissions, and corrupt-file recovery.

## Original findings and status

### API keys are passed as process arguments — fixed in working tree

`Assistant.qml` invokes `assistant_api.py save_config` with the Gemini and Groq keys in the argument list ([services/Assistant.qml:708](services/Assistant.qml#L708)). Process arguments may be visible to other processes running as the same user. The configuration is saved at `~/.config/caelestia/assistant.json` ([assistant_common.py:18](scripts/assistant_common.py#L18)); this source review did not establish the resulting file permissions.

Keys now travel through stdin; settings JSON is atomically written with mode `0600`, and Profile settings include explicit remove-key controls. A dedicated operating-system credential store remains a possible next step.

### Clipboard capture is enabled by default — fixed in working tree

Clipboard listening defaults to `true` and runs a polling timer while watching and while the assistant window is inactive ([services/Assistant.qml:201](services/Assistant.qml#L201), [services/Assistant.qml:413](services/Assistant.qml#L413)). Captured clipboard text is retained in the assistant state and may be sent to a provider when an action is run.

Capture now defaults to off and can be enabled from the HUD. The request review displays the selected text and provider before sending. A persistent capture indicator and a one-click clear action remain useful UI improvements.

### Sensitive assistant data is passed through process arguments — fixed in working tree

Chat title generation passes up to 500 characters of the prompt and answer as arguments ([services/Assistant.qml:942](services/Assistant.qml#L942)). Other subprocess call sites should be audited for the same pattern.

Prompt, thread, title, profile, config, and TTS payloads now travel over stdin. Process arguments contain executable paths and action names.

### Request context can include multiple private sources — partially fixed

The API script assembles selected text, conversation thread, learner profile, profile, workspace context, extra context, and recalled history before making a provider request ([scripts/assistant_api.py:680](scripts/assistant_api.py#L680)). A user may not realize all those sources are included in a request.

The pre-send panel identifies each source and has per-request switches. The selected text, custom prompt, and conversation turns are shown. The UI does not yet expand and show the exact contents of memory cards, profiles, history recall, or workspace context.

### History and profile parsing and saving need recovery safeguards — partially fixed

Assistant history and chats are loaded from JSON. Parse errors replace the in-memory value with an empty list ([services/Assistant.qml:113](services/Assistant.qml#L113)); some profile writes overwrite their destination directly ([scripts/assistant_common.py:118](scripts/assistant_common.py#L118)). A later save could replace recoverable data with an empty dataset. The source does not consistently surface parse or write errors.

Writes are now atomic and mode `0600`; malformed files are backed up before a save replaces them. The UI still needs clear load/save error feedback, retention controls, and broader data export/deletion management.

### Privacy and consent controls are fragmented — partially fixed

The HUD has clipboard controls and action selection ([modules/assistant/AssistantHUD.qml:646](modules/assistant/AssistantHUD.qml#L646)), but the source review did not find a complete review step that summarizes the data sources and provider before network submission.

The review panel shows provider preference, fallback behavior, prompt text, and context-source controls. There is no local-only model path in this implementation, and exact profile/memory/workspace content is not yet displayed.

## New recommendations

1. Expand each optional context source in the review so users can inspect the actual profile, memory snippets, recalled history, and workspace context, not just enable or disable them.
2. Persist the clipboard opt-in choice and show an always-visible capture state; add a dedicated clear-selection action.
3. Audit environment-based API keys: they remain available to the assistant process through inherited environment variables and may be exposed through shell/session configuration.
4. Document that clicking Read Aloud sends answer text to Edge TTS when online; offer an explicit online/offline speech choice. This was revealed while auditing subprocess payloads and is not currently covered by the request review.
5. Add visible storage errors and retention/export/delete controls for chats, history, profile, and memory.
6. Evaluate an OS credential store for API keys and re-check file modes on the target installation.

## Verification still needed

- Check that Quickshell delivers stdin payloads correctly for API requests, config/profile writes, history/chat/memory saves, title generation, and TTS.
- Inspect actual permissions on all assistant data files and corruption backups after creation and save.
- Observe provider requests to confirm the context toggles control exactly what is transmitted for each action.
- Check cancellation behavior and confirm a canceled review sends no request and leaves no staged conversation entry.
- Verify that Read Aloud's Edge TTS network behavior is made clear to users.
