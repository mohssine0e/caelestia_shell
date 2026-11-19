"""Voice regression checks. No microphone, clipboard or network access."""
import io
import fcntl
import time
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import voice_transcribe as voice


def audio_file(path, sample=1000):
    with wave.open(str(path), 'wb') as audio:
        audio.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
        audio.writeframes(struct.pack('<h', sample) * 16000)


class TranscriptionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.audio = Path(self.temp.name) / 'record.wav'
        audio_file(self.audio)

    def test_uses_shared_credentials(self):
        with patch.object(voice, 'load_config', return_value={'groq_key': 'private-groq', 'gemini_key': 'private-gemini'}):
            self.assertEqual(voice.load_keys(), ('private-groq', 'private-gemini'))

    def test_rejects_unfinalized_wav(self):
        self.audio.write_bytes(self.audio.read_bytes()[:-200])
        with self.assertRaisesRegex(ValueError, 'finalized'):
            voice.validate_audio(self.audio)

    def test_silence_never_calls_provider(self):
        audio_file(self.audio, sample=0)
        with patch.object(voice, 'load_keys') as keys:
            self.assertEqual(voice.transcribe(self.audio), '')
            keys.assert_not_called()

    def test_no_speech_is_not_retried_as_an_error(self):
        with patch.object(voice, 'load_keys', return_value=('g', 'm')), \
             patch.object(voice, 'transcribe_groq', return_value=''), \
             patch.object(voice, 'transcribe_gemini') as fallback:
            self.assertEqual(voice.transcribe(self.audio), '')
            fallback.assert_not_called()

    def test_provider_failure_uses_fallback(self):
        with patch.object(voice, 'load_keys', return_value=('g', 'm')), \
             patch.object(voice, 'transcribe_groq', side_effect=TimeoutError()), \
             patch.object(voice, 'transcribe_gemini', return_value='Bonjour'):
            self.assertEqual(voice.transcribe(self.audio), 'Bonjour')

    def test_english_audio_is_not_left_as_arabic_text(self):
        with patch.object(voice, 'load_keys', return_value=('g', 'm')), \
             patch.object(voice, 'transcribe_groq', side_effect=['مرحبا', 'Hello']) as groq, \
             patch.object(voice, 'detect_spoken_language', return_value='en'):
            self.assertEqual(voice.transcribe(self.audio), 'Hello')
            self.assertEqual(groq.call_args.args[2], 'en')

    def test_genuine_arabic_speech_keeps_arabic_transcript(self):
        with patch.object(voice, 'load_keys', return_value=('g', 'm')), \
             patch.object(voice, 'transcribe_groq', return_value='مرحبا') as groq, \
             patch.object(voice, 'detect_spoken_language', return_value='ar'):
            self.assertEqual(voice.transcribe(self.audio), 'مرحبا')
            self.assertEqual(groq.call_count, 1)

    def test_french_speech_corrects_arabic_misclassification(self):
        with patch.object(voice, 'load_keys', return_value=('g', 'm')), \
             patch.object(voice, 'transcribe_groq', side_effect=['مرحبا', 'Bonjour']) as groq, \
             patch.object(voice, 'detect_spoken_language', return_value='fr'):
            self.assertEqual(voice.transcribe(self.audio), 'Bonjour')
            self.assertEqual(groq.call_args.args[2], 'fr')

    def test_api_failure_is_reported_without_secret_url(self):
        error = urllib.error.HTTPError('https://example.com/?key=SECRET', 401, 'SECRET', {}, None)
        with patch.object(voice, 'load_keys', return_value=('g', '')), \
             patch.object(voice, 'transcribe_groq', side_effect=error), \
             patch.object(voice, 'transcribe_offline', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'HTTP 401') as result:
                voice.transcribe(self.audio)
            self.assertNotIn('SECRET', str(result.exception))

    def test_real_short_utterances_are_not_blacklisted(self):
        response = io.BytesIO(json.dumps({'text': 'Merci.', 'segments': [{'no_speech_prob': 0.01}]}).encode())
        with patch.object(voice.urllib.request, 'urlopen', return_value=response) as request:
            self.assertEqual(voice.transcribe_groq(self.audio, 'test'), 'Merci.')
            self.assertIn(b'whisper-large-v3-turbo', request.call_args.args[0].data)
            self.assertIn('/audio/transcriptions', request.call_args.args[0].full_url)

    def test_gemini_skips_missing_model_and_thought_parts(self):
        error = urllib.error.HTTPError('https://example.com', 404, 'missing', {}, None)
        response = io.BytesIO(json.dumps({'candidates': [{'content': {'parts': [
            {'text': 'private reasoning', 'thought': True}, {'text': 'مرحبا'}]}}]}).encode())
        with patch.object(voice, 'GEMINI_CANDIDATE_MODELS', ['old', 'current']), \
             patch.object(voice.urllib.request, 'urlopen', side_effect=[error, response]):
            self.assertEqual(voice.transcribe_gemini(self.audio, 'test'), 'مرحبا')


class ToggleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = {**os.environ, 'HOME': str(self.base), 'XDG_RUNTIME_DIR': str(self.base),
                    'VOICE_TEST_ROOT': str(self.base), 'PATH': f'{self.bin}:/usr/bin:/bin'}
        self.script = self.base / 'voice_type.sh'
        shutil.copyfile(ROOT / 'scripts/voice_type.sh', self.script)
        (self.base / 'voice_transcribe.py').write_text('''import os,sys,wave
from pathlib import Path
p=Path(os.environ['VOICE_TEST_ROOT'])
with wave.open(sys.argv[1]) as w:
 assert w.getnframes()==16000, 'WAV not finalized'
if os.environ.get('VOICE_FAIL'):
 print('Groq: API key rejected (HTTP 401)',file=sys.stderr); sys.exit(1)
if os.environ.get('VOICE_SWITCH'): (p/'focus').write_text('other')
print('Bonjour مرحبا test')
''')
        self.stub('pw-record', '''import signal,sys,time,wave
path=sys.argv[-1]
open(path,'wb').close()
def stop(*args):
 time.sleep(.12)
 with wave.open(path,'wb') as w:
  w.setparams((1,2,16000,0,'NONE','not compressed')); w.writeframes(b'\\x01\\x01'*16000)
 sys.exit(0)
signal.signal(signal.SIGINT,stop)
while True: time.sleep(.05)
''')
        self.stub('notify-send', '''import os,sys
from pathlib import Path
with (Path(os.environ['VOICE_TEST_ROOT'])/'notifications').open('a') as f: f.write(' '.join(sys.argv[1:])+'\\n')
''')
        self.stub('wpctl', "print('Volume: 0.6')\n")
        self.stub('hyprctl', '''import os,json
from pathlib import Path
p=Path(os.environ['VOICE_TEST_ROOT'])/'focus'
print(json.dumps({'address':p.read_text() if p.exists() else 'original','class':'test-editor'}))
''')
        self.stub('wl-copy', '''import os,sys
from pathlib import Path
p=Path(os.environ['VOICE_TEST_ROOT'])
if '--clear' in sys.argv:
 (p/'clip').unlink(missing_ok=True); (p/'mime').unlink(missing_ok=True)
else:
 (p/'clip').write_bytes(sys.stdin.buffer.read()); (p/'mime').write_text(sys.argv[sys.argv.index('--type')+1])
''')
        self.stub('wl-paste', '''import os,sys
from pathlib import Path
p=Path(os.environ['VOICE_TEST_ROOT'])
if not (p/'clip').exists(): sys.exit(1)
if '--list-types' in sys.argv: print((p/'mime').read_text())
else: sys.stdout.buffer.write((p/'clip').read_bytes())
''')
        self.stub('wtype', '''import os,sys
from pathlib import Path
p=Path(os.environ['VOICE_TEST_ROOT'])
if os.environ.get('VOICE_PASTE_FAIL'): sys.exit(1)
(p/'pasted').write_bytes((p/'clip').read_bytes())
if os.environ.get('VOICE_COPY_DURING_PASTE'): (p/'clip').write_bytes(b'new user copy')
''')
        self.state = self.base / 'caelestia-voice'

    def stub(self, name, code):
        p = self.bin / name
        p.write_text('#!/usr/bin/python3\n' + code)
        p.chmod(0o755)

    def tearDown(self):
        pidfile = self.state / 'recorder.pid'
        if pidfile.exists():
            try: os.kill(int(pidfile.read_text()), signal.SIGTERM)
            except (ProcessLookupError, ValueError): pass
        self.temp.cleanup()

    def run_toggle(self):
        return subprocess.run(['bash', str(self.script)], env=self.env, capture_output=True, text=True, timeout=8)

    def start(self):
        result = self.run_toggle()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.state / 'recorder.pid').exists())
        (self.state / 'started').write_text('0')

    def test_finalized_audio_pastes_and_restores_image_clipboard(self):
        original = b'\\x89PNG\\x00\\xffbinary\n\n'
        (self.base / 'clip').write_bytes(original)
        (self.base / 'mime').write_text('image/png')
        self.start()
        result = self.run_toggle()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / 'pasted').read_text(), 'Bonjour مرحبا test')
        self.assertEqual((self.base / 'clip').read_bytes(), original)
        self.assertEqual((self.base / 'mime').read_text(), 'image/png')
        self.assertFalse((self.state / 'recording.wav').exists())
        self.start()  # No inherited flock prevents another recording.

    def test_failure_does_not_paste_or_claim_no_speech(self):
        self.env['VOICE_FAIL'] = '1'
        self.start()
        result = self.run_toggle()
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.base / 'pasted').exists())
        self.assertIn('HTTP 401', (self.state / 'status.log').read_text())
        self.assertFalse((self.state / 'recording.wav').exists())

    def test_focus_switch_copies_without_pasting(self):
        self.env['VOICE_SWITCH'] = '1'
        self.start()
        self.assertEqual(self.run_toggle().returncode, 0)
        self.assertFalse((self.base / 'pasted').exists())
        self.assertEqual((self.base / 'clip').read_text(), 'Bonjour مرحبا test')

    def test_paste_failure_keeps_transcript_available(self):
        self.env['VOICE_PASTE_FAIL'] = '1'
        self.start()
        self.assertEqual(self.run_toggle().returncode, 0)
        self.assertEqual((self.base / 'clip').read_text(), 'Bonjour مرحبا test')

    def test_user_clipboard_change_wins(self):
        self.env['VOICE_COPY_DURING_PASTE'] = '1'
        self.start()
        self.assertEqual(self.run_toggle().returncode, 0)
        self.assertEqual((self.base / 'clip').read_bytes(), b'new user copy')

    def test_busy_invocation_does_not_start_a_second_recorder(self):
        self.state.mkdir()
        with (self.state / 'toggle.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.run_toggle().returncode, 0)
            self.assertFalse((self.state / 'recorder.pid').exists())

    def test_rapid_duplicate_press_does_not_stop_recording(self):
        self.start()
        pid = (self.state / 'recorder.pid').read_text()
        (self.state / 'started').write_text(str(time.time_ns()))
        self.assertEqual(self.run_toggle().returncode, 0)
        self.assertEqual((self.state / 'recorder.pid').read_text(), pid)
        self.assertFalse((self.base / 'pasted').exists())

    def test_failed_recorder_clears_state(self):
        self.stub('pw-record', 'import sys; sys.exit(1)\n')
        self.assertEqual(self.run_toggle().returncode, 1)
        self.assertFalse((self.state / 'recorder.pid').exists())

    def test_muted_microphone_does_not_claim_to_record(self):
        self.stub('wpctl', "print('Volume: 0.6 [MUTED]')\n")
        self.assertEqual(self.run_toggle().returncode, 1)
        self.assertFalse((self.state / 'recorder.pid').exists())

    def test_stale_pid_recovers_without_signalling_unrelated_process(self):
        self.state.mkdir()
        (self.state / 'recorder.pid').write_text(str(os.getpid()))
        self.start()
        self.assertNotEqual(int((self.state / 'recorder.pid').read_text()), os.getpid())


if __name__ == '__main__':
    unittest.main()
