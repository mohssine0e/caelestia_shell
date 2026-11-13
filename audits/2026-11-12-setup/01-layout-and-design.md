# Layout, sizing, and visual design

**Judgment:** the layout needs a shared sizing contract. The current assistant height calculation is useful progress, but it does not prove that every child fits. Runtime logs still show recursive layout rearrangement.

## Current → proposed

| ID / priority | Current evidence | Needed change |
|---|---|---|
| W01 · P1 | **Observed:** chat user-bubble `RowLayout` reports recursive rearrangement. The bubble derives its size from an anchored inner layout, uses a maximum width but no explicit available-width allocation, and adds 12 height pixels for 16 pixels of vertical margins. [HUD:1256](../../modules/assistant/AssistantHUD.qml#L1256) | Resolve available bubble width first; measure wrapped text at that width; include actual padding in height. Keep a single owner of each child's geometry. |
| W02 · P1 | **Confirmed source:** the HUD computes window height from content, animates implicit height, then an 80 ms timer writes live window width/height. Streaming uses a 160 px preferred body, then completion uses full chat content height. Live setters generate deprecation warnings. [HUD:91](../../modules/assistant/AssistantHUD.qml#L91), [Floating:26](../../modules/assistant/AssistantFloating.qml#L26) | Separate desired opening size, actual allocated size, and user-resized size. Hold geometry steady while streaming; grow at deliberate boundaries only. Verify the installed Quickshell behavior before choosing its resize mechanism. |
| W03 · P1 | **Confirmed source:** Tasks is fixed at 1040×720. That exceeds a 1920×1080 monitor's approximate 960×540 logical area at scale 2. [Tasks:15](../../modules/tasks/Tasks.qml#L15) | Clamp to usable logical screen dimensions; switch the commands split view to list/detail navigation when narrow. |
| W04 · P2 | **Source risk:** assistant header combines title, chat title, selection count, provider/latency, and several buttons. Footer badges also occupy a single row. [HUD:320](../../modules/assistant/AssistantHUD.qml#L320), [HUD:1451](../../modules/assistant/AssistantHUD.qml#L1451) | Give the title flexible space and an explicit elision width; move metrics into details. Wrap or collapse secondary controls before hiding essential actions. |
| W05 · P2 | **Confirmed source:** memory's controls viewport uses a `120` floor and a `0.55` fraction of remaining height, alongside a separate card viewport. [MemoryView:337](../../modules/assistant/MemoryView.qml#L337) | Use a compact persistent search/filter row. Put long suggestions/recovery details in an expandable body section with a clear scroll boundary; keep card space predictable. |
| W06 · P2 | **Observed:** Commands tabs place anchored `MouseArea`s directly inside layouts. Profile delegates read the wrong `modelData` type. [Commands:525](../../modules/tasks/CommandsList.qml#L525), [Profile:864](../../modules/assistant/ProfileView.qml#L864) | Wrap clickable tab content in one layout-managed item/control. Declare each delegate's required model properties and reference its own ID. |
| W07 · P2 | **Confirmed source:** Daily Focus uses fixed dark/yellow colors; Commands includes fixed pixel fonts alongside tokens. [DailyFocus:39](../../modules/tasks/DailyFocusBanner.qml#L39), [Commands:507](../../modules/tasks/CommandsList.qml#L507) | Use Caelestia tokens for color, type, padding, radius, focus, and hover. Keep semantic warning/error colors for actual warnings/errors. |
| W08 · P2 | **Source risk:** minimum assistant height depends on non-scrollable controls. If those alone exceed the screen allowance, reducing the chat viewport to zero cannot make the page fit. [HUD:93](../../modules/assistant/AssistantHUD.qml#L93) | Add a compact/short-window layout: collapse optional context first, then scroll the middle content. Essential navigation and composer must fit independently. |
| W09 · P1 | **Source risk:** the maximum window height depends on the minimum height, which depends on the HUD maximum passed back from that same window maximum. This is a circular sizing dependency even when current values settle. [Floating:78](../../modules/assistant/AssistantFloating.qml#L78), [HUD:112](../../modules/assistant/AssistantHUD.qml#L112) | Derive the hard maximum directly from the usable screen area, then derive minimum/preferred sizes from that independent cap. Keep the dependency direction one-way. |

## Shared layout contract

1. Calculate the **usable logical work area** of the window's actual monitor, including reserved edges and a small outer margin. Do not divide an already-logical QML size by scale again.
2. Choose a preferred opening size and clamp it to that area. Existing 640/680 assistant widths can remain starting preferences, not requirements.
3. Allocate header/navigation and composer/footer first. Give the remaining height to content. Measure wrapped text using the actual content width.
4. If essential controls plus a useful content area cannot fit, enter compact mode. Reducing font size is not the default escape hatch.
5. Define scrolling per view: chat list, history list, memory list/detail, profile form, practice question/answer, tasks list, commands detail. Avoid overlapping vertical scroll regions unless their separation is obvious.
6. Respect a user's manual resize until an explicit reset or next-session policy says otherwise. Streaming text should not repeatedly move the window or send button.

Qt recommends that layouts own their children's geometry and that size constraints be expressed with layout properties. Mixing competing geometry rules can cause undefined behavior. [Qt layout guidance](https://doc.qt.io/qt-6/qtquicklayouts-overview.html)

Quickshell exposes window minimum/maximum hints and system resize operations. Its public type documentation alone does not establish a reliable live-content resizing policy for this installed build; test that separately. [FloatingWindow API](https://quickshell.org/docs/v0.3.0/types/Quickshell/FloatingWindow/)

## Visual direction

| Keep | Add/change | Remove from the default view |
|---|---|---|
| Current dark palette, rounded cards, familiar action names | Consistent padding and type scale; stronger primary-action hierarchy; visible keyboard focus | Routine word/token counts, redundant status badges, decorative warning colors |
| Compact assistant and timer | Responsive control rows and stable scrolling | Automatic geometry changes for every content update |
| Rich text and selection | Code scrolling/copy, long-word wrapping, readable Arabic/English mixing | Truncation of primary content without a way to open/read all of it |

## Acceptance checks

- Exercise 1920×1080, 1366×768, and simulated 960×540 logical work areas; fractional scaling and enlarged fonts separately.
- In every assistant view, test empty/loading/error states, long titles, a large recovery notice, many tags, long Arabic text, code, tables, and a long URL.
- Composer, close/back, save, and submit controls remain reachable; all main text is readable by wrapping or scrolling. Labels may elide only when the full value is accessible.
- Repeated opening, switching, resizing, and streaming produces no recursive layout/binding warnings.
- Check monitor offsets/hotplug and window position as well as dimensions. Source sizing formulas are not visual verification.

**Files:** the five assistant view/window files above, `GauntletView.qml`, `modules/tasks/{Tasks,Wrapper,CommandsList}.qml`, `modules/timer/{TimerFloating,TimerMini}.qml`, and a small shared layout helper if extraction proves useful. Coordinate Hyprland placement with [07](07-desktop-integration.md).
