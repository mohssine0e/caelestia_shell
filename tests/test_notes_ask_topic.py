import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import notes_backend as notes


class AskTopicTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp.name) / 'notes.sqlite3'
        self.env = mock.patch.dict(os.environ, {'CAELESTIA_NOTES_DB': str(self.db_path)})
        self.env.start()
        note = notes.create_note({'raw_content': 'docker ps lists running containers'})['note']
        with notes.database() as db:
            db.execute("""UPDATE notes SET topic='Docker', subconcept='Overview',
                category='technical', essentials_json=?, content_locked=1 WHERE id=?""",
                (json.dumps(['I use docker ps to list running containers.']), note['id']))
        self.base_id = note['id']

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def test_answer_only_keeps_notes_unchanged_and_sends_section(self):
        reply = json.dumps({'answer': 'It lists running containers.', 'suggestions': []})
        before = notes.get_note({'id': self.base_id})['note']['content_revision']
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')) as provider:
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'What is this section missing?'})
        self.assertEqual(result['answer'], 'It lists running containers.')
        self.assertEqual(result['suggestions'], [])
        self.assertEqual(notes.get_note({'id': self.base_id})['note']['content_revision'], before)
        self.assertEqual(len(notes.list_notes({})['notes']), 1)
        context = json.loads(provider.call_args.args[1])
        self.assertEqual(context['question'], 'What is this section missing?')
        self.assertEqual(context['notes'][0]['id'], self.base_id)
        self.assertIn('docker ps', context['notes'][0]['content'])
        self.assertEqual(context['notes'][0]['section'], '')

    def test_incomplete_provider_json_is_retried_without_changing_notes(self):
        valid = json.dumps({'answer': 'Images are also useful to explain.', 'suggestions': []})
        with mock.patch.object(notes, '_run_provider', side_effect=[
                ('{"answer": "incomplete', 'gemini'), (valid, 'gemini')]) as provider:
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'What is missing?'})
        self.assertEqual(result['answer'], 'Images are also useful to explain.')
        self.assertEqual(provider.call_count, 2)
        self.assertEqual(len(notes.list_notes({})['notes']), 1)

    def test_many_proposals_are_optional_and_separate_from_fill_gaps(self):
        suggestions = [
            {'action': 'add', 'kind': 'bullet', 'subconcept': 'Overview', 'section': 'notes',
             'content': f'I inspect Docker behavior number {index}.'}
            for index in range(7)
        ]
        reply = json.dumps({'answer': 'Here are several useful additions.', 'suggestions': suggestions})
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')):
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'Add the missing details.'})
        self.assertEqual(len(result['suggestions']), 7)
        self.assertEqual(notes.learning_list({'topic': 'Docker'})['suggestions'], [])
        self.assertEqual(len(notes.list_notes({})['notes']), 1)
        payload = {'topic': 'Docker', 'subconcept': 'Overview', 'source': 'ask',
                   'request_id': result['request_id']}
        notes.dismiss_gap(dict(payload, id=result['suggestions'][0]['id']))
        accepted = notes.accept_all_topic_lines(payload)
        self.assertEqual(len(accepted['changed_ids']), 6)
        self.assertEqual(len(notes.list_notes({})['notes']), 7)
        notes.undo_topic_lines(dict(payload, ids=accepted['changed_ids']))
        self.assertEqual(len(notes.list_notes({})['notes']), 1)

    def test_diagram_is_previewed_then_saved_only_after_accept(self):
        diagram = {'title': 'Container lookup', 'caption': 'A conceptual path.',
                   'nodes': [{'id': 'cli', 'label': 'Docker CLI'}, {'id': 'daemon', 'label': 'Daemon'}],
                   'layers': [['cli'], ['daemon']], 'edges': [{'from': 'cli', 'to': 'daemon'}]}
        reply = json.dumps({'answer': 'The CLI asks the daemon.', 'suggestions': [
            {'kind': 'diagram', 'action': 'add', 'subconcept': 'Overview', 'section': 'notes',
             'content': 'The CLI asks the daemon.', 'diagram': diagram}]})
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')):
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'Add a diagram to my notes.'})
        self.assertEqual(len(notes.list_notes({})['notes']), 1)
        suggestion = result['suggestions'][0]
        self.assertEqual(json.loads(suggestion['diagram_json']), diagram)
        saved = notes.accept_topic_line({'topic': 'Docker', 'subconcept': 'Overview',
            'source': 'ask', 'request_id': result['request_id'], 'id': suggestion['id']})
        self.assertEqual(len(saved['changed_ids']), 1)
        diagram_note = next(n for n in notes.list_notes({})['notes'] if n['id'] != self.base_id)
        self.assertEqual(diagram_note['diagrams'], [diagram])
        self.assertEqual(diagram_note['essentials'], [])
        self.assertEqual(diagram_note['raw_content'], 'The CLI asks the daemon.')

    def test_wrong_replacement_target_is_ignored(self):
        reply = json.dumps({'answer': 'I would fix one point.', 'suggestions': [
            {'kind': 'bullet', 'action': 'replace', 'subconcept': 'Overview', 'section': 'notes',
             'content': 'A correction.', 'target_note_id': 'made-up', 'target_key': 'essential:0'}]})
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')):
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'Correct the point.'})
        self.assertEqual(result['suggestions'], [])
        self.assertEqual(len(notes.list_notes({})['notes']), 1)

    def test_valid_replacement_preserves_capture_and_can_be_undone(self):
        original = notes.get_note({'id': self.base_id})['note']
        reply = json.dumps({'answer': 'This wording is clearer.', 'suggestions': [
            {'kind': 'bullet', 'action': 'replace', 'subconcept': 'Overview', 'section': 'notes',
             'content': 'I use docker ps to see currently running containers.',
             'target_note_id': self.base_id, 'target_key': 'essential:0'}]})
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')):
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'Make this explanation clearer.'})
        self.assertEqual(len(result['suggestions']), 1)
        payload = {'topic': 'Docker', 'subconcept': 'Overview', 'source': 'ask',
                   'request_id': result['request_id'], 'id': result['suggestions'][0]['id']}
        accepted = notes.accept_topic_line(payload)
        changed = notes.get_note({'id': self.base_id})['note']
        self.assertEqual(changed['raw_content'], original['raw_content'])
        self.assertEqual(changed['display_edits']['essential:0'],
                         'I use docker ps to see currently running containers.')
        notes.undo_topic_lines(dict(payload, ids=accepted['changed_ids']))
        self.assertEqual(notes.get_note({'id': self.base_id})['note']['display_edits'], {})

    def test_remove_proposal_hides_one_entry_but_preserves_source_and_undo(self):
        original = notes.get_note({'id': self.base_id})['note']
        reply = json.dumps({'answer': 'This line can be removed.', 'suggestions': [
            {'kind': 'bullet', 'action': 'remove', 'subconcept': 'Overview', 'section': 'notes',
             'target_note_id': self.base_id, 'target_key': 'essential:0',
             'reason': 'It repeats another point.'}]})
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')):
            result = notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                                      'question': 'Remove redundant lines from my notes.'})
        self.assertEqual(len(result['suggestions']), 1)
        payload = {'topic': 'Docker', 'subconcept': 'Overview', 'source': 'ask',
                   'request_id': result['request_id'], 'id': result['suggestions'][0]['id']}
        accepted = notes.accept_topic_line(payload)
        changed = notes.get_note({'id': self.base_id})['note']
        self.assertEqual(changed['raw_content'], original['raw_content'])
        self.assertEqual(changed['hidden_entries'], ['essential:0'])
        self.assertEqual(notes._topic_context('Docker', 'Overview')[0]['facts'], [])
        notes.undo_topic_lines(dict(payload, ids=accepted['changed_ids']))
        self.assertEqual(notes.get_note({'id': self.base_id})['note']['hidden_entries'], [])
        self.assertEqual(notes.get_note({'id': self.base_id})['note']['content_revision'],
                         original['content_revision'])

    def test_ask_includes_entire_section_even_when_large(self):
        extra = 'Docker layer cache detail ' + 'x' * 28000
        with notes.database() as db:
            db.execute('UPDATE notes SET essentials_json=? WHERE id=?',
                       (json.dumps([extra]), self.base_id))
        reply = json.dumps({'answer': 'The section is long.', 'suggestions': []})
        with mock.patch.object(notes, '_run_provider', return_value=(reply, 'gemini')) as provider:
            notes.ask_topic({'topic': 'Docker', 'subconcept': 'Overview',
                             'question': 'Summarize this section.'})
        request = json.loads(provider.call_args.args[1])
        self.assertIn(extra, request['notes'][0]['content'])


if __name__ == '__main__':
    unittest.main()
