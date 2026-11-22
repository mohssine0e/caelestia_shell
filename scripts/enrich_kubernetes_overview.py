#!/usr/bin/env python3
"""One-time Kubernetes Overview depth and diagram pilot; preview by default.

Only the reviewed, unchanged derived notes are updated. Original captures stay
intact and a SQLite snapshot is made before applying the transaction.
"""
import argparse
import json
import sqlite3
from datetime import datetime, timezone

try:
    import notes_backend as notes
    import deepen_kubernetes_notes as previous
except ModuleNotFoundError:
    from scripts import notes_backend as notes
    from scripts import deepen_kubernetes_notes as previous


KEY = 'kubernetes-overview-diagrams-2026-11-22'

OVERVIEW = {
    'What Kubernetes manages': [
        'Definition — Kubernetes (K8s) is an open-source system for deploying and managing containerized applications across a cluster.',
        'Why it exists — When containers must run across machines, it coordinates placement, replicas, recovery, updates, and access to them.',
        'Name — Kubernetes means “helmsman” or “pilot” in Greek; K8s replaces the eight letters between K and s.',
        'Cluster — A control plane manages the cluster; worker nodes provide the machines on which application Pods run.',
        'Node — One physical or virtual machine registered with the cluster. A Pod is scheduled onto one node at a time.',
        'API object — A saved resource such as a Deployment, Pod, or Service. Metadata identifies it; spec expresses intent; status reports observed state.',
        'Desired state — I declare what should exist, usually in a manifest. Kubernetes continually compares that intent with what exists now.',
        'Reconciliation — Controllers make repeated adjustments until observed state approaches desired state. This is a continuing loop, not a one-time script.'
    ],
    'How the cluster is organized': [
        'API server — The front door for kubectl and components. It validates requests and exposes the Kubernetes API.',
        'etcd — The persistent key-value store for API data and cluster state. It does not hold my container images or application files.',
        'Controller manager — Runs controllers that watch resources through the API and act when actual state differs from desired state.',
        'Scheduler — Chooses a suitable node for a Pod that has not yet been assigned, considering resource needs and placement constraints.',
        'Kubelet — The agent on each node. It observes assigned Pods and asks the container runtime to make their containers run.',
        'Container runtime — Pulls images and starts containers for the kubelet. Kubernetes coordinates it; it does not run images by itself.',
        'Pod networking — The cluster network implementation gives Pods connectivity. A Pod has its own IP; containers within that Pod share it.',
        'Service networking — A typical Service supplies a stable name and virtual address for changing Pods; a headless Service behaves differently.',
        'Cluster add-ons — DNS commonly resolves Service names. The exact networking and DNS implementations depend on the cluster.',
        'Apply flow — kubectl sends a manifest to the API server, which stores the desired object in etcd.',
        'Workload flow — A controller creates the required Pod objects; the scheduler assigns unscheduled Pods to nodes.',
        'Node flow — The kubelet on each assigned node starts the containers and reports status through the API.',
        'Failure flow — If a managed Pod disappears, its controller works toward the requested replica count by creating a replacement Pod.'
    ]
}

DIAGRAMS = {
    'How the cluster is organized': [{
        'title': 'From a manifest to a running Pod',
        'caption': 'Conceptual roles: controllers and the scheduler observe and update through the API server; arrows are not direct network calls.',
        'nodes': [
            {'id': 'manifest', 'label': 'Manifest / kubectl'},
            {'id': 'api', 'label': 'API server'},
            {'id': 'etcd', 'label': 'etcd: saved state'},
            {'id': 'controllers', 'label': 'Controllers: reconcile'},
            {'id': 'scheduler', 'label': 'Scheduler: choose node'},
            {'id': 'assigned', 'label': 'Pod assigned to node'},
            {'id': 'kubelet', 'label': 'Kubelet + runtime'},
            {'id': 'pod', 'label': 'Running Pod'}
        ],
        'layers': [['manifest'], ['api'], ['etcd', 'controllers', 'scheduler'],
                   ['assigned'], ['kubelet'], ['pod']],
        'edges': [
            {'from': 'manifest', 'to': 'api'},
            {'from': 'api', 'to': 'etcd'},
            {'from': 'api', 'to': 'controllers'},
            {'from': 'api', 'to': 'scheduler'},
            {'from': 'scheduler', 'to': 'assigned'},
            {'from': 'assigned', 'to': 'kubelet'},
            {'from': 'kubelet', 'to': 'pod'}
        ]
    }],
    'Run and update replicated Pods': [{
        'title': 'How a Deployment keeps replicas running',
        'caption': 'A changed Pod template creates a new ReplicaSet; the ReplicaSet maintains the requested Pods.',
        'nodes': [
            {'id': 'deployment', 'label': 'Deployment'},
            {'id': 'replicaset', 'label': 'ReplicaSet'},
            {'id': 'pod_a', 'label': 'Pod A'},
            {'id': 'pod_b', 'label': 'Pod B'}
        ],
        'layers': [['deployment'], ['replicaset'], ['pod_a', 'pod_b']],
        'edges': [
            {'from': 'deployment', 'to': 'replicaset'},
            {'from': 'replicaset', 'to': 'pod_a'},
            {'from': 'replicaset', 'to': 'pod_b'}
        ]
    }],
    'Reach changing Pods through a Service': [{
        'title': 'How a Service finds changing Pods',
        'caption': 'The Service keeps its name while ready Pods matching its selector can change.',
        'nodes': [
            {'id': 'service', 'label': 'Service: stable name'},
            {'id': 'selector', 'label': 'Label selector'},
            {'id': 'pod_a', 'label': 'Ready Pod A'},
            {'id': 'pod_b', 'label': 'Ready Pod B'}
        ],
        'layers': [['service'], ['selector'], ['pod_a', 'pod_b']],
        'edges': [
            {'from': 'service', 'to': 'selector'},
            {'from': 'selector', 'to': 'pod_a'},
            {'from': 'selector', 'to': 'pod_b'}
        ]
    }]
}


def target_ids():
    return {item['title']: previous.expected_id(item) for item in previous.first_pass.ITEMS
            if item['title'] in set(OVERVIEW) | set(DIAGRAMS)}


def preflight(db):
    if not db.execute('SELECT 1 FROM notes_maintenance WHERE key=?', (previous.KEY,)).fetchone():
        raise ValueError('The Kubernetes practical-depth pass must be applied first.')
    if db.execute('SELECT 1 FROM notes_maintenance WHERE key=?', (KEY,)).fetchone():
        return False
    for title, note_id in target_ids().items():
        row = db.execute('SELECT * FROM notes WHERE id=? AND deleted_at IS NULL', (note_id,)).fetchone()
        if (row is None or row['topic'] != 'Kubernetes' or not row['content_locked']
                or json.loads(row['essentials_json'] or '[]') != previous.DETAILS[title]
                or json.loads(row['display_edits_json'] or '{}') != {}
                or json.loads(row['diagrams_json'] or '[]') != []):
            raise ValueError(f'{title} has changed since review. No Overview pass was applied.')
    for diagram_list in DIAGRAMS.values():
        if notes._clean_diagrams(diagram_list) != diagram_list:
            raise ValueError('A curated diagram is invalid.')
    return True


def run(apply=False):
    with notes.database() as db:
        if not preflight(db):
            return {'changed': 0, 'message': 'The Overview and diagram pass was already applied.'}
    if not apply:
        return {'expanded_overview_notes': len(OVERVIEW), 'diagrams': len(DIAGRAMS)}
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = notes.database_path().parent / 'backups' / f'notes_before_k8s_overview_diagrams_{stamp}.sqlite3'
    backup.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(notes.database_path()) as source, sqlite3.connect(backup) as target:
        source.backup(target)
    backup.chmod(0o600)
    changed = []
    with notes.database() as db:
        db.execute('BEGIN IMMEDIATE')
        if not preflight(db):
            return {'changed': 0, 'message': 'The Overview and diagram pass was already applied.'}
        for title, note_id in target_ids().items():
            fields = ['diagrams_json=?', 'updated_at=?', 'schema_version=?']
            values = [json.dumps(DIAGRAMS.get(title, []), ensure_ascii=False), notes.utc_now(), notes.SCHEMA_VERSION]
            if title in OVERVIEW:
                bullets = OVERVIEW[title]
                fields += ['essentials_json=?', 'formatted_content=?']
                values += [json.dumps(bullets, ensure_ascii=False), '\n'.join('- ' + x for x in bullets)]
            db.execute('UPDATE notes SET ' + ','.join(fields) + ' WHERE id=?', (*values, note_id))
            changed.append(note_id)
        db.execute('INSERT INTO notes_maintenance(key,applied_at) VALUES (?,?)', (KEY, notes.utc_now()))
        notes.sync_notes_json(db)
    return {'changed': len(changed), 'expanded_overview_notes': len(OVERVIEW),
            'diagrams': len(DIAGRAMS), 'backup': str(backup)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    print(json.dumps(run(parser.parse_args().apply), indent=2))
