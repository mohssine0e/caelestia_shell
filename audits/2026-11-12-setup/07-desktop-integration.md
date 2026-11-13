# Hyprland and desktop integration

**Judgment:** the desktop starts and Hyprland reports no configuration errors. The custom windows still need consistent placement, focus, dismissal, and recovery behavior across the QML shell and external Lua files.

## Concrete findings

| ID / priority | Current evidence | Needed change |
|---|---|---|
| I01 · P2 | **Confirmed:** assistant placement has a static `move = "20 300"` rule and a separate open listener that moves it to right-center. Timer comments describe top-right while its helper centers it. [rules.lua:70](/home/mohssine/.config/hypr/hyprland/rules.lua#L70), [execs.lua:49](/home/mohssine/.config/hypr/hyprland/execs.lua#L49), [functions.lua:91](/home/mohssine/.config/hypr/utils/functions.lua#L91) | Choose one placement owner. Keep size ownership in QML and placement/workspace policy in Hyprland. Reconcile after resize or monitor changes without undoing manual moves. Correct misleading comments. |
| I02 · P2 | **Source risk:** rules match broad `^Assistant.*` / `^Timer.*` titles; helpers choose the active monitor rather than necessarily the window's owning monitor. [rules.lua:57](/home/mohssine/.config/hypr/hyprland/rules.lua#L57), [functions.lua:108](/home/mohssine/.config/hypr/utils/functions.lua#L108) | Match the shell app/class plus exact role/title where supported. Use the owning monitor, its logical work area, offsets and reserved edges. Make cross-workspace pinning a deliberate preference. |
| I03 · P1 | **Confirmed:** display mode selection auto-applies after 1.4 seconds, runs a detached helper, and shows a toast before knowing success. The external helper forces scale 1 and does not implement rollback. [ProjectMenu:94](../../modules/project/ProjectMenu.qml#L94), [display-mode.py:83](/home/mohssine/.config/caelestia/scripts/display-mode.py#L83) | Preserve current monitor settings, apply with a tracked result, and offer a timed Keep/Revert flow backed by a rollback mechanism that survives losing the target screen. Preserve scale/refresh/position unless the selected operation requires a change. |
| I04 · P2 | **Confirmed:** `settings.watchFiles` is false; shell reload shortcuts kill/restart the process. Timer state is currently volatile and lock UI runs inside the shell. [shell.qml:31](../../shell.qml#L31), [keybinds.lua:79](/home/mohssine/.config/hypr/hyprland/keybinds.lua#L79) | Define one reload workflow that checks lock/session state, flushes acknowledged data and restores sessions. Reload after approved code changes; documentation alone needs no reload. |
| I05 · P2 | **Confirmed:** Super+Alt+V invokes voice typing, but its credential loader reads only legacy keys from `assistant.json`, unlike the assistant's environment/keyring/private-file resolver. [keybinds.lua:266](/home/mohssine/.config/hypr/hyprland/keybinds.lua#L266), [voice_transcribe:13](../../scripts/voice_transcribe.py#L13) | Share credential resolution and report the actual configured backend without revealing keys. Verify voice after key migration/clear operations. |
| I06 · P2 | **Confirmed/source risk:** voice typing pastes into whatever window is focused when transcription finishes and restores only nonempty text clipboard content. [voice_type:46](../../scripts/voice_type.sh#L46) | Remember the intended target; require focus continuity or offer the transcript for manual paste. Restore clipboard state carefully and explain clipboard-history retention. |

## Coverage of the other desktop areas

These rows are targeted review recommendations, not claims that every listed component currently fails.

| Area reviewed | Keep / current strength | Next focused check or improvement |
|---|---|---|
| Bar and popouts | Existing per-screen state and token-based controls | Check every popout against reserved edges, narrow monitors, tray-menu focus and hotplug. Apply shared sizing/dismissal rules instead of separate fixes. |
| Dashboard | Existing tabs and scrollable content; upstream tab-index fix is in history | Check long media metadata, unavailable weather, empty players, large fonts and short-screen performance cards. No need to redesign it before custom-window fixes. |
| Launcher | `StyledListView`, bounded shown count, keyboard navigation | Preserve focus and selection after opening/closing tasks/HUD; distinguish empty search from missing external actions. |
| Notifications/sidebar | Existing expanded and collapsed notification bodies | Verify actions and full text remain reachable; unify undo/dismiss patterns. Avoid duplicate timer alerts and private task titles on lock/recording surfaces. |
| Recorder/utilities | Recorder already polls only while referenced and reconciles command exit | Test cancelled region selection and failed recorder start; show confirmed state. Retain this visibility-gated polling pattern. |
| Network/VPN | Existing state models and provider adapters | Distinguish command pending/success/failure; bound retry loops. Replace raw interface interpolation into shell commands with argument-safe handling. See [09](09-privacy-and-security.md). |
| Lock | PAM success flow exists; custom lock card and power UI have been added | Review public unlock entry points separately, test long errors and smaller screens, and protect lock ownership during shell restart. See P04 in [09](09-privacy-and-security.md). |
| Weather | Cached cities, retry handling, configured-location support | Make auto-location understandable; avoid plain HTTP location lookup where that fallback is used. See P08 in [09](09-privacy-and-security.md). |

## Acceptance checks

- Open each surface by mouse and shortcut; Escape/back and outside-click behave consistently and do not destroy drafts.
- Open on monitor B while monitor A was previously focused; move, resize, unplug and reconnect. No offscreen controls or cancellation from unrelated windows.
- Switch workspaces with assistant/timer pinned and unpinned; confirm intended privacy and focus behavior.
- Simulate display-helper failure in an isolated test; show failure, keep a visible display, and revert on timeout.
- Test voice with focus changes and each supported credential backend using synthetic text/audio.
- Preserve lock authentication and recording state during any future reload procedure. No lock/unlock or display-switch tests were executed in this audit.

**Files:** shell entry/shortcuts, `modules/drawers/*`, `modules/project/ProjectMenu.qml`, relevant surface wrappers, voice helpers, and the external Hyprland files linked above. External configuration changes need their own reviewable diff because they are outside this repository.
