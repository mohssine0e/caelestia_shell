#!/usr/bin/env python3
"""One-time, reviewed depth pass for the six compact Kubernetes subsections.

Dry run by default. Only the exact earlier curated content can be updated; source
captures remain byte-for-byte intact. A database backup precedes the transaction.
"""
import argparse
import json
import sqlite3
import uuid
from datetime import datetime, timezone

try:
    import notes_backend as notes
    import refine_kubernetes_notes as first_pass
except ModuleNotFoundError:
    from scripts import notes_backend as notes
    from scripts import refine_kubernetes_notes as first_pass

KEY = 'kubernetes-practical-depth-2026-11-22'
ROOT = 'https://kubernetes.io/docs/'

DETAILS = {
    'What Kubernetes manages': [
        'Kubernetes manages containerized applications across a cluster of machines.',
        'The name means “helmsman” or “pilot” in Greek; K8s counts the eight letters between K and s.',
        'I declare a desired state; controllers keep working to bring the observed state closer to it.',
        'I use it when I need replicas, recovery, controlled updates, and stable access across machines—not just a way to run one container.'
    ],
    'How the cluster is organized': [
        'kubectl and controllers use the API server; etcd stores the cluster’s API data, not application files.',
        'Controllers compare desired and observed state and create or update resources when they differ.',
        'The scheduler assigns unscheduled Pods to suitable nodes; the kubelet on each node asks its container runtime to run them.',
        'The control plane can span multiple machines for availability. Worker nodes run application Pods.'
    ],
    'What a Pod groups together': [
        'A Pod, like a pea pod, groups one or more containers scheduled together on one node. One container per Pod is common.',
        'I add a sidecar only when containers must cooperate closely and share the same Pod lifecycle.',
        'Containers in a Pod share an IP address and port space, so they can reach each other through localhost; declared volumes can also be shared.',
        'A failed container may restart inside its Pod. If the Pod itself is lost, a controller can create a replacement with a new identity and IP.',
        'A bare Pod does not replace itself after node failure; I normally use a Deployment for a long-running, interchangeable application.',
        'Labels let Services and controllers select Pods. A Service selector must match the intended Pod labels.',
        'Readiness controls whether a Pod receives Service traffic; liveness can restart an unhealthy container. A declared containerPort alone does not expose it.'
    ],
    'Run and update replicated Pods': [
        'I use a Deployment for interchangeable replicas. A StatefulSet fits Pods that need stable identity or persistent storage.',
        'A Deployment owns ReplicaSets; each ReplicaSet maintains the desired number of Pods from a Pod template.',
        'The selector must match the Pod template labels. The template is the blueprint for each new Pod.',
        'Changing the Pod template, such as its image, starts a new ReplicaSet and rolling update. Changing only replicas does not create a new revision.',
        'Readiness tells a Service when new Pods can receive traffic during a rollout.',
        'If I roll back a bad live revision, I also update my saved manifest or Git source so a later apply does not bring the bad image back.'
    ],
    'Reach changing Pods through a Service': [
        'Pod IPs change as Pods are replaced. A Service gives clients a stable name and virtual IP for a matching group of Pods.',
        'The Service selector matches Pod labels; EndpointSlices track the current backing network endpoints.',
        'With cluster DNS enabled, a Pod can reach nginx-service in the same namespace, or nginx-service.<namespace> from another namespace.',
        'port is the Service port; targetPort is the Pod’s receiving port. In our example, Service port 80 forwards to container port 80.',
        'Readiness affects which Pods receive normal Service traffic; an unready Pod is removed from the Service’s ready endpoints.',
        'I use ClusterIP for internal traffic, NodePort for direct node-port access, and LoadBalancer when an external load-balancer integration exists.'
    ],
    'When Kubernetes pulls an image': [
        'An image reference names a registry/repository plus a tag or digest. A tag is a movable name; a digest identifies exact content.',
        'imagePullPolicy controls when the kubelet asks the container runtime to pull an image.',
        'Always: contact the registry on each start to resolve the image; cached layers can still be reused.',
        'IfNotPresent: use a local image when present; otherwise pull it. Never: require a local image or startup fails.',
        'If omitted at object creation, :latest or no tag defaults to Always; other tags and digests default to IfNotPresent.',
        'Changing an image tag later does not change the pull policy already stored on the object.',
        'I pin a digest when reproducibility matters; a mutable tag can make replicas run different image contents over time.',
        'A private registry may need imagePullSecrets or node-level credentials. If a pull fails, I inspect Pod events and the image name.'
    ],
    'Know which cluster and namespace I am inspecting': [
        'I check the current kubeconfig context before changing resources; the same name can exist in several clusters or namespaces.',
        'Namespaced commands use the context’s namespace, or default when none is set. I use -n <namespace> to be explicit.',
        'I start with get pods, then describe the failing Pod for conditions and events, then inspect logs.',
        'Pending can mean scheduling or setup is blocked; describe and events show the specific reason.',
        'ImagePullBackOff points to a failed image pull. CrashLoopBackOff points to repeated container restarts; logs --previous may show the last crash.',
        'For a multi-container Pod, I use -c <container> with logs or exec. exec needs a running container and an installed executable.',
        'I use get events -n <namespace> when I need the sequence of cluster decisions around that resource.'
    ],
}

POD_CODE = '''apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx-pod  # Separate from the Deployment example
spec:
  containers:
    - name: nginx
      image: nginx:stable  # Mutable example tag; use a digest for reproducibility
      ports:
        - containerPort: 80  # Metadata; this does not expose the Pod
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 2  # Example value; tune to actual startup time'''

COMMANDS = [
    ('Deployments', 'Roll back the live Deployment', 'kubectl rollout undo deployment/nginx-deployment',
     'Restore the previous rollout revision on the live Deployment; update the saved manifest too.',
     'concepts/workloads/controllers/deployment/', 65),
    ('Inspect & debug', 'Check the active cluster context', 'kubectl config current-context',
     'Show which kubeconfig context kubectl currently uses.',
     'reference/kubectl/generated/kubectl_config/kubectl_config_current-context/', 115),
    ('Inspect & debug', 'Read recent cluster events', 'kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp',
     'Show namespace events in creation order; describe gives the events for one Pod.',
     'tasks/debug/debug-application/debug-running-pod/', 145),
    ('Inspect & debug', 'Read the previous container instance', 'kubectl logs <pod-name> --previous',
     'Read logs from the previous terminated container instance, when one exists.',
     'reference/kubectl/generated/kubectl_logs/', 155),
]


def expected_id(item):
    if item['id']:
        return item['id']
    return str(uuid.uuid5(uuid.NAMESPACE_URL, first_pass.KEY + '/' + item['title']))


def preflight(db):
    marker = db.execute("SELECT 1 FROM sqlite_master WHERE name='notes_maintenance'").fetchone()
    if not marker or not db.execute('SELECT 1 FROM notes_maintenance WHERE key=?', (first_pass.KEY,)).fetchone():
        raise ValueError('The six-section Kubernetes review must be applied first.')
    if db.execute('SELECT 1 FROM notes_maintenance WHERE key=?', (KEY,)).fetchone():
        return False
    baseline = {item['title']: item for item in first_pass.ITEMS}
    for title in DETAILS:
        item = baseline[title]
        row = db.execute('SELECT * FROM notes WHERE id=? AND deleted_at IS NULL', (expected_id(item),)).fetchone()
        if (row is None or row['topic'] != 'Kubernetes' or row['subconcept'] != item['subconcept']
                or json.loads(row['essentials_json'] or '[]') != json.loads(item['essentials_json'])
                or json.loads(row['excerpts_json'] or '[]') != json.loads(item['excerpts_json'])
                or json.loads(row['display_edits_json'] or '{}') != {} or not row['content_locked']):
            raise ValueError(f'{title} has changed since review. No detail pass was applied.')
    return True


def run(apply=False):
    with notes.database() as db:
        if not preflight(db):
            return {'changed': 0, 'message': 'The detail pass was already applied.'}
    if not apply:
        return {'update': len(DETAILS), 'add_commands': len(COMMANDS),
                'sections': list(dict.fromkeys(x[0] for x in COMMANDS))}
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = notes.database_path().parent / 'backups' / f'notes_before_k8s_details_{stamp}.sqlite3'
    backup.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(notes.database_path()) as source, sqlite3.connect(backup) as target:
        source.backup(target)
    backup.chmod(0o600)
    baseline = {item['title']: item for item in first_pass.ITEMS}
    changed_ids = []
    with notes.database() as db:
        db.execute('BEGIN IMMEDIATE')
        if not preflight(db):
            return {'changed': 0, 'message': 'The detail pass was already applied.'}
        for title, bullets in DETAILS.items():
            item = baseline[title]
            note_id = expected_id(item)
            excerpts = json.loads(item['excerpts_json'])
            if title == 'What a Pod groups together':
                excerpts[0]['content'] = POD_CODE
            db.execute('UPDATE notes SET essentials_json=?, excerpts_json=?, formatted_content=?, updated_at=? WHERE id=?',
                       (json.dumps(bullets, ensure_ascii=False), json.dumps(excerpts, ensure_ascii=False),
                        '\n'.join('- ' + line for line in bullets), notes.utc_now(), note_id))
            changed_ids.append(note_id)
        for section, title, command, explanation, doc, order in COMMANDS:
            note_id = str(uuid.uuid5(uuid.NAMESPACE_URL, KEY + '/' + title))
            now = notes.utc_now()
            db.execute('''INSERT INTO notes
                (id,created_at,updated_at,raw_content,formatted_content,topic,topic_locked,
                 category,keep_decision,status,origin,title,technical_type,subconcept,topic_section,
                 essentials_json,excerpts_json,reference_url,content_locked,display_order,schema_version)
                 VALUES (?,?,?,?,?,'Kubernetes',1,'technical','keep','formatted','curated',?,
                         'command',?,'commands',?,?,?,1,?,?)''',
                       (note_id, now, now, command, explanation, title, section,
                        json.dumps([explanation], ensure_ascii=False),
                        json.dumps([{'language': 'bash', 'content': command}], ensure_ascii=False),
                        ROOT + doc, order, notes.SCHEMA_VERSION))
            changed_ids.append(note_id)
        db.execute('INSERT INTO notes_maintenance(key,applied_at) VALUES (?,?)', (KEY, notes.utc_now()))
        notes.sync_notes_json(db)
    for note_id in changed_ids[-len(COMMANDS):]:
        notes.sync_legacy_notes_rpc({'id': note_id})
    return {'changed': len(changed_ids), 'updated': len(DETAILS), 'added_commands': len(COMMANDS),
            'backup': str(backup)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    print(json.dumps(run(parser.parse_args().apply), indent=2))
