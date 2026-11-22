"""Semantic revision, scoped preview and safe acceptance regression tests."""
import json
import unittest
from unittest import mock
from tests import test_notes_backend as fixtures
notes = fixtures.notes


class NotesStabilityTest(unittest.TestCase):
    setUp = fixtures.NotesBackendTest.setUp
    tearDown = fixtures.NotesBackendTest.tearDown
    def seed(self, topic='Docker', section='Images'):
        note = notes.create_note({'raw_content': topic + ' image behavior'})['note']
        with notes.database() as db:
            db.execute("UPDATE notes SET topic=?,subconcept=?,essentials_json=?,completions_json=?,category='technical' WHERE id=?",
                       (topic, section, json.dumps(['Always downloads all layers.']), json.dumps(['Tags can change.']), note['id']))
        return notes.get_note({'id': note['id']})['note']

    def generate(self, values, topic='Docker', section='Images', refs=None):
        with mock.patch.object(notes, '_run_provider', return_value=(json.dumps(values), 'test')) as provider, \
                mock.patch.object(notes, 'topic_references', return_value=refs or []):
            result = notes.fill_topic({'topic': topic, 'subconcept': section})
        self.assertEqual(provider.call_count, 1)
        return result['suggestions']

    def correction(self, note, text='Always checks the registry; cached layers can be reused.'):
        return dict(action='replace', kind='bullet', content=text, subconcept='Images',
                    target_note_id=note['id'], target_key='essential:0')

    def test_inventory_includes_completions_and_display_corrections(self):
        note = self.seed()
        notes.edit_topic_entry({'topic':'Docker','note_id':note['id'],'key':'essential:0','value':'Cached layers can be reused.'})
        inventory = notes._topic_context('Docker','Images')[0]
        self.assertIn('Cached layers can be reused.', inventory['content'])
        self.assertIn('Tags can change.', inventory['content'])
        self.assertNotIn('Always downloads', inventory['content'])
        lines = self.generate([dict(content='Tags can change.', kind='bullet')])
        self.assertEqual(lines, [])

    def test_correction_preserves_raw_and_undo_restores_display(self):
        note=self.seed()
        line=self.generate([self.correction(note)])[0]
        payload={'topic':'Docker','subconcept':'Images','id':line['id']}
        result=notes.accept_topic_line(payload)
        current=notes.get_note({'id':note['id']})['note']
        self.assertEqual(current['raw_content'],note['raw_content'])
        self.assertEqual(current['display_edits']['essential:0'],line['content'])
        self.assertTrue(current['content_locked'])
        self.assertEqual(notes.accept_topic_line(payload)['changed_ids'], [])
        notes.undo_topic_lines({'topic':'Docker','subconcept':'Images','ids':result['changed_ids']})
        self.assertEqual(notes.get_note({'id':note['id']})['note']['display_edits'], {})

    def test_accept_all_stale_correction_rolls_back_entire_batch(self):
        note=self.seed()
        self.generate([dict(kind='bullet',content='A digest identifies exact image content.'),self.correction(note)])
        notes.edit_topic_entry({'topic':'Docker','note_id':note['id'],'key':'essential:0','value':'A newer correction.'})
        with self.assertRaisesRegex(ValueError,'changed'):
            notes.accept_all_topic_lines({'topic':'Docker','subconcept':'Images'})
        self.assertEqual(len(notes.list_notes({})['notes']),1)
        self.assertTrue(all(s['state']=='suggested' for s in notes.learning_list({'topic':'Docker'})['suggestions']))

    def test_accept_and_undo_respect_scope(self):
        note=self.seed(); line=self.generate([self.correction(note)])[0]
        with self.assertRaisesRegex(ValueError,'another subsection'):
            notes.accept_topic_line({'topic':'Docker','subconcept':'Pods','id':line['id']})
        result=notes.accept_topic_line({'topic':'Docker','subconcept':'Images','id':line['id']})
        with self.assertRaisesRegex(ValueError,'another subsection'):
            notes.undo_topic_lines({'topic':'Docker','subconcept':'Pods','ids':result['changed_ids']})

    def test_multiple_corrections_same_note_accept_and_undo(self):
        note=self.seed(); other=self.correction(note,'Tags are mutable references.'); other['target_key']='completion:0'
        self.generate([self.correction(note),other])
        result=notes.accept_all_topic_lines({'topic':'Docker','subconcept':'Images'})
        self.assertEqual(len(result['changed_ids']),2)
        notes.undo_topic_lines({'topic':'Docker','subconcept':'Images','ids':result['changed_ids']})
        self.assertEqual(notes.get_note({'id':note['id']})['note']['display_edits'],{})

    def test_undo_does_not_remove_newer_edit(self):
        note=self.seed(); line=self.generate([self.correction(note)])[0]
        result=notes.accept_topic_line({'topic':'Docker','id':line['id']})
        notes.edit_topic_entry({'topic':'Docker','note_id':note['id'],'key':'essential:0','value':'Newer manual correction.'})
        with self.assertRaisesRegex(ValueError,'newer work'):
            notes.undo_topic_lines({'topic':'Docker','ids':result['changed_ids']})

    def test_addition_undo_and_lock_prevent_retriage(self):
        self.seed(); line=self.generate([dict(kind='command',command='docker image inspect <image>',content='Inspect image metadata.')])[0]
        result=notes.accept_topic_line({'topic':'Docker','id':line['id']})
        saved=next(n for n in notes.list_notes({})['notes'] if n['origin']=='ai')
        with mock.patch.object(notes,'_run_provider') as provider:
            reply=notes.triage_note({'id':saved['id']})
        provider.assert_not_called(); self.assertTrue(reply['preserved'])
        notes.undo_topic_lines({'topic':'Docker','ids':result['changed_ids']})
        self.assertEqual(len(notes.list_notes({})['notes']),1)

    def test_seen_markers_compare_semantic_revision(self):
        note=self.seed(); revision=note['content_revision']
        self.assertTrue(note['unread'])
        notes.mark_notes_seen({'notes':[{'id':note['id'],'revision':revision}]})
        with notes.database() as db:
            db.execute("UPDATE notes SET status='format_failed',updated_at='2099-01-01' WHERE id=?",(note['id'],))
        self.assertFalse(notes.get_note({'id':note['id']})['note']['unread'])
        notes.edit_topic_entry({'topic':'Docker','note_id':note['id'],'key':'essential:0','value':'A genuine change.'})
        self.assertEqual(notes.mark_notes_seen({'notes':[{'id':note['id'],'revision':revision}]})['marked'],[])
        self.assertTrue(notes.get_note({'id':note['id']})['note']['unread'])

    def test_references_reject_invented_evidence_and_accept_exact_quote(self):
        self.seed('Kubernetes')
        ref={'url':'https://kubernetes.io/docs/concepts/containers/images/', 'text':'The imagePullPolicy is always set when the object is first created.'}
        base=dict(kind='bullet',content='Pull policy defaults are set at creation.',reference_url=ref['url'], evidence='This is an invented quotation from nowhere.')
        self.assertEqual(self.generate([base],topic='Kubernetes',refs=[ref]),[])
        base['evidence']=ref['text']
        self.assertEqual(len(self.generate([base],topic='Kubernetes',refs=[ref])),1)

    def test_unbounded_suggestions_and_invalid_foreign_targets(self):
        note=self.seed()
        bad=self.correction(note);bad['target_note_id']='nonexistent'
        self.assertEqual(self.generate([bad]),[])
        values=[dict(kind='command',content='Inspect metadata.',command=f'docker inspect example{i}') for i in range(6)]
        self.assertEqual(len(self.generate(values)),6)

    def test_old_maintenance_and_formatting_preserve_curated_note(self):
        note = self.seed()
        with notes.database() as db: db.execute('UPDATE notes SET content_locked=1 WHERE id=?',(note['id'],))
        with mock.patch.object(notes, '_format_with_provider') as provider:
            reply=notes.organize_note({'id':note['id']})
        provider.assert_not_called();self.assertTrue(reply['preserved'])
        notes.refactor_subconcepts({})
        current=notes.get_note({'id':note['id']})['note']
        self.assertEqual(current['subconcept'],'Images')
        self.assertEqual(current['essentials'],['Always downloads all layers.'])

    def test_dismiss_requires_matching_subsection(self):
        note=self.seed();line=self.generate([self.correction(note)])[0]
        with self.assertRaisesRegex(ValueError,'another subsection'):
            notes.dismiss_gap({'topic':'Docker','subconcept':'Pods','id':line['id']})
        self.assertEqual(notes.learning_list({'topic':'Docker','subconcept':'Images'})['suggestions'][0]['state'],'suggested')

    def test_raw_edit_unlocks_curated_content(self):
        note=self.seed()
        with notes.database() as db: db.execute('UPDATE notes SET content_locked=1 WHERE id=?',(note['id'],))
        updated=notes.update_note({'id':note['id'],'raw_content':'docker images changed source'})['note']
        self.assertFalse(updated['content_locked'])


if __name__=='__main__': unittest.main()
