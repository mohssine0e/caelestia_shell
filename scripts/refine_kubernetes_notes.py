#!/usr/bin/env python3
"""Apply the reviewed, one-time Kubernetes notebook cleanup. Dry run by default.

Original captures are preserved. A SQLite snapshot precedes changes. A maintenance
marker makes reruns harmless, including after the user edits these notes later.
This script never runs as part of schema migration or normal Notes startup.
"""
import argparse
import json
import sqlite3
import uuid
from datetime import datetime, timezone

try:
    import notes_backend as notes
except ModuleNotFoundError:
    from scripts import notes_backend as notes

KEY = 'kubernetes-compact-review-2026-11-22'
ROOT = 'https://kubernetes.io/docs/'
ITEMS = []


def add(note_id, section, title, bullets, path, command=None, code=None, label=None):
    excerpts = ([{'language': 'bash', 'content': command}] if command else
                [{'language': 'yaml', 'content': code, 'label': label or title}] if code else [])
    ITEMS.append(dict(id=note_id, subconcept=section, title=title, essentials_json=json.dumps(bullets, ensure_ascii=False),
                      excerpts_json=json.dumps(excerpts, ensure_ascii=False), reference_url=ROOT + path,
                      technical_type='command' if command else 'code' if code else 'concept',
                      topic_section='commands' if command else 'code' if code else 'notes',
                      display_order=len(ITEMS) * 10,
                      formatted_content='\n'.join('- ' + b for b in bullets)))


add('f96e118f-cd4f-43fb-9f41-3bf3c5a84dd0', 'Overview', 'What Kubernetes manages', [
    'Kubernetes manages containerized applications across a cluster of machines.',
    'I declare a desired state; controllers keep working to bring the observed state closer to it.'
], 'concepts/overview/')
add('a81c5c2b-c4a3-4448-b678-ee50246249ae', 'Overview', 'How the cluster is organized', [
    'The control plane exposes the API, stores cluster state in etcd, schedules Pods, and runs controllers. It can span multiple machines.',
    'Worker nodes run Pods. The kubelet works with a container runtime to keep their containers running.'
], 'concepts/overview/components/')
add(None, 'Pods', 'What a Pod groups together', [
    'A Pod is the smallest deployable unit: one or more containers scheduled together on one node.',
    'Containers in a Pod share its network address and ports; they can also share explicitly configured volumes.',
    'Pods are replaceable. A Deployment creates replacement Pods; a bare Pod has no controller to recreate it on another node.',
    'Labels identify resources. A selector uses those labels to find matching Pods.'
], 'concepts/workloads/pods/', code='''apiVersion: v1
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
        - containerPort: 80  # Describes the port; does not expose it externally''', label='This is how I define one NGINX Pod')
add('37875499-bc47-4b96-873a-96929e92c9f9', 'Deployments', 'Run and update replicated Pods', [
    'A Deployment manages ReplicaSets, which maintain the requested number of Pods.',
    'The selector must match the Pod template labels. Changing the template starts a rollout; changing only replicas does not create a new revision.'
], 'concepts/workloads/controllers/deployment/', code='''apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx  # Must match template.metadata.labels
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:stable  # Example tag; pin a digest for reproducibility
          ports:
            - containerPort: 80''', label='This is how I keep two NGINX Pods running')
add('ce4ef15d-2ad9-440a-a4e0-e8bbdae8e16e', 'Deployments', 'Apply a manifest',
    ['Create or update the resources declared in this file.'], 'concepts/overview/working-with-objects/object-management/', command='kubectl apply -f deployment.yaml')
add('e632ee89-a0d2-4afe-9029-18a2faceff13', 'Deployments', 'Change a live Deployment image',
    ['Change the live Pod template; the YAML file stays unchanged.'], 'concepts/workloads/controllers/deployment/', command='kubectl set image deployment/nginx-deployment nginx=<image:tag>')
add(None, 'Deployments', 'Watch a rollout', ['Wait for the Deployment rollout to complete.'],
    'concepts/workloads/controllers/deployment/', command='kubectl rollout status deployment/nginx-deployment')
add('ebb01de1-7c0d-4b13-8f42-0a6ce0004f98', 'Deployments', 'Delete resources from a manifest',
    ['Delete the listed resources from the cluster; keep the local file.'], 'concepts/overview/working-with-objects/object-management/', command='kubectl delete -f deployment.yaml')
add('a6652696-ce23-48a8-b701-8bccdf34ef77', 'Services', 'Reach changing Pods through a Service', [
    'Pod IPs can change when Pods are replaced. A Service gives clients a stable way to reach a matching group of Pods.',
    'The Service selector matches Pod labels. port is the Service port; targetPort is the receiving port on a Pod.',
    'ClusterIP is the default Service type for cluster-internal access. NodePort also exposes a port on eligible node addresses.'
], 'concepts/services-networking/service/')
add('19a24908-3f0e-486d-8fda-882ca97ad550', 'Services', 'Expose NGINX through NodePort', [
    'With reachable node networking and the port allowed by firewalls, I can use http://<node-ip>:30080. Local clusters may need a tunnel or port mapping.'
], 'concepts/services-networking/service/', code='''apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  selector:
    app: nginx  # Matches the Deployment's Pod labels
  ports:
    - port: 80  # Service port inside the cluster
      targetPort: 80  # NGINX container's listening port
      nodePort: 30080  # Port exposed on eligible node addresses''', label='This is how I expose NGINX through a node port')
add('2a41f368-034b-4937-9f2a-e140f4aa952d', 'Images', 'When Kubernetes pulls an image', [
    'imagePullPolicy controls when the kubelet asks the container runtime to pull an image.',
    'Always: resolve the image through the registry on each start; cached layers can still be reused.',
    'IfNotPresent: use the local image when available; otherwise pull it. Never: use only a local image, or fail.',
    'If omitted at creation, :latest or no tag defaults to Always; other tags and digests default to IfNotPresent.',
    'Changing an image tag later does not automatically change the existing pull policy.',
    'Tags can move to a different image. A digest pins the exact image content.'
], 'concepts/containers/images/')
add(None, 'Inspect & debug', 'Know which cluster and namespace I am inspecting', [
    'kubectl uses the current kubeconfig context. Namespaced commands use its namespace, or default if none is set.',
    'Add -n <namespace> for a specific namespace; use -A on supported list commands to inspect all namespaces.',
    'For a multi-container Pod, use -c <container> with logs or exec. logs --previous reads the previous terminated container instance, when available.',
    'exec needs a running container and an installed executable; minimal images may not include /bin/sh.'
], 'tasks/debug/debug-application/debug-running-pod/')
add('1175512e-f666-4753-9604-f0921187da14', 'Inspect & debug', 'Find cluster endpoints',
    ['Show control-plane and marked service endpoints; not a full health check.'], 'reference/kubectl/generated/kubectl_cluster-info/', command='kubectl cluster-info')
add('853f1f3f-1fb0-45e1-99f2-40e325113603', 'Inspect & debug', 'Inspect node status',
    ['List node readiness, roles, and Kubernetes versions.'], 'reference/kubectl/generated/kubectl_get/', command='kubectl get nodes')
add(None, 'Inspect & debug', 'Find Pods and investigate their status', [
    'List Pods with node placement and IP addresses.',
    'Inspect a Pod’s configuration, conditions, and recent events.'
], 'tasks/debug/debug-application/debug-running-pod/', command='kubectl get pods -o wide\nkubectl describe pod <pod-name>')
add('ad30f13f-d36c-438b-919c-aa32c658ca3b', 'Inspect & debug', 'Read container output',
    ['Read a container’s stdout and stderr logs.'], 'reference/kubectl/generated/kubectl_logs/', command='kubectl logs <pod-name>')
add('a190575c-9c5d-4422-9cb4-e0992a35c9ad', 'Inspect & debug', 'Open a shell inside a container',
    ['Open an interactive shell, if /bin/sh exists in the container.'], 'reference/kubectl/generated/kubectl_exec/', command='kubectl exec -it <pod-name> -- /bin/sh')


def run(apply=False):
    with notes.database() as db:
        exists = db.execute("SELECT 1 FROM sqlite_master WHERE name='notes_maintenance'").fetchone()
        if exists and db.execute('SELECT 1 FROM notes_maintenance WHERE key=?', (KEY,)).fetchone():
            return {'changed': 0, 'message': 'This reviewed cleanup has already been applied.'}
        for item in ITEMS:
            if item['id'] and not db.execute("SELECT 1 FROM notes WHERE id=? AND deleted_at IS NULL AND lower(topic)='kubernetes'", (item['id'],)).fetchone():
                raise ValueError('The notebook differs from the reviewed snapshot. Review it before applying this cleanup.')
    if not apply:
        return {'update': 13, 'add': len(ITEMS)-13, 'sections': notes.KUBERNETES_SECTIONS if hasattr(notes, 'KUBERNETES_SECTIONS') else ['Overview','Pods','Deployments','Services','Images','Inspect & debug']}
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = notes.database_path().parent / 'backups' / f'notes_before_reviewed_k8s_{stamp}.sqlite3'
    backup.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(notes.database_path()) as source, sqlite3.connect(backup) as target:
        source.backup(target)
    backup.chmod(0o600)
    ids = []
    with notes.database() as db:
        db.execute('BEGIN IMMEDIATE')
        for item in ITEMS:
            data = dict(item)
            note_id = data.pop('id')
            if note_id is None:
                note_id = str(uuid.uuid5(uuid.NAMESPACE_URL, KEY + '/' + data['title']))
                raw = data['formatted_content']
                excerpts = json.loads(data['excerpts_json'])
                if excerpts: raw += '\n\n' + excerpts[0]['content']
                db.execute("INSERT INTO notes(id,created_at,updated_at,raw_content,origin,status,topic,category) VALUES(?,?,?,?,'curated','formatted','Kubernetes','technical')",
                           (note_id, notes.utc_now(), notes.utc_now(), raw))
            data.update(topic='Kubernetes', category='technical', status='formatted', keep_decision='keep',
                        content_locked=1, topic_locked=1, completions_json='[]', display_edits_json='{}', updated_at=notes.utc_now())
            db.execute('UPDATE notes SET '+','.join(k+'=?' for k in data)+' WHERE id=?', (*data.values(), note_id))
            db.execute('UPDATE topic_suggestions SET subconcept=? WHERE note_id=?', (data['subconcept'], note_id))
            db.execute('UPDATE concepts SET area=?, title=?, definition=? WHERE legacy_note_id=?',
                       (data['subconcept'], data['title'], json.loads(data['essentials_json'])[0], note_id))
            ids.append(note_id)
        db.execute('CREATE TABLE IF NOT EXISTS notes_maintenance(key TEXT PRIMARY KEY, applied_at TEXT NOT NULL)')
        db.execute('INSERT INTO notes_maintenance VALUES (?,?)', (KEY, notes.utc_now()))
        notes.sync_notes_json(db)
    for note_id in ids:
        notes.sync_legacy_notes_rpc({'id': note_id})
    return {'changed': len(ids), 'preserved_raw_captures': 13, 'backup': str(backup)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    print(json.dumps(run(parser.parse_args().apply), indent=2))
