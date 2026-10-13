#!/usr/bin/env python3
"""Reset all changes through the same confirmation used by the Git panel."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()


class GitReset(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='raftaar-reset-')
        self.work = Path(self.temporary.name).resolve()
        self.repo = self.work / "repo café ' $test"
        self.repo.mkdir()
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[ui]\nagents_panel = false\n')
        self.env = dict(os.environ, HOME=str(self.work),
                        XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), GIT_CONFIG_NOSYSTEM='1')
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], env=self.env)

    def run_ui(self, lines, start=None):
        script = self.work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n')
        result = subprocess.run([str(EXE), str(start or self.repo), '--headless', '1400x860',
                                 '--script', str(script)], env=self.env, capture_output=True,
                                text=True, timeout=25, check=True)
        return result.stdout

    def commit(self):
        (self.repo / 'a.txt').write_text('original\n')
        (self.repo / 'deleted.txt').write_text('restore me\n')
        (self.repo / 'renamed.txt').write_text('original name\n')
        (self.repo / '.gitignore').write_text('ignored/\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Initial')
        self.head = self.git('rev-parse', 'HEAD')

    def changes(self):
        self.commit()
        (self.repo / 'a.txt').write_text('staged\n')
        self.git('add', 'a.txt')
        (self.repo / 'a.txt').write_text('unstaged\n')
        (self.repo / 'deleted.txt').unlink()
        self.git('mv', 'renamed.txt', 'moved.txt')
        (self.repo / 'added.txt').write_text('staged addition\n')
        self.git('add', 'added.txt')
        folder = self.repo / "new folder café ' $test" / 'nested'
        folder.mkdir(parents=True)
        (folder / 'new.txt').write_text('new file\n')
        (folder / '.hidden').write_text('hidden file\n')
        (self.repo / 'empty').mkdir()
        (self.repo / 'ignored').mkdir()
        (self.repo / 'ignored/keep').write_text('ignored content\n')
        self.outside = self.work / 'outside'
        self.outside.mkdir()
        (self.outside / 'keep').write_text('outside content\n')
        if os.name != 'nt':
            (self.repo / 'link').symlink_to(self.outside, target_is_directory=True)
        (self.repo / 'nested-repo').mkdir()
        subprocess.run(['git', 'init', '-q', str(self.repo / 'nested-repo')],
                       env=self.env, check=True)
        (self.repo / 'nested-repo/keep').write_text('nested repository\n')

    def assert_reset(self):
        self.assertEqual((self.repo / 'a.txt').read_text(), 'original\n')
        self.assertEqual((self.repo / 'deleted.txt').read_text(), 'restore me\n')
        self.assertEqual((self.repo / 'renamed.txt').read_text(), 'original name\n')
        for name in ['added.txt', 'moved.txt', "new folder café ' $test", 'empty', 'link']:
            self.assertFalse(os.path.lexists(self.repo / name), name)
        self.assertEqual((self.repo / 'ignored/keep').read_text(), 'ignored content\n')
        self.assertEqual((self.outside / 'keep').read_text(), 'outside content\n')
        self.assertEqual((self.repo / 'nested-repo/keep').read_text(), 'nested repository\n')
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.head)
        self.assertEqual(self.git('diff'), b'')
        self.assertEqual(self.git('diff', '--cached'), b'')

    def test_button_cancel_and_escape(self):
        self.changes()
        status = self.git('status', '--porcelain')
        for cancel in ['click 910 425', 'key Escape']:
            output = self.run_ui(['wait-git', 'cmd git_history', 'wait-git',
                                  'click 1372 60', 'print-state', cancel, 'print-state'])
            self.assertIn('focus=5 ', output)
            self.assertIn('focus=0 ', output)
            self.assertEqual(self.git('status', '--porcelain'), status)
            self.assertEqual((self.repo / 'a.txt').read_text(), 'unstaged\n')
            self.assertTrue((self.repo / 'empty').is_dir())

    def test_button_resets_staged_unstaged_and_created_paths(self):
        self.changes()
        output = self.run_ui(['wait-git', 'cmd git_history', 'wait-git',
                              'click 1372 60', 'print-state', 'click 810 425',
                              'wait-git', 'print-scm'])
        self.assertIn('focus=5 ', output)
        self.assert_reset()

    def test_command_and_open_file_reload(self):
        self.commit()
        (self.repo / 'a.txt').write_text('modified\n')
        output = self.run_ui(['wait-git', 'open ' + str(self.repo / 'a.txt'),
                              'cmd git_reset_all', 'key Return', 'wait-git', 'wait 500',
                              'print-doc', 'print-scm'])
        self.assertIn('original\n', output)
        self.assertNotIn('modified\n', output)
        self.assertIn('action=none', output)
        self.assertEqual(self.git('status', '--porcelain'), b'')

    def test_unborn_repository(self):
        (self.repo / 'staged.txt').write_text('staged\n')
        self.git('add', '.')
        (self.repo / 'new').mkdir()
        (self.repo / 'new/file').write_text('untracked\n')
        self.run_ui(['wait-git', 'cmd git_reset_all', 'key Return', 'wait-git'])
        self.assertEqual(self.git('status', '--porcelain'), b'')
        self.assertFalse((self.repo / 'staged.txt').exists())
        self.assertFalse((self.repo / 'new').exists())
        self.assertTrue((self.repo / '.git').is_dir())

    def test_empty_untracked_directory(self):
        self.commit()
        (self.repo / 'empty').mkdir()
        self.assertEqual(self.git('status', '--porcelain'), b'')
        self.run_ui(['wait-git', 'cmd git_reset_all', 'key Return', 'wait-git'])
        self.assertFalse((self.repo / 'empty').exists())

    def test_merge_conflicts(self):
        self.commit()
        self.git('checkout', '-qb', 'other')
        (self.repo / 'a.txt').write_text('other branch\n')
        self.git('commit', '-qam', 'Other')
        self.git('checkout', '-q', 'main')
        (self.repo / 'a.txt').write_text('current branch\n')
        self.git('commit', '-qam', 'Current')
        head = self.git('rev-parse', 'HEAD')
        merge = subprocess.run(['git', '-C', str(self.repo), 'merge', 'other'],
                               env=self.env, capture_output=True)
        self.assertEqual(merge.returncode, 1)
        self.run_ui(['wait-git', 'cmd git_reset_all', 'key Return', 'wait-git'])
        self.assertEqual((self.repo / 'a.txt').read_text(), 'current branch\n')
        self.assertEqual(self.git('status', '--porcelain'), b'')
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)
        self.assertFalse((self.repo / '.git/MERGE_HEAD').exists())

    def test_reset_failure_does_not_clean_untracked_files(self):
        self.commit()
        (self.repo / 'a.txt').write_text('modified\n')
        (self.repo / 'new.txt').write_text('keep after failure\n')
        (self.repo / '.git/index.lock').touch()
        output = self.run_ui(['wait-git', 'cmd git_reset_all', 'key Return',
                              'wait-git', 'print-scm'])
        self.assertIn('error=', output)
        self.assertEqual((self.repo / 'a.txt').read_text(), 'modified\n')
        self.assertEqual((self.repo / 'new.txt').read_text(), 'keep after failure\n')

    def test_repository_switch_does_not_reset_another_repository(self):
        self.commit()
        other = self.work / 'other'
        other.mkdir()
        subprocess.run(['git', 'init', '-q', str(other)], env=self.env, check=True)
        (other / 'keep').write_text('other content\n')
        self.run_ui(['wait-git', 'cmd git_reset_all', 'open ' + str(other), 'wait-git',
                     'key Return', 'wait-git'])
        self.assertEqual((other / 'keep').read_text(), 'other content\n')

    def test_project_subdirectory_resets_whole_repository(self):
        self.commit()
        subdirectory = self.repo / 'subdirectory'
        subdirectory.mkdir()
        (self.repo / 'a.txt').write_text('modified outside project\n')
        (subdirectory / 'new').write_text('new inside project\n')
        self.run_ui(['wait-git', 'cmd git_reset_all', 'key Return', 'wait-git'],
                    start=subdirectory)
        self.assertEqual((self.repo / 'a.txt').read_text(), 'original\n')
        self.assertFalse(subdirectory.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
