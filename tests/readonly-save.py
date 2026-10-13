#!/usr/bin/env python3
"""Saving a read-only file asks first: Overwrite replaces it and it stays read-only, Cancel leaves it.
Closing or quitting with it modified asks the same after Save; vim's :wa leaves it; Save As and
writable files save as before."""
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
CONFIG = ('[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')
DIALOG = 'focus=5'


@unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root may write any file')
class ReadOnlySave(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-readonly-')
        self.home = Path(self.tmp.name).resolve()
        self.work = self.home / 'work'
        self.work.mkdir()
        self.note = self.work / 'note.txt'
        self.other = self.work / 'other.txt'
        self.note.write_bytes(b'before\n')
        self.other.write_bytes(b'other\n')
        os.chmod(self.note, 0o444)
        self.config = self.home / 'config/raftaar/config'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(CONFIG, encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())

    def tearDown(self):
        for path in self.work.rglob('*'):
            try:
                os.chmod(path, 0o755 if path.is_dir() else 0o644)
            except OSError:
                pass
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def run_editor(self, paths, actions):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(['wait 100', *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), *map(str, paths), '--headless', '1280x800', '--scale', '1',
                                 '--script', script.as_posix()], env=self.env, capture_output=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
        output = result.stdout.decode('utf-8')
        self.assertNotIn('unknown command', output)
        return output.splitlines()

    def assert_read_only(self, path, text):
        self.assertEqual(path.read_bytes(), text)
        self.assertFalse(os.access(path, os.W_OK))
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode) & 0o222, 0)

    def state(self, line, field):
        return dict(part.split('=', 1) for part in line.split() if '=' in part)[field]

    def test_save_asks_and_cancel_keeps_the_file(self):
        lines = self.run_editor([self.note], ['type x', 'cmd save', 'print-state', 'key Escape',
                                              'print-state', 'key ctrl+s', 'print-state', 'key Escape'])
        self.assertIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'dirty'), '1')
        self.assertNotIn(DIALOG, lines[1])
        self.assertEqual(self.state(lines[1], 'dirty'), '1')
        self.assertIn(DIALOG, lines[2])
        self.assert_read_only(self.note, b'before\n')

    def test_overwrite_replaces_it_and_it_stays_read_only(self):
        lines = self.run_editor([self.note], ['type x', 'cmd save', 'key Return', 'print-state',
                                              'print-toast'])
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'dirty'), '0')
        self.assertEqual(lines[1], 'toast=Saved')
        self.assert_read_only(self.note, b'xbefore\n')
        # it asks again next time
        lines = self.run_editor([self.note], ['type y', 'cmd save', 'print-state', 'key Escape'])
        self.assertIn(DIALOG, lines[0])
        self.assert_read_only(self.note, b'xbefore\n')

    def test_writable_files_save_without_asking(self):
        lines = self.run_editor([self.other], ['type x', 'cmd save', 'print-state', 'print-toast'])
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(lines[1], 'toast=Saved')
        self.assertEqual(self.other.read_bytes(), b'xother\n')

    def test_closing_asks_again_after_save(self):
        # Save in the close dialog, then Cancel: the tab stays, modified
        lines = self.run_editor([self.note], ['type x', 'cmd close_tab', 'print-state', 'key Return',
                                              'print-state', 'key Escape', 'print-state'])
        self.assertIn(DIALOG, lines[0])
        self.assertIn(DIALOG, lines[1])
        self.assertEqual(self.state(lines[1], 'tabs'), '1')
        self.assertNotIn(DIALOG, lines[2])
        self.assertEqual(self.state(lines[2], 'tabs'), '1')
        self.assertEqual(self.state(lines[2], 'dirty'), '1')
        self.assert_read_only(self.note, b'before\n')
        # Save, then Overwrite: saved and closed
        lines = self.run_editor([self.note], ['type x', 'cmd close_tab', 'key Return', 'key Return',
                                              'print-state'])
        self.assertTrue(lines[0].startswith('tabs=0'), lines[0])
        self.assert_read_only(self.note, b'xbefore\n')

    def test_quitting_saves_it_after_overwrite(self):
        lines = self.run_editor([self.note], ['type x', 'cmd quit', 'key Return', 'key Escape',
                                              'print-state'])
        self.assertEqual(self.state(lines[0], 'tabs'), '1')
        self.assertNotIn(DIALOG, lines[0])
        self.assert_read_only(self.note, b'before\n')
        # the script ends where the editor quits
        self.run_editor([self.note], ['type x', 'cmd quit', 'key Return', 'key Return', 'wait 100'])
        self.assert_read_only(self.note, b'xbefore\n')

    def test_vim_write_all_leaves_read_only_files(self):
        lines = self.run_editor([self.note, self.other], [
            'cmd toggle_vim', 'type x', 'cmd prev_tab', 'type x', 'type :wa', 'key Return', 'print-toast',
            'print-state'])
        self.assertEqual(lines[0], 'toast=Read-only files were not saved (:w asks to overwrite)')
        self.assertNotIn(DIALOG, lines[1])
        self.assertEqual(self.other.read_bytes(), b'ther\n')
        self.assert_read_only(self.note, b'before\n')

    def test_save_as_onto_a_read_only_file_asks(self):
        other = self.other
        os.chmod(other, 0o444)
        actions = ['type x', 'cmd save_as', 'key ctrl+a', 'type ' + other.as_posix(), 'key Return', 'print-state']
        lines = self.run_editor([self.note], actions + ['key Escape', 'print-state'])
        self.assertIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[1], 'active'), 'note.txt')
        self.assert_read_only(other, b'other\n')
        lines = self.run_editor([self.note], actions + ['key Return', 'print-state'])
        self.assertEqual(self.state(lines[1], 'active'), 'other.txt')
        self.assertEqual(self.state(lines[1], 'dirty'), '0')
        self.assert_read_only(other, b'xbefore\n')
        self.assert_read_only(self.note, b'before\n')

    @unittest.skipIf(os.name == 'nt', 'a folder that takes no new file is POSIX permissions')
    def test_save_as_onto_a_symlink_asks_for_the_file_it_leads_to(self):
        # the link is in a folder that takes no new file; the read-only file it leads to is not
        locked = self.home / 'locked'
        locked.mkdir()
        (locked / 'link.txt').symlink_to(self.other)
        os.chmod(self.other, 0o444)
        os.chmod(locked, 0o555)
        try:
            lines = self.run_editor([self.note], ['type x', 'cmd save_as', 'key ctrl+a',
                                                  'type ' + (locked / 'link.txt').as_posix(), 'key Return',
                                                  'print-state', 'key Return', 'print-state'])
        finally:
            os.chmod(locked, 0o755)
        self.assertIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[1], 'dirty'), '0')
        self.assert_read_only(self.other, b'xbefore\n')
        self.assertTrue((locked / 'link.txt').is_symlink())

    @unittest.skipIf(os.name == 'nt', 'a folder that takes no new file is POSIX permissions')
    def test_a_folder_that_takes_no_new_file_fails_as_before(self):
        # Overwrite could not work there: no question, and the save fails as any other
        os.chmod(self.work, 0o555)
        try:
            lines = self.run_editor([self.note], ['type x', 'cmd save', 'print-state', 'print-toast'])
        finally:
            os.chmod(self.work, 0o755)
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(lines[1], 'toast=Could not save the file')
        self.assert_read_only(self.note, b'before\n')

    def test_vim_write_quit_closes_it_after_overwrite(self):
        lines = self.run_editor([self.note, self.other], [
            'cmd toggle_vim', 'cmd prev_tab', 'type x', 'type :wq', 'key Return', 'print-state', 'key Return',
            'print-state'])
        self.assertIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'tabs'), '2')
        self.assertEqual(self.state(lines[1], 'tabs'), '1')
        self.assertEqual(self.state(lines[1], 'active'), 'other.txt')
        self.assert_read_only(self.note, b'efore\n')

    @unittest.skipIf(not shutil.which('git'), 'needs git')
    def test_vim_write_quit_closes_a_diff_view(self):
        # a diff view is read-only in the editor's own way: :wq has nothing to save and closes it
        env = dict(self.env, GIT_CONFIG_NOSYSTEM='1')
        def git(*args):
            subprocess.run(['git', *args], cwd=self.work, env=env, check=True, capture_output=True)
        git('init', '-q')
        git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'add', 'other.txt')
        git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'one')
        self.other.write_bytes(b'other changed\n')
        self.config.write_text(CONFIG.replace('[git]\nenabled = false\n', '[git]\nenabled = true\n'),
                               encoding='utf-8')
        lines = self.run_editor([self.work, self.other], [
            'wait-git', 'cmd git_changes', 'wait-git', 'print-state', 'cmd toggle_vim', 'type :wq',
            'key Return', 'print-state'])
        self.assertEqual(self.state(lines[0], 'tabs'), '2')
        self.assertEqual(self.state(lines[1], 'tabs'), '1')
        self.assertEqual(self.state(lines[1], 'active'), 'other.txt')

    def test_a_cancelled_quit_saves_the_session_again(self):
        # Cancel in the question after Save stops the quit, so the next quit saves the session again,
        # with the file opened in between
        self.config.write_text(CONFIG.replace('restore_session = false', 'restore_session = true'),
                               encoding='utf-8')
        self.run_editor([self.work, self.note], [
            'type x', 'cmd quit', 'key Return', 'key Escape', 'open ' + self.other.as_posix(),
            'cmd quit', 'key Return', 'key Return', 'wait 100'])
        sessions = list((self.home / 'state').rglob('*'))
        text = b''.join(path.read_bytes() for path in sessions if path.is_file())
        self.assertIn(b'other.txt', text)
        self.assert_read_only(self.note, b'xbefore\n')

    def test_save_as_writes_a_new_file(self):
        copy = self.work / 'copy.txt'
        lines = self.run_editor([self.note], ['type x', 'cmd save_as', 'key ctrl+a',
                                              'type ' + copy.as_posix(), 'key Return', 'print-state'])
        self.assertNotIn(DIALOG, lines[0])
        self.assertEqual(self.state(lines[0], 'active'), 'copy.txt')
        self.assertEqual(copy.read_bytes(), b'xbefore\n')
        self.assert_read_only(self.note, b'before\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
