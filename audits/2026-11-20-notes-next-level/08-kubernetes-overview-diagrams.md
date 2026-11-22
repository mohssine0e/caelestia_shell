# Kubernetes Overview and diagram pilot

**Updated:** 2026-11-22. **State:** applied to the active notebook and inspected in Quickshell.

Overview now includes definitions and the complete first learning path: what Kubernetes coordinates; cluster, node, API object, desired state, and reconciliation; API server, etcd, controller manager, scheduler, kubelet, runtime, networking and DNS; then the path from manifest to running Pod and replacement after failure. Short labels at the start of each bullet support quick lookup after the detailed first read. The two original Overview captures and all other Kubernetes raw captures remain unchanged.

Three reviewed diagrams are stored as structured nodes, layers, and edges on their existing notes: the manifest-to-Pod path in Overview, Deployment → ReplicaSet → Pods, and Service → selector → ready Pods. The diagrams open inside the current review window and start collapsed. They use Caelestia palette tokens rather than exported image colors. A copied topic includes a text outline of each diagram, so its relationships remain available outside the QML view. The diagrams are curated examples; AI-generated diagram proposals are a later step and are **not** active.

Implementation: `notes.diagrams_json` is an additive SQLite column. The backend validates size, node IDs, placement, and edge endpoints before returning diagrams to QML. Diagram changes affect unread revisions. Editing a source capture clears its derived diagrams so an old picture cannot misrepresent the new text. [`modules/notes/DiagramCard.qml`](../../modules/notes/DiagramCard.qml) draws the graph natively; [`scripts/enrich_kubernetes_overview.py`](../../scripts/enrich_kubernetes_overview.py) is the one-time, dry-run-by-default content update. It requires the prior reviewed data, checks for user edits, backs up SQLite, and records an idempotent maintenance marker.

## Verification

- A separate SQLite copy rehearsed the pass: four existing notes changed, three diagrams appeared, the second run changed zero, and integrity remained `ok`.
- The live pass produced the same result. Comparison with its backup found **zero changed raw captures**. Backup: `~/.local/share/caelestia/notes/backups/notes_before_k8s_overview_diagrams_20261122T193653Z.sqlite3`.
- The full Python suite passed **223 tests**, including migration, semantic revision, edit invalidation, and malformed graph cases.
- Quickshell was restarted. A live screenshot showed the collapsed diagram above the Overview bullets; a temporary expanded state showed the graph nodes and arrows. The testing state was then removed. The runtime log had no diagram errors after the palette and layout fixes. Synthetic pointer input in this compositor session was unreliable, so the click interaction was not claimed as verified by automation.

## References

- [Kubernetes overview](https://kubernetes.io/docs/concepts/overview/)
- [Kubernetes components](https://kubernetes.io/docs/concepts/overview/components/)
- [Kubernetes objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
