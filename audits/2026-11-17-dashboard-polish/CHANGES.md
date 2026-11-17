# Dashboard polish branch: what was applied

Branch `ui/dashboard-polish`, created from `main` at 713ff0ad. It holds the dashboard and calendar
part of the plan in `audits/2026-11-17-lyrics-ui/PLAN.md` on the `plan/lyrics-ui` branch. The
lyrics work is on that branch, and the assistant work is on `feat/assistant`; neither was touched
here. This branch only changes `modules/dashboard/dash/Calendar.qml` and `modules/dashboard/Dash.qml`,
so it merges independently of both.

Small tweaks only: your colours, fonts and layout stay. Nothing was run inside the shell; every
change was checked by reading the code and by parsing the files with `qmlformat`.

## Applied changes

### Commit 1: `calendar: run qmlformat (formatting only, no behaviour change)`
`Calendar.qml` was the only dashboard file not in the repo's `qmlformat` style (mixed indentation,
one-line `if`s and objects). Whitespace and line breaks only, so the real changes in commit 2 are
easy to read.

### Commit 2: `dashboard: calendar spacing on the 4 px scale, one meaning per colour, matching cards`
Colours, one meaning each:
- primary = today, secondary = weekends and the selected day, tertiary = events.
- Weekend names and dates: `m3tertiary` to `m3secondary`. Before, weekends and event markers were
  both tertiary.
- Selected day: `m3primaryContainer` at 70% to `m3secondaryContainer` at full strength, text
  `m3onSecondaryContainer`. Before, it looked like a faded second "today" next to the primary
  today circle.
- Agenda headings (Today, Tomorrow, dates): `m3primary` to `m3onSurfaceVariant`, so primary stays
  for today.

Spacing, from the theme's tokens instead of loose numbers:
- Weekday row spacing `3` to `Tokens.spacing.extraSmall`.
- Day cell height `padding.small + 4` to `padding.medium`.
- Selection circle inset `- 4` to `- Tokens.padding.extraSmall`.
- Agenda rows: width `- 10` and heights `+ 12` / `+ 10` to `padding.medium` / `padding.small`.
- Agenda fade strip height `18` to `Tokens.spacing.largeIncreased`.
- Event accent bar `3 px` with radius `2` to `4 px` with full rounding.
- Quick-add confirm button padding `2` to `Tokens.padding.extraSmall`.
- Quick-add time field width: `66` to the measured width of "00:00" in its own font plus its
  padding, so it fits at any font scale.

Buttons and cards:
- The close and add buttons in the calendar header now use the same icon size and padding as the
  month arrows, so the four buttons in that row are one size.
- Quick-add box: the lone 1 px `m3outlineVariant` border is removed and the radius goes from
  `rounding.small` to `rounding.medium`, like the other inner surfaces. No other card in the
  dashboard has a border.
- Weather card radius `rounding.extraLarge * 1.5` to `rounding.extraLarge`, like the profile and
  calendar cards beside it.
- Today highlight: vertically centred on the today row instead of placed with a `- 1` px nudge.

## Tests run
- `qmlformat` parses both changed files, and both are in the repo's format.
- `qmllint` (Qt 6.4) found no syntax errors. It cannot resolve Quickshell or the Caelestia plugin
  on this machine, so property names and types against those modules were not checked.
- Existing Python tests (`python3 -m unittest discover -s tests -p "test_*.py"`): all pass. None
  of them covers the dashboard.
- There are no QML tests for the dashboard, and this branch adds none: the changes are visual.

## Not done
- Contrast of the new secondary colours on your wallpapers and schemes.
- No other dashboard, bar or setup files were changed. The other hard-coded sizes I found
  (avatar size in `User.qml`, `topMargin: 5` in `Tabs.qml`) were left alone: changing them would
  move things you set on purpose without a screenshot to compare.

## Check on your PC
1. Open the dashboard tab. Weekend dates and names are in the secondary colour; event dots and
   bars are still tertiary; today is still the primary circle.
2. Click another day: its circle is clearly different from today's, not a faded copy.
3. The four buttons in the calendar header (previous, next, add, close) look the same size.
4. Open quick add: no border, the time field shows "00:00" without clipping, the check button
   looks right.
5. The weather, profile and calendar cards have matching corners.
6. The agenda list spacing looks even, and the event accent bars look right at 4 px.
