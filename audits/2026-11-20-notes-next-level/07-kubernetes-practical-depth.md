# Kubernetes notes: practical depth pass

**Updated:** 2026-11-22. **State:** applied to the active notebook, tested, and inspected in the live Notes window.

The six-section layout remains compact. This pass adds the detail needed to explain a concept to myself without replacing the short bullets with long articles. The additions follow the learning path: desired state and control-plane roles; Pod sharing, replacement, labels and probes; Deployment templates, rollout and rollback; Service discovery and port mapping; image identity and pull behavior; then a concrete debugging sequence. The Pod YAML remains collapsed and now includes an example readiness probe. Four commands were added for rollout undo, checking the current context, ordered events, and previous-container logs.

The one-time script is [`scripts/deepen_kubernetes_notes.py`](../../scripts/deepen_kubernetes_notes.py). It previews by default. `--apply` requires the prior six-section review and checks that the seven target notes still match that reviewed baseline, including empty display edits. It creates a SQLite backup and a maintenance marker before the notebook can be changed again. The script changed seven derived explanations and added four curated command notes. It did not rewrite the earlier captures' `raw_content`.

## Verification

- Before applying, the script succeeded on a separate SQLite copy. Running it again changed zero notes.
- The live run changed 11 derived/new notes, and a second run changed zero. The current notebook has 21 Kubernetes notes across Overview (2), Pods (1), Deployments (6), Services (2), Images (1), and Inspect & debug (9).
- The live database passed `PRAGMA integrity_check`; comparison with the pre-pass backup found **zero changed raw captures**. Backup: `~/.local/share/caelestia/notes/backups/notes_before_k8s_details_20261122T191721Z.sqlite3`.
- The full Python suite passed: **220 tests**. Quickshell was restarted and a screenshot of the opened Overview showed the new bullets, the subsection strip, and no clipped content. The runtime log contained no NotesView error. Other shell components still emit unrelated warnings.

## Reference points

- [Kubernetes overview and name](https://kubernetes.io/docs/concepts/overview/)
- [Cluster components](https://kubernetes.io/docs/concepts/overview/components/)
- [Pods](https://kubernetes.io/docs/concepts/workloads/pods/) and [probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) and [rollout undo](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_undo/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Images and pull policies](https://kubernetes.io/docs/concepts/containers/images/)
- [Debug running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
