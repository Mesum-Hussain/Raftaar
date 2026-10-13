#!/usr/bin/env python3
"""Untracked folder rows and counts follow disk changes with the explorer hidden."""
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()


class GitUntracked(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-untracked-')
        self.work = Path(self.tmp.name).resolve()
        self.repo = self.work / 'repo café'
        self.repo.mkdir()
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = true\n'
                          '[editor]\ncursor_blink = false\n'
                          '[ui]\nagents_panel = false\nsidebar = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix(),
                        GIT_CONFIG_NOSYSTEM='1')
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / '.gitignore').write_text('*.log\n')
        (self.repo / 'workspace').mkdir()
        (self.repo / 'workspace/file.txt').write_text('tracked\n')
        self.git('add', '-A')
        self.git('commit', '-qm', 'Initial')
        (self.repo / 'notes/sub').mkdir(parents=True)
        (self.repo / 'notes/sub/b.txt').write_text('new\n')
        (self.repo / 'notes/ignored.log').write_text('ignored\n')
        self.process = self.reader = None

    def tearDown(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
            self.process.wait(timeout=10)
            self.reader.join(timeout=5)
            self.process.stdout.close()
            self.process.stderr.close()
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], env=self.env)

    def start(self, snapshots, project=None):
        # Each project line marks a completed snapshot. The following wait gives the test time to
        # mutate the files, without touching a root file or explicitly refreshing Git. --script
        # also exercises the native Windows watcher, where the control socket is unavailable.
        dump = ['print-scm', 'print-gitlog', 'print-project']
        lines = ['wait-git', 'cmd git_history', 'wait-git', 'wait 800', *dump]
        for _ in range(snapshots - 1):
            lines.extend(['wait 1800', 'wait-git', *dump])
        script = self.work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        self.process = subprocess.Popen([str(EXE), (project or self.repo).as_posix(),
                                         '--headless', '1280x800', '--scale', '1',
                                         '--script', script.as_posix()], env=self.env,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, encoding='utf-8')
        self.output = queue.Queue()

        def read():
            for line in self.process.stdout:
                self.output.put(line)
            self.output.put(None)

        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()

    def snapshot(self, files):
        lines = []
        while True:
            try:
                line = self.output.get(timeout=20)
            except queue.Empty:
                self.fail('editor did not produce the next Git snapshot')
            self.assertIsNotNone(line, 'editor exited before the next Git snapshot')
            if line.startswith('project='):
                break
            lines.append(line)
        output = ''.join(lines)
        panel = output.split('\n*', 1)[0]
        actual = [line.strip()[2:] for line in panel.splitlines()
                  if line.strip().startswith('U ')]
        self.assertEqual(actual, sorted(files), output)
        if files:
            self.assertIn('Uncommitted changes ' + str(len(files)), output)
        else:
            self.assertIn('action=none', output)
            self.assertNotIn('Uncommitted changes', output)

    def test_add_remove_rename_and_new_subdirectories(self):
        self.start(5)
        self.snapshot(['notes/sub/b.txt'])
        # notes has no visible file directly in it, but still needs its own watch.
        (self.repo / 'notes/c.txt').write_text('added\n')
        (self.repo / 'notes/sub/b.txt').unlink()
        self.snapshot(['notes/c.txt'])
        (self.repo / 'notes/c.txt').rename(self.repo / 'notes/renamed.txt')
        (self.repo / 'notes/deep/child').mkdir(parents=True)
        (self.repo / 'notes/deep/child/d.txt').write_text('deep\n')
        self.snapshot(['notes/deep/child/d.txt', 'notes/renamed.txt'])
        # After discovery, the newly created deep directory must be watched too.
        (self.repo / 'notes/deep/child/d.txt').unlink()
        (self.repo / 'notes/renamed.txt').unlink()
        self.snapshot([])
        (self.repo / 'notes/deep/child/e.txt').write_text('new after clean\n')
        self.snapshot(['notes/deep/child/e.txt'])

    def test_project_inside_repository_watches_repository_root(self):
        self.start(3, self.repo / 'workspace')
        self.snapshot(['notes/sub/b.txt'])
        (self.repo / 'other').mkdir()
        (self.repo / 'other/a.txt').write_text('new sibling folder\n')
        self.snapshot(['notes/sub/b.txt', 'other/a.txt'])
        (self.repo / 'notes/sub').rename(self.repo / 'notes/moved')
        (self.repo / 'other/a.txt').unlink()
        self.snapshot(['notes/moved/b.txt'])


if __name__ == '__main__':
    unittest.main()
