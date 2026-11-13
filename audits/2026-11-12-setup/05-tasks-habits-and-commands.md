# Tasks, habits, notes, and command reference

**Judgment:** the task model already has useful nested tasks, duration parsing, keyboard navigation, virtualized rows and caches. Its next improvements should be data protection and a clearer workspace, rather than more controls.

## Current → proposed

| ID / priority | Current evidence | Needed change |
|---|---|---|
| T01 · P1 | **Confirmed:** parse/load errors mark tasks loaded with an empty array; saves are not gated by a healthy-store state. [TaskList:760](../../modules/tasks/TaskList.qml#L760) | Preserve unreadable task/habit data, show recovery status, and block replacement until a backup/recovery decision. Validate nested shapes and IDs before normalization. |
| T02 · P1 | **Confirmed:** Daily Focus seeds example notes (“Deploy staging…”) on missing/invalid data and can save them as user notes. [DailyFocus:63](../../modules/tasks/DailyFocusBanner.qml#L63), [DailyFocus:105](../../modules/tasks/DailyFocusBanner.qml#L105) | Use empty notes with optional placeholders. Preserve corrupt input; never persist sample tasks as the user's real plan. |
| T03 · P1 | **Confirmed:** fixed 1040×720 root plus preferred list heights and expandable notes lack a small-screen layout. [Tasks:15](../../modules/tasks/Tasks.qml#L15), [TaskList:31](../../modules/tasks/TaskList.qml#L31) | Apply the shared sizing contract from [01](01-layout-and-design.md). Clamp notes and filter area; let the task list occupy the remaining space. |
| T04 · P2 | **Source risk:** each screen's eagerly loaded task view owns its own file-backed lists and notes. Multiple screens can hold stale copies of the same files. [Drawers:10](../../modules/drawers/Drawers.qml#L10), [Wrapper:50](../../modules/tasks/Wrapper.qml#L50), [TaskList:760](../../modules/tasks/TaskList.qml#L760) | Keep one durable task/habit/note store shared by views. A view owns selection/filter/editor state, not independent copies of persistent data. |
| T05 · P2 | **Confirmed:** parent/subtask deletion uses double-click interactions, while nested deletion uses a single click. No corresponding undo store was found. [TaskCard:637](../../modules/tasks/TaskCard.qml#L637), [SubtaskCard:469](../../modules/tasks/SubtaskCard.qml#L469), [Nested:289](../../modules/tasks/NestedSubtaskCard.qml#L289) | Use consistent delete actions with undo. Confirm removal of a populated tree when recovery would otherwise be unclear. Show descendant impact. |
| T06 · P2 | **Confirmed source gap:** the timer stores a snapshot task title/ID; task deletion/rename does not reconcile the active timer. [TaskTimerChip:43](../../modules/tasks/TaskTimerChip.qml#L43), [DataManager:598](../../modules/tasks/DataManager.qml#L598) | Resolve task labels from stable IDs and handle deletion/unlinking without losing elapsed effort. Share the timer policy in [06](06-timer.md). |
| T07 · P2 | **Confirmed:** the initial Tasks page is Commands. Commands has its own categories, favorites, banner, navigation and detail pane. [Tasks:87](../../modules/tasks/Tasks.qml#L87), [Commands:498](../../modules/tasks/CommandsList.qml#L498) | Open the last-used page or Tasks by default. Keep Tasks/Habits/Reference as clear destinations; collapse commands navigation when space is limited. |
| T08 · P2 | **Confirmed:** Commands silently ignores malformed data and valid empty arrays; toggling a star writes the entire document. [Commands:29](../../modules/tasks/CommandsList.qml#L29) | Distinguish empty from unreadable, surface load/save status, and store favorites without risking the reference content. Preserve the copy-first interaction. |

## Design and behavior

| Keep | Enhance | Simplify/remove |
|---|---|---|
| Quick capture, nested tasks, `@minutes`, categories, useful keyboard navigation | Show how parsed duration/category/link will be stored; keep rename round-trips predictable | Repeated decorative labels and dense controls on every task |
| Build/avoid habits and completion history | Plain explanation of what a checkbox means for each habit type and when the day resets | Unexplained scores/streaks that compete with the actual habit |
| Daily notes | Compact note preview and a bounded editor; saved/error status | Seeded example content and its special hardcoded theme |
| Commands reference and copy actions | Good search, narrow list/detail mode, consistent tab controls | Overlapping category/favorites navigation when a single filter would work |

The popout currently closes five seconds after pointer leave unless an input has focus. That protects active typing, but can interrupt reading or keyboard navigation. Prefer explicit dismissal while focused or editing; if auto-hide remains, make it optional and preserve drafts/position. [Wrapper:36](../../modules/tasks/Wrapper.qml#L36)

## Acceptance checks

- Existing tasks/habits survive migration, malformed files, permission failures and a restart during a pending save, using copies first.
- Add/rename/reorder/delete nested items while filtered; selection follows stable IDs rather than stale indexes.
- Parent completion reflects children correctly; estimates remain consistent at task/subtask/nested levels.
- Verify build/avoid behavior around the configured 02:00 local reset, suspend/resume and timezone changes. Do not assume timer UTC-day behavior matches habits.
- Delete a populated tree and undo it with order, children, durations and completion history intact.
- Open the workspace on two screens and edit the same list; no silent last-writer overwrite.
- Test small-screen commands navigation, expanded notes, long titles, keyboard-only reading, and pointer leave during editing.

**Files:** `modules/tasks/{Tasks,Wrapper,TasksHeader,TaskList,DataManager,DailyFocusBanner,CommandsList,TaskCard,SubtaskCard,NestedSubtaskCard,TaskTimerChip,TitleParse}.qml/js`, plus the shared store introduced during implementation. Do not replace the existing virtualized list just to restyle it.
