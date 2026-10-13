#!/usr/bin/env python3
"""Commit messages wrap by default and retain their original Git payload."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
MESSAGE = ('Keep the commit message readable when the panel is narrow, preserve every word, '
           'and leave the stored message intact. ') * 3
MESSAGE = MESSAGE.rstrip()


class CommitWrap(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-commit-wrap-')
        self.home = Path(self.tmp.name).resolve()
        self.repo = self.home / 'repo'
        self.repo.mkdir()
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        config = self.home / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        # The main editor's wrap preference has no effect on commit messages.
        config.write_text('[editor]\nword_wrap = false\n[ui]\nagents_panel = false\n'
                          '[updates]\ncheck = false\n', encoding='utf-8')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'a.txt').write_text('changed\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args],
                                       env=self.env, stderr=subprocess.DEVNULL)

    def run_editor(self, actions, size='1000x700'):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(['wait-git', 'cmd git_history', 'wait-git', 'key Return',
                                     'type ' + MESSAGE, *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.repo), '--headless', size,
                                 '--script', str(script)], env=self.env, capture_output=True,
                                text=True, encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def marker_position(self, actions):
        output = self.run_editor([*actions, 'type @', 'print-scm'])
        message = next(line.removeprefix('message=') for line in output.splitlines()
                       if line.startswith('message='))
        self.assertEqual(message.replace('@', ''), MESSAGE)
        return message.index('@')

    def test_navigation_uses_wrapped_rows_by_default(self):
        position = self.marker_position(['key ctrl+Home', 'key Down'])
        self.assertGreater(position, 0)
        self.assertLess(position, len(MESSAGE))
        self.assertEqual(MESSAGE[position - 1], ' ')

    def test_resize_reflows_without_editing_the_message(self):
        wide = self.marker_position(['key ctrl+Home', 'key Down'])
        narrow = self.marker_position(['resize 700 700', 'key ctrl+Home', 'key Down'])
        self.assertLess(narrow, wide)
        self.assertGreater(narrow, 0)

    def test_soft_breaks_do_not_enter_the_commit_payload(self):
        self.run_editor(['key Return', 'key Return', 'type Body with café and β.',
                         'key ctrl+Return', 'wait-git'])
        message = self.git('log', '-1', '--format=%B').decode('utf-8').rstrip('\n')
        self.assertEqual(message, MESSAGE + '\n\nBody with café and β.')


if __name__ == '__main__':
    unittest.main(verbosity=2)
