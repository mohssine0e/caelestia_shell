# Performance and architecture

**Judgment:** focus on hidden work, duplicate state ownership and reliable checks. Rewriting everything or shrinking fonts will not make this setup meaningfully lighter.

## What was measured

One active-session `ps` sample reported Quickshell RSS **1,030,968 KiB (~1,007 MiB)** and **4.5% lifetime-average CPU**, after about 15 minutes. This is the whole shell, during normal interaction, not an idle benchmark or proof of a memory leak. No component-level CPU/memory attribution was performed.

Reviewed large components include HUD **1,747 lines**, Profile **1,155**, Commands **1,280**, Assistant service **1,429**, and memory engine **1,712**. Line count alone is not a performance defect; it makes geometry, state and persistence harder to review together.

## Current → proposed

| ID / priority | Current evidence | Needed change |
|---|---|---|
| E01 · P2 | **Confirmed:** assistant/timer loaders use `activeAsync: true` for every screen; tasks content uses `active: true`; HUD creates all subviews even when hidden. [Floating:17](../../modules/assistant/AssistantFloating.qml#L17), [Wrapper:50](../../modules/tasks/Wrapper.qml#L50), [HUD:1713](../../modules/assistant/AssistantHUD.qml#L1713) | Load expensive views on first use, then cache deliberately. Keep durable state/drafts outside disposable views. Measure startup, first-open latency and repeated-open memory before deciding unload policy. |
| E02 · P2 | **Confirmed:** chat already batches at 60 ms, but the full growing Markdown string is rebound as it streams; sizing/scroll callbacks react too. [Assistant:512](../../services/Assistant.qml#L512), [HUD:1164](../../modules/assistant/AssistantHUD.qml#L1164), [HUD:1330](../../modules/assistant/AssistantHUD.qml#L1330) | Preserve batching, isolate updates to the active message, and freeze window geometry during generation. Profile long code/table answers before adding custom Markdown infrastructure. |
| E03 · P2 | **Confirmed:** hidden stopwatch updates at 33 ms; Tasks has an always-running 30-second display timer; Disks has both event monitoring and a 3-second refresh. [FocusTimer:129](../../services/FocusTimer.qml#L129), [Tasks:110](../../modules/tasks/Tasks.qml#L110), [Disks:139](../../services/Disks.qml#L139) | Separate state correctness from display refresh. Gate UI-only work by visibility; reconcile on resume. Reduce disk heartbeat only after checking event coverage and required freshness. |
| E04 · P2 | **Confirmed:** topic heuristics/default profiles exist in multiple layers; the API shadows imported profile helpers; memory has multiple write paths. [Assistant:377](../../services/Assistant.qml#L377), [API:313](../../scripts/assistant_api.py#L313), [API:424](../../scripts/assistant_api.py#L424) | One context policy, one schema per store, one request lifecycle and one coordinated persistence path. QML presents state and sends intent; Python handles provider requests and context assembly. |
| E05 · P2 | **Confirmed:** one successful chat can trigger automatic titling and extraction; extraction includes a projection of every saved memory card. [Assistant:947](../../services/Assistant.qml#L947), [Assistant:1268](../../services/Assistant.qml#L1268), [Engine:610](../../scripts/memory_engine.py#L610) | Use local titles by default; make extraction intentional or governed by explicit background settings. Deduplicate/batch work and retrieve only candidate memories for the extraction topic. |
| E06 · P2 | **Confirmed:** provider/model attempts have individual timeouts, but no shared overall request deadline is apparent; context limits are mostly characters/turns. [API:161](../../scripts/assistant_api.py#L161), [API:857](../../scripts/assistant_api.py#L857) | Bound total latency/retries and total prompt size. Cancel the whole job, including secondary work. Do not equate an 8k output ceiling with a requested answer length. |
| E07 · P1 | **Observed:** `qmllint` returns 255 without diagnostics in this environment; live logs still show real errors. CI covers QML/C++ lint/build, but no assistant request/context regression suite was found. [CI lint](../../.github/workflows/lint.yml), [lint config](../../.qmllint.ini) | Establish a reproducible lint invocation with required imports and exit-code checks. Add small behavior tests for request cancellation, context selection, timer accounting and recovery. Runtime logs are an additional gate. |
| E08 · P2 | **Confirmed:** custom paths point to one home checkout/build; earlier audit/planning Markdown describes different historical states. [shell.qml:2](../../shell.qml#L2), [Assistant:1413](../../services/Assistant.qml#L1413) | Centralize path resolution and document the supported launch/build environment. Date audits and link completed work to commits instead of treating old plans as current specifications. |

## Storage correction

`FileView.setText` is atomic by default. Do not spend a rewrite merely adding another temporary-file wrapper around every QML save. Atomic replacement does **not** solve stale writers, unreadable-data replacement, schema errors, file permissions, or asynchronous save acknowledgement. Those are the actual outstanding storage tasks. [FileView documentation](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/FileView/)

## Proposed boundaries

| Layer | Owns |
|---|---|
| Shared controls/layout helpers | Spacing, focus, accessible actions, available-size rules |
| Assistant views | Rendering, navigation, drafts, scroll position, selected attachments |
| Request coordinator | Request/attempt identity, lifecycle, cancellation, immutable request snapshot |
| Context builder + providers | Relevant source selection, budget, trust separation, transport, structured result events |
| Durable stores | Schema, recovery, revisions, writes, source links, retention |
| Hyprland integration | Window placement/workspace policy and monitor transitions |

Extract boundaries gradually while fixing the associated bug. Avoid a general framework or new long-running service before measurements justify it.

## Verification targets

- Record comparable idle, assistant streaming, long-history, large-task-list and hidden-stopwatch samples on the same screen/settings.
- Compare cold start versus first-open time; test repeated open/close cycles for retained objects before claiming a leak.
- Count provider calls and bytes sent for a normal question. Context selection should reduce irrelevant material without losing needed evidence.
- No continuous high-frequency UI work for closed surfaces; no persistent layout warnings; no regression in input responsiveness.
- Keep meaningful behavioral tests offline by default. Broad screenshot checks belong at approved visual milestones.

**Files:** the files referenced above, `services/Memory.qml`, store helpers, shared components and CI configuration as each batch is approved. Keep existing task virtualization, stream batching and recorder reference counting.
