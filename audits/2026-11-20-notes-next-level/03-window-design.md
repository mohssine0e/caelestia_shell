# Window and interaction proposal

## Preserve the useful shape

Keep one floating, draggable review window and the separate capture mode of that same window. Use the existing global theme. The first design should work at the observed **900×620** size, then at **600×400** and larger sizes. This is a content/navigation redesign, not another palette project.

```text
┌──────────────────────────────────────────────────────────────────┐
│ Java   Git   Docker   RabbitMQ…           Search /           ×   │
│ Memory & References   Collections   Concurrency   All…            │
├──────────────────────────────────────────────────────────────────┤
│ ←  Pass-by-value                    Understand | Recall      ⋯  │
│ A method receives a copy of each argument value.                 │
│                                                                  │
│ WHY THIS MATTERS                                                 │
│ The difference between changing an object and replacing a        │
│ local reference explains a common Java debugging surprise.       │
│                                                                  │
│ HOW IT WORKS                                                     │
│ [small reference diagram / short ordered explanation]            │
│                                                                  │
│ EXAMPLE                                      Fragment     Copy  │
│ [code]                                                          │
│ Expected result: …                                              │
│                                                                  │
│ ▸ Why “by value”?    ▸ Compare with…    ▸ Boundaries               │
│ Requires: References       Next: Mutation vs immutability         │
└──────────────────────────────────────────────────────────────────┘
```

The wireframe illustrates navigation and hierarchy, not final pixel placement. Show only sections supported by actual saved content. In Recall, the explanation and diagram collapse; the core rules, example, and critical conditions remain.

## Finding a concept

Topic pills retain stable positions. The second strip groups areas. Clicking an area opens a compact concept index in the main pane: title plus one-line description. Clicking a concept opens its page. **All is an index of concepts grouped by area**, not every fact in a single endless scroll.

Use breadcrumbs/Back within the same pane. No permanent left sidebar. Remember the last concept, view mode, and anchored scroll position per topic. A newly saved concept should not steal focus from the page being read.

At large widths, an optional narrow “On this page” outline can appear; collapse it when the reading column would become cramped. Do not introduce a mandatory second pane.

## Header changes

- Keep topic navigation, search, and close in the top bar. Leave an explicit empty drag region; dragging must not steal text selection or pill clicks.
- Move permanent “AI generate topic…” into the topic-overflow/add action.
- Keep Understand/Recall visible on a concept page. Put Copy page, Sources, Reanalyze, Move, and Delete in the overflow menu.
- Offer one contextual “Fill gaps” action for the current scope. Show accept/dismiss controls next to pending additions, with Accept all only while reviewing that batch.
- Rename “Sync” to “Reanalyze capture” where that is its actual behavior; it is not remote synchronization.

## Search should answer “where is the detail?”

`/` focuses search when no editable field is active. Results show `topic → area → concept`, a matching excerpt, and the match kind (rule, example, command, source). Enter opens the precise block; Esc leaves search before closing the window. Esc dismisses an open inspector first.

Start with local full-text search plus aliases, not an AI request on every keystroke. Examples for acceptance: `pass by reference`, `hashCode`, `computeIfAbsent`, `undo git commit`, `docker logs`. Synonyms should lead to the appropriate concept without rewriting what the user typed. Show raw-source matches too, especially for unprocessed captures.

## Reading and code

Use global typography tokens: approximately 15–16px body, 24–28px concept title, and readable control labels. Keep a comfortable reading width; let code use extra horizontal space when needed. In Recall, reduce unnecessary inter-bullet spacing rather than shrinking text.

Prose wraps by word. Code preserves indentation and supports horizontal scrolling; optionally offer wrapping without changing copied text. On narrow windows, stack a command's explanation below it. Long tokens, references, and pills must not force the window wider or disappear under adjacent controls.

One copy affordance per command or code block. Explain flags in their subcommand context. Distinguish a complete example from a fragment with placeholders. Keep an important state-changing effect beside a command; put secondary details in expansion.

## Updates and suggestions

A dot means **unseen content change**, not merely “updated in the last 24 hours.” Track the saved revision the user has seen. Aggregate dots from blocks to concepts and areas. Opening a topic does not clear every child's unread state.

Clicking an updated concept reveals the changed block with a temporary highlight. Cosmetic reformatting should not mark an entire topic unread. Accepted suggestions appear in their destination section and preserve the reading anchor.

Loading an explanation reserves only a small local space. Failure shows Retry at that block. Existing notes remain readable while offline, during generation, and after provider errors.

## Implementation approach

Extract header/navigation, search results, concept content, code/command block, pending additions, and source inspector into focused QML components. Keep one backend presentation model with stable block IDs. The same model drives display and export.

Use a `ListView` of currently visible blocks with lazy detail loading. Do not keep saved expansion/selection state only inside recycled delegates. Qt documents that delegates can be reused and non-model state must be reset or stored externally. [Qt ListView](https://doc.qt.io/qt-6/qml-qtquick-listview.html)

Measure long-note rendering before and after. Repeater eagerly instantiates delegates, while ListView can create only the needed visible delegates. [Qt Repeater](https://doc.qt.io/qt-6.12/qml-qtquick-repeater.html)

## Visual acceptance

Test at 600×400, 900×620, 1200×800, and non-default display scaling. Check long titles, 200-character unbroken commands, mixed RTL/LTR text, an open inspector, empty search, offline generation, many concepts, and a long Java capture. No hidden close button, clipped control, inaccessible bottom content, or focus hijack. Record the actual supported minimum size and test it rather than adding unrelated hardcoded heights.
