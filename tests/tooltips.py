#!/usr/bin/env python3
"""Hover tooltips: the delay, what hides them, the setting, and no redraw while idle."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

# 1280x800 at scale 1: a button, and the strip below it where its tooltip appears
SEARCH = (1126, 20, (1046, 40, 1226, 80))
SETTINGS = (1156, 20, (1064, 40, 1244, 80))
EXPLORER_NEW = (162, 60, (72, 82, 272, 112))
EXPLORER_NEW_FOLDER = (190, 60, (100, 82, 300, 112))
# the branch at the left end of the status bar (770 to 800): its tooltip is above it
AWAY = (640, 400)
# the Git tab's work tree panel with the explorer hidden: each button, and the commands it runs
GIT_BUTTONS = (
    (1223, 106, 'Writes the message from git diff --cached'),
    (902, 224, 'git commit -q -F - < message'),
    (1226, 60, 'git -c pull.rebase=false pull --no-edit'),
    (1145, 224, 'git push'),
    (1200, 60, 'git fetch'),
    (1252, 60, 'git reset --hard -q && git clean -f -d -q'),
    (1257, 272, 'git reset -q -- .'),
    (1257, 300, 'git reset -q -- file.txt'),
    (1257, 336, 'git add -A'),
    (1257, 364, 'git add -A -- b.txt'),
    (1230, 364, 'git checkout -q -- b.txt'),
    (1257, 392, "git add -A -- 'it'\\''s new.txt'"),
    (1230, 392, "git clean -f -d -q -- 'it'\\''s new.txt'"),
)


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class Tooltips(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-tips-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        (self.project / 'file.txt').write_text('text\n', encoding='utf-8')
        self.config = self.work / 'config/raftaar/config'
        self.config.parent.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), GIT_CONFIG_NOSYSTEM='1')
        self.process = self.client = self.reader = None

    def tearDown(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
            self.process.wait(timeout=10)
            self.process.stderr.close()
        for closable in (self.reader, self.client):
            if closable is not None:
                closable.close()
        self.tmp.cleanup()

    def start(self, tooltips=None, git=False, size='1280x800', ui=''):
        setting = ('' if tooltips is None else f'tooltips = {str(tooltips).lower()}\n') + ui
        # git: the Git tab without the explorer, and the AI button (Ollama is not asked)
        git_setting = 'enabled = true\ncommit_ai = ollama\n' if git else 'enabled = false\n'
        if git:
            setting += 'sidebar = false\n'
        self.config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                               '[updates]\ncheck = false\n[git]\n' + git_setting +
                               '[editor]\ncursor_blink = false\n'
                               '[ui]\nagents_panel = false\n' + setting, encoding='utf-8')
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), '--headless', size,
                                         '--scale', '1', '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(10)
        deadline = time.monotonic() + 10
        while True:
            try:
                self.client.connect(str(control))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.fail('editor did not start')
                time.sleep(0.01)
        self.reader = self.client.makefile('r', encoding='utf-8')
        self.command('wait 150')
        self.command('open ' + str(self.project / 'file.txt'))

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def strip(self, box, name):
        path = self.work / (name + '.ppm')
        self.command('shot ' + str(path))
        magic, size, maximum, pixels = path.read_bytes().split(b'\n', 3)
        width = int(size.split()[0])
        x0, y0, x1, y1 = box
        return b''.join(pixels[(y * width + x0) * 3:(y * width + x1) * 3] for y in range(y0, y1))

    def hover(self, button, wait):
        """The strip under the button before hovering, and after hovering for wait ms."""
        x, y, box = button
        self.command('move %d %d' % AWAY)
        self.command('wait 500')      # past TIP_GRACE: the next button waits again
        before = self.strip(box, 'before')
        self.command(f'move {x} {y}')
        self.command(f'wait {wait}')
        return before, self.strip(box, 'after')

    def test_appears_after_the_delay_for_title_bar_and_explorer(self):
        self.start()
        for button in (SEARCH, SETTINGS, EXPLORER_NEW, EXPLORER_NEW_FOLDER):
            before, early = self.hover(button, 200)
            self.assertEqual(before, early, button)
            self.command('wait 500')
            self.assertNotEqual(before, self.strip(button[2], 'late'), button)

    def test_leaving_and_pressing_hide_it(self):
        self.start()
        before, shown = self.hover(SEARCH, 700)
        self.assertNotEqual(before, shown)
        self.command('move %d %d' % AWAY)
        self.command('wait 30')
        self.assertEqual(before, self.strip(SEARCH[2], 'left'))
        # a press hides it while the button is held
        before, shown = self.hover(SETTINGS, 700)
        self.assertNotEqual(before, shown)
        self.command('down')
        self.command('wait 700')
        self.assertEqual(before, self.strip(SETTINGS[2], 'pressed'))
        self.command('move %d %d' % AWAY)
        self.command('up')
        self.command('key Escape')

    def test_a_key_press_dismisses_it_until_another_button(self):
        self.start()
        self.command('move %d %d' % AWAY)
        self.command('wait 60')
        settings_hidden = self.strip(SETTINGS[2], 'settings-hidden')
        before, shown = self.hover(SEARCH, 700)
        self.assertNotEqual(before, shown)
        self.command('type x')
        self.command('wait 900')
        self.assertEqual(before, self.strip(SEARCH[2], 'typed'))
        # the next button gets its tooltip again
        x, y, box = SETTINGS
        self.command(f'move {x} {y}')
        self.command('wait 700')
        self.assertNotEqual(settings_hidden, self.strip(box, 'settings-shown'))

    def test_the_setting_turns_them_off(self):
        self.start(tooltips=False)
        for button in (SEARCH, EXPLORER_NEW):
            before, after = self.hover(button, 700)
            self.assertEqual(before, after, button)

    def git(self, *args, cwd=None):
        subprocess.run(['git', *args], cwd=cwd or self.project, env=self.env, check=True,
                       capture_output=True)

    def test_git_panel_buttons_show_the_commands_they_run(self):
        remote = self.work / 'remote.git'
        self.git('init', '-q', '--bare', str(remote), cwd=self.work)
        (self.project / 'b.txt').write_text('b\n', encoding='utf-8')
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'raftaar')
        self.git('config', 'user.email', 'raftaar@example.com')
        self.git('add', '-A')
        self.git('commit', '-q', '-m', 'one')
        self.git('remote', 'add', 'origin', str(remote))
        self.git('push', '-q', '-u', 'origin', 'main')
        # one file staged, one changed, one new whose name a shell would split
        (self.project / 'file.txt').write_text('staged\n', encoding='utf-8')
        self.git('add', 'file.txt')
        (self.project / 'b.txt').write_text('changed\n', encoding='utf-8')
        (self.project / "it's new.txt").write_text('new\n', encoding='utf-8')
        self.start(git=True)
        self.command('wait-git')
        self.command('cmd git_history')
        self.command('wait-git')
        for x, y, text in GIT_BUTTONS:
            self.command('move %d %d' % AWAY)
            self.command('wait 60')
            self.command(f'move {x} {y}')
            self.command('wait 650')
            self.assertEqual(self.command('print-tip'), f'tip={text}\n', (x, y))
        # with pull.rebase set, a pull leaves it to git
        self.git('config', 'pull.rebase', 'true')
        (self.project / 'file.txt').write_text('staged again\n', encoding='utf-8')
        self.command('wait-git')
        self.command('move %d %d' % AWAY)
        self.command('wait 60')
        self.command('move 1226 60')
        self.command('wait 650')
        self.assertEqual(self.command('print-tip'), 'tip=git pull --no-edit\n')

    def generate_tip(self, font, x, y):
        """Generate's tooltip at x y, in the work tree's panel at its narrowest (260 of a window 600
        wide), with the interface font at FONT"""
        self.git('init', '-q', '-b', 'main')
        self.git('add', 'file.txt')
        self.start(git=True, size='600x500', ui=f'font_size = {font}\n')
        self.command('wait-git')
        self.command('cmd git_history')
        self.command('wait-git')
        self.command('move %d %d' % AWAY)
        self.command('wait 60')
        self.command(f'move {x} {y}')
        self.command('wait 650')
        self.assertEqual(self.command('print-tip'), 'tip=Writes the message from git diff --cached\n')

    def test_generate_beside_a_narrow_message(self):
        self.generate_tip(13, 535, 106)

    def test_generate_under_a_message_it_would_crowd(self):
        # with the largest interface font, beside the message it would leave it narrower than itself
        self.generate_tip(24, 470, 247)

    def test_no_frames_while_shown_and_idle(self):
        self.start()
        self.hover(SEARCH, 700)
        self.command('print-frames')
        self.command('wait 600')
        self.assertEqual(self.command('print-frames'), 'frames=0\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
