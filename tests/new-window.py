#!/usr/bin/env python3
"""Open Folder's "Open <folder> in a new window", and a recent folder in the project menu picked with
Shift, start another raftaar with that folder, and this window keeps its project. RAFTAAR_NEW_WINDOW stands in
for the program, and notes what it was given."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()


@unittest.skipIf(os.name == 'nt', 'RAFTAAR_NEW_WINDOW is Unix only; Windows starts raftaar.exe itself')
class NewWindow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-new-window-')
        self.home = Path(self.tmp.name).resolve()
        self.alpha = self.home / 'work/alpha'
        self.beta = self.home / 'work/beta'
        self.alpha.mkdir(parents=True)
        self.beta.mkdir(parents=True)
        (self.alpha / 'a.txt').write_text('a\n', encoding='utf-8')
        self.noted = self.home / 'noted.txt'
        self.program = self.home / 'other-raftaar'
        self.program.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "' + self.noted.as_posix() + '"\n',
                                encoding='utf-8')
        self.program.chmod(0o755)
        config = self.home / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[ui]\nagents_panel = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix(),
                        RAFTAAR_NEW_WINDOW=self.program.as_posix())

    def tearDown(self):
        self.tmp.cleanup()

    def run_editor(self, lines):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.alpha), '--headless', '1000x700',
                                 '--script', str(script)], env=self.env, capture_output=True,
                                text=True, encoding='utf-8', timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def noted_folder(self):
        for _ in range(100):
            if self.noted.exists() and self.noted.read_text(encoding='utf-8'):
                break
            time.sleep(0.05)
        return self.noted.read_text(encoding='utf-8')

    def remember(self, folder):
        """A session of the folder, so the project menu lists it as a recent folder."""
        state = self.home / 'state/raftaar'
        state.mkdir(parents=True, exist_ok=True)
        (state / (folder.as_posix().replace('/', '%') + '.session')).write_text('', encoding='utf-8')

    def test_opens_the_folder_in_another_raftaar(self):
        out = self.run_editor(['cmd open_folder', 'type ../beta/', 'print-palette', 'key Down',
                               'key Return', 'wait 300', 'print-palette', 'print-project'])
        self.assertEqual(out, [
            'field=~/work/alpha/../beta/', '> Open ~/work/beta', '  Open ~/work/beta in a new window',
            'none', 'project=~/work/alpha'])
        self.assertEqual(self.noted_folder(), self.beta.as_posix() + '\n')

    # the project menu (under the project name): its first recent folder at y 168
    def test_shift_click_opens_a_recent_folder_in_another_raftaar(self):
        self.remember(self.beta)
        out = self.run_editor(['cmd open_recent', 'print-menu', 'click 100 168 shift', 'wait 300',
                               'print-project'])
        self.assertEqual(out, ['Open Folder\u2026', 'Open File\u2026', '-', '~/work/beta',
                               'project=~/work/alpha'])
        self.assertEqual(self.noted_folder(), self.beta.as_posix() + '\n')

    def test_a_click_opens_a_recent_folder_here(self):
        self.remember(self.beta)
        out = self.run_editor(['cmd open_recent', 'click 100 168', 'wait 300', 'print-project'])
        self.assertEqual(out, ['project=~/work/beta'])
        time.sleep(0.3)
        self.assertFalse(self.noted.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
