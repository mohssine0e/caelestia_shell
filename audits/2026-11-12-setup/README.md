fol# Hyprland + Caelestia setup audit

**Date:** 2026-11-12 · **Reviewed code:** `7798e0fe1f31d769fb92498aa77e247234a8bf7c`

Your setup has useful features worth keeping. The main weakness is inconsistent control of **window size, conversation context, and saved data**. These cause visible messiness, unrelated AI answers, and unreliable behavior. Adding more features before fixing those foundations would increase the problem.

This folder contains recommendations, not implemented changes. Start with the table below; each report stands on its own.

## Reports

| Area | Report | Main decision |
|---|---|---|
| Windows, layout, scaling, visual consistency | [01 — Layout and design](01-layout-and-design.md) | One sizing policy; fixed essential controls; scrollable content. |
| AI relevance, topic mixing, answer length | [02 — Assistant context and intelligence](02-assistant-context-and-intelligence.md) | Select context for the question instead of attaching the whole user profile. |
| Chat interaction, cancellation, streaming | [03 — Assistant behavior and UX](03-assistant-behavior-and-ux.md) | Make each request reliable, then simplify the HUD. |
| Memory, history, profile, practice | [04 — Memory and history](04-memory-history-and-profile.md) | Separate conversation storage, personal preferences, knowledge, and practice. |
| Tasks, habits, notes, command reference | [05 — Tasks](05-tasks-habits-and-commands.md) | Protect data and make the task workspace responsive. |
| Countdown, stopwatch, linked tasks | [06 — Timer](06-timer.md) | Correct time accounting and survive shell restarts. |
| Hyprland, display switching, bar, dashboard, lock | [07 — Desktop integration](07-desktop-integration.md) | Make every window follow predictable desktop behavior. |
| Resource use and maintainability | [08 — Performance and architecture](08-performance-and-architecture.md) | Measure first; reduce hidden work and duplicate ownership. |
| Privacy, storage, voice, lock entry points | [09 — Privacy and security](09-privacy-and-security.md) | Apply privacy choices across every data path. |
| Implementation order and approval checkpoints | [10 — Roadmap](10-roadmap-and-validation.md) | Small reviewable batches with concrete acceptance checks. |

## Work on these first

| Priority | Issue | What the fix should achieve |
|---|---|---|
| P1 | Profile/workspace context enters unrelated questions | “Hi” or a translation does not mention Java, Bash, your editor, or unrelated weaknesses. |
| P1 | Request finalization throws; cancellation is incomplete | Stop stays stopped; a late chunk cannot change the current answer. |
| P1 | Live QML layout warnings remain | No clipped composer/messages or repeated layout rearrangement warnings. |
| P1 | Recovery protection is uneven across saved stores | Unreadable history/tasks are preserved before a replacement can be saved. |
| P1 | Breaks consume task effort; timers disappear on restart | Work time, break time, and remaining estimate stay distinct and recoverable. |
| P1 | Secondary AI jobs and voice have separate privacy paths | Background extraction, titles, speech, and recording follow explicit settings. |
| P1 | Public unlock entry points bypass the normal PAM success path | Review/remove unauthenticated same-session unlock paths; preserve authenticated unlock. |
| P2 | Dense controls and inconsistent colors/spacing | Keep primary actions visible; move occasional actions into details or menus. |
| P2 | Eager views, duplicate writers, oversized components | Lower hidden work and make future changes easier to isolate. |

**P1:** fix before expanding these features. **P2:** next improvement. **P3:** optional later. These are work priorities, not claims of an active security incident.

## What is already good

- Explicit Follow-up and Standalone modes already take precedence over automatic topic guessing.
- Request IDs, explicit request states, stream batching, and adaptive answer-length instructions already exist. They need completion, not replacement from scratch.
- Memory suggestions already require acceptance before becoming saved cards; memory corruption backup/recovery also exists.
- Task and memory lists already use `ListView`; the task model has caching and shared title parsing.
- Caelestia provides reusable typography, colors, controls, per-screen state, and useful upstream components.

## Evidence and limits

Reviewed the custom assistant, tasks, timer, their services/Python helpers, shell entry points, and relevant Hyprland Lua configuration. Bar/dashboard/launcher/notifications/network/recording/lock received a targeted integration review, not an exhaustive review of every upstream component or C++ plugin. Visual recommendations use source structure and the screenshots supplied earlier; no fresh screenshot-based review of all states was performed.

The live setup reported **Hyprland 0.57.2**, **Quickshell 0.3.2**, and one **1920×1080 display at scale 1**. `hyprctl configerrors` returned no errors. Existing shell logs contain assistant layout errors, an assistant process-finalization exception, profile delegate type errors, and Commands view layout warnings. Small-display, multi-monitor, suspend, corruption, provider-failure, and authentication scenarios were not exercised against live user data.

The repository HEAD advanced from `95382279` to `7798e0fe` during this audit. Content hashes taken during the review showed no tracked-file content changes across that transition. Reports describe the reviewed file contents, including the previously uncommitted assistant changes that are now committed.

**Verification correction:** local `qmllint` runs returned **exit 255 with no diagnostics**, including a run with the build import path. Silence was not a successful lint result. The earlier statement that lint passed should not be used as an acceptance gate. Also, `FileView` writes are atomic by default; the remaining problems are recovery, validation, coordination, and save acknowledgement. See [08](08-performance-and-architecture.md).

Private profile files were inspected only for schema and whether Java/Bash references exist; reports contain no keys, conversation text, or personal memory contents. No provider requests, live-data corruption tests, configuration changes, or shell reloads were performed for this audit.
