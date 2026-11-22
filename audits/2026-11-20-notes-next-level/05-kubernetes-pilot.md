# Kubernetes note refactor pilot

**Historical pilot:** Current live Kubernetes content and verification are recorded in [06 — Kubernetes stability upgrade](06-kubernetes-stability-upgrade.md).

**Date:** 2026-11-21  
**Capture:** `Kubernetes imagePullPolicy mechanics`  
**State:** first pilot applied to the derived concept view; original capture preserved.

## Baseline found

There is one saved Kubernetes capture and one structured concept. The capture contains a useful image pull policy definition followed by a brief Docker image-layer connection. The legacy note already held two essentials and two completion bullets, but the concept page held only one rule copied from the entire raw sentence. Consequently, the concept page hid the extracted facts and its Fill gaps action proposed the default rule a second time.

The concept also has a separate relation to the Docker image-layer concept. Keep that as a related concept link; it should not be mixed into the Kubernetes definition.

## Pilot changes

- Added an idempotent, **per-note** sync from saved essentials, completions, and exact excerpts into the linked concept blocks.
- Replaced a raw-capture seed block with the concise definition only when it was safe to identify as the untouched seed. The complete original capture remains unchanged in Sources.
- Stored essential facts as Recall-visible blocks; kept completion bullets in Understand detail. The first definition is not copied twice.
- Classified explanatory mechanics separately from rules and kept AI-derived material marked unverified.
- Scoped the sync to the note whose analysis just completed. Multi-concept captures are left alone because one note's bullets cannot safely be assigned to several concepts without a mapping.
- Added local near-duplicate filtering to gap suggestions. It suppresses paraphrases and partial copies of a saved rule while preserving meaningful contrasts such as `Always` versus `Never`.
- Dismissed the generated “why” answer and duplicate default-rule suggestions after review; they were weak or already covered. No generated suggestion was accepted automatically.

The active concept now has one concise primary definition, one explanatory mechanism, and two additional policy rules. The raw capture and its related Docker link remain intact.

The reading UI now labels its legacy `Core Kubernetes` area as **Basics**. With one area, that is the first and only Kubernetes subconcept. The area remains selected directly; there is no “All” tab. Relation data remains in storage, but the related-link pills are hidden from both the topic page and concept detail so they do not take space above the notes. The code presentation now uses collapsed snippets with a single-line language/description header and an icon-only copy action; original captures are available in Sources instead of a per-snippet raw-note button.

## Accuracy check

Kubernetes documents `Always`, `IfNotPresent`, and `Never`; `Always` requests a pull on each launch while the runtime can reuse cached layers, `IfNotPresent` pulls only when the image is absent locally, and `Never` uses only a local image. The documented defaults are `Always` for `:latest` or an omitted tag and `IfNotPresent` otherwise. Kubernetes sets the policy when the object is first created; changing the image tag later does not automatically change the policy. Digests identify immutable image content.

Source: [Kubernetes: Images](https://kubernetes.io/docs/concepts/containers/images/).

The current saved completion bullets correctly state the default mapping but do not yet include the creation-time behavior, the runtime's cached-layer nuance, or what `Never` does when no local image exists. Those are valid future additions to propose after the gap engine sees the full saved content; none has been silently inserted in this pilot.

## Reusable refactor procedure

1. Read the raw capture, extracted essentials/completions/snippets, existing concept blocks, and related concepts together.
2. Preserve the raw capture. Separate unrelated but connected facts into their own concept and retain a relation.
3. Build a concise definition, Recall rules, and deeper mechanisms/examples/caveats. Avoid duplicate paraphrases.
4. Verify version-sensitive technical claims against primary documentation; retain source/evidence status.
5. Stage additions for review. Do not treat “accept” as fact-checking or automatically replace user content.
6. Re-run the operation and verify it is idempotent, scoped to the selected note, and has not changed any raw capture.

This pilot improves the old and future single-concept notes when they are synchronized. It deliberately does not distribute a multi-concept capture or claim that this one note is complete.

## Verification

- Added regression coverage for targeted sync, preserved raw text, source mappings, Recall versus deeper detail, duplicate suppression, and no cross-note mutation.
- Full Python suite result is recorded in `MASTER_PLAN.md` after the implementation run.
- Python regression suite: 208 tests passed; `git diff --check` passed. `qmlformat` also fails without diagnostics on the HEAD versions of both touched QML files, and `qmllint` returns 255 without diagnostics even for unchanged `InlineEntry.qml`; these local tools do not provide a usable syntax verdict here.
- A Quickshell process was not running during this session, so the live window was not reloaded. Reopen Notes to inspect the Basics label, area selection, and collapsed code presentation.
