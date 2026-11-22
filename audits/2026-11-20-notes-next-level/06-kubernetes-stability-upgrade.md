# Kubernetes notes: compact review and stability upgrade

**Updated:** 2026-11-22. **State:** applied to the active notebook and inspected in the live Quick Notes window.

## The reading surface

The familiar topic and subsection strips remain. Kubernetes now has six ordered subsections: **Overview → Pods → Deployments → Services → Images → Inspect & debug**. There is no roadmap or All tab. One subsection is visible at a time. Facts are short bullets; commands have brief explanations and a small copy button; YAML is collapsed under a selectable, clickable title. A long command can be scrolled horizontally and has a full-command hover tooltip.

The 13 prior Kubernetes captures remain verbatim in Sources. Four short notes were added: a Pod example, rollout status, an inspection workflow, and context/namespace rules. The reviewed content corrects the control-plane topology, `kubectl cluster-info` health claim, image pull behavior, and the conditions for reaching NodePort. It distinguishes a live `kubectl set image` change from editing the saved manifest. The six sections use explicit display order; a repeat maintenance run makes no changes.

The one-time content script is [`scripts/refine_kubernetes_notes.py`](../../scripts/refine_kubernetes_notes.py). It previews by default and writes only with `--apply`. It creates a SQLite snapshot before writing and records a maintenance marker so later personal edits cannot be overwritten by a rerun. Original capture text is preserved. Current pre-review snapshot: `~/.local/share/caelestia/notes/backups/notes_before_reviewed_k8s_20261122T142644Z.sqlite3`.

## Fill gaps, corrections and reading markers

**Fill gaps** sends the current subsection's saved facts, commands, snippets and completion facts, plus bounded summaries of other Kubernetes sections. It asks for at most three useful additions or corrections and does not make a second request to force an overview. It ignores duplicate facts and previously dismissed suggestions. A correction shows the old line before acceptance, validates the source revision, and edits only the displayed line. Accept all validates the whole batch before saving. Undo can reverse the last accepted batch while refusing to overwrite a newer edit.

For Kubernetes, the request includes bounded text from fixed official Kubernetes documentation pages. Each proposal must carry one of those URLs and an exact supporting quote. If documentation cannot be loaded, the request reports that error; it does not fabricate a reference. Other topics keep their existing provider path without this documentation requirement. The AI output is a proposal, so the user decides whether to accept it.

**Refresh** reads local saved data; it does not rerun AI triage on every source. Reviewed and accepted notes have `content_locked`; routine triage, formatting and legacy regrouping preserve them. Direct source edits unlock the note. New-content dots use semantic content revisions instead of 24-hour age. A visible note is marked read after a short dwell, and its dot clears. Saving a content change makes it unread again; status retries and timestamp changes do not.

## Verification and limits

- SQLite rehearsal on a separate copy updated 13 captures and added four notes; a second run changed zero. The original captures were byte-identical after the rehearsal. The live run made the same 17 changes and created the snapshot above.
- The full Python suite passed: 220 tests after migration and behavior changes. Tests cover preview scope, correction/undo transaction behavior, stale revisions, private note filtering, lock protection, and unread revisions.
- Quickshell was restarted. A live screenshot showed the six subsections, compact Deployments facts, four commands, and collapsed YAML. A QML warning about a null delegate parent width was found and fixed before the final restart. Automated pointer clicks were unreliable in this compositor session, so tab switching was inspected by rendered states and the backend scope tests rather than claimed as a successful synthetic click.
- A live provider call for **Images** was run against a temporary copy of the notebook. It returned `[]`, so no suggestions were written to the user's data. This is an acceptable response when the subsection is already covered. The parser, local docs retrieval, and preview validation are covered by focused tests.
- The official documentation text is cached for 24 hours; the cache is limited per page. External AI and documentation availability still determine whether Fill gaps can produce proposals. Very long commands remain on one row and require horizontal scroll or the hover tooltip.

## Primary references

- [Kubernetes components](https://kubernetes.io/docs/concepts/overview/components/)
- [Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Images and pull policies](https://kubernetes.io/docs/concepts/containers/images/)
- [Debug running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
