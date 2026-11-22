"""Diagram storage keeps source edits and note revision semantics correct."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import notes_backend as notes


class DiagramStorageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'notes.sqlite3'
        self.path_patch = patch.object(notes, 'database_path', return_value=self.path)
        self.path_patch.start()

    def tearDown(self):
        self.path_patch.stop()
        self.tmp.cleanup()

    def test_additive_migration_keeps_original_capture(self):
        note = notes.create_note({'raw_content': 'Original Kubernetes capture'})['note']
        with notes.database() as db:
            db.execute('ALTER TABLE notes DROP COLUMN diagrams_json')
            db.execute('PRAGMA user_version=17')
        with notes.database() as db:
            row = db.execute('SELECT raw_content,diagrams_json FROM notes WHERE id=?', (note['id'],)).fetchone()
            self.assertEqual(row['raw_content'], 'Original Kubernetes capture')
            self.assertEqual(row['diagrams_json'], '[]')
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], notes.SCHEMA_VERSION)

    def test_diagram_changes_revision_and_source_edit_clears_it(self):
        note = notes.create_note({'raw_content': 'A Deployment owns ReplicaSets.'})['note']
        diagram = {'title': 'Ownership', 'caption': '',
                   'nodes': [{'id': 'deployment', 'label': 'Deployment'},
                             {'id': 'replicaset', 'label': 'ReplicaSet'}],
                   'layers': [['deployment'], ['replicaset']],
                   'edges': [{'from': 'deployment', 'to': 'replicaset'}]}
        original_revision = note['content_revision']
        with notes.database() as db:
            db.execute('UPDATE notes SET diagrams_json=? WHERE id=?',
                       (json.dumps([diagram]), note['id']))
        enriched = notes.get_note({'id': note['id']})['note']
        self.assertEqual(enriched['diagrams'], [diagram])
        self.assertNotEqual(enriched['content_revision'], original_revision)
        changed = notes.update_note({'id': note['id'], 'raw_content': 'A Deployment manages ReplicaSets.'})['note']
        self.assertEqual(changed['diagrams'], [])
        self.assertEqual(changed['raw_content'], 'A Deployment manages ReplicaSets.')

    def test_malformed_graph_is_ignored(self):
        bad = {'title': 'Bad', 'nodes': [{'id': 'a', 'label': 'A'}],
               'layers': [['a']], 'edges': [{'from': 'a', 'to': 'missing'}]}
        self.assertEqual(notes._clean_diagrams([bad]), [])


if __name__ == '__main__':
    unittest.main()
