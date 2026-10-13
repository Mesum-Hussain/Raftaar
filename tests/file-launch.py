#!/usr/bin/env python3
"""A window started with files alone (raftaar notes.txt, --wait, Finder) is a quick edit: it shows the file
without the explorer, whatever the settings say, and never writes that into them.
A toggle, a focus command or the explorer's row in Settings brings it back, and opening a folder
makes it a project window with its explorer."""
import configparser
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
HIDDEN = 'explorer=0 term=0'
SHOWN = 'explorer=1 term=0'
CONFIG = ('[editor]\ncursor_blink = false\n'
          '[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


def settings_row_y(key):
    """The middle of a [ui] row in Settings, laid out as tests/settings-ui.py does (Follow system on)."""
    y, previous = 192, None
    for line in (ROOT / 'src/app/config.s').read_text(encoding='utf-8').splitlines():
        match = re.match(r'\s+SETTING(?:_ACTION)? \.Ls_(\w+), (\w+), (\w+)', line)
        if not match or match.group(2) == 'theme':
            continue
        section, name = match.group(1), match.group(2)
        if section != previous:
            y += 48
            previous = section
        if (section, name) == ('ui', key):
            return y + 32
        y += 72
    raise KeyError(key)


class FileLaunch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-file-launch-')
        self.home = Path(self.tmp.name).resolve()
        self.alpha = self.home / 'work/alpha'
        self.beta = self.home / 'work/beta'
        self.alpha.mkdir(parents=True)
        self.beta.mkdir(parents=True)
        self.a = self.alpha / 'a.txt'
        self.b = self.alpha / 'b.txt'
        self.a.write_text('alpha\n' * 40, encoding='utf-8')
        self.b.write_text('beta\n', encoding='utf-8')
        self.config = self.home / 'config/raftaar/config'
        self.config.parent.mkdir(parents=True)
        self.configure()
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())

    def tearDown(self):
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def configure(self, ui=''):
        self.config.write_text(CONFIG + ('[ui]\n' + ui if ui else ''), encoding='utf-8')

    def setting(self, key):
        config = configparser.ConfigParser(interpolation=None, strict=False)
        config.read(self.config, encoding='utf-8')
        return config.get('ui', key, fallback=None)

    def run_editor(self, paths, actions, size='1280x800'):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join(['wait 100', *actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), *map(str, paths), '--headless', size, '--scale', '1',
                                 '--script', script.as_posix()], env=self.env, capture_output=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
        output = result.stdout.decode('utf-8')
        self.assertNotIn('unknown command', output)
        return output.splitlines()

    def test_files_alone_hide_the_panels(self):
        before = self.config.read_bytes()
        for name, paths, panels in (
                ('one file', [self.a], HIDDEN),
                ('two files', [self.a, self.b], HIDDEN),
                ('a new file', [self.alpha / 'new.txt'], HIDDEN),
                ('--wait', ['--wait', self.a], HIDDEN),
                ('folder', [self.alpha], SHOWN),
                ('folder and file', [self.alpha, self.a], SHOWN),
                ('--empty', ['--empty'], SHOWN)):
            with self.subTest(launch=name):
                self.assertEqual(self.run_editor(paths, ['print-panels']), [panels])
        self.assertEqual(self.config.read_bytes(), before)

    def test_a_file_launch_looks_like_a_project_with_the_panels_off(self):
        file_shot = self.home / 'file.ppm'
        self.run_editor([self.a], ['shot ' + file_shot.as_posix()])
        self.configure('sidebar = false\n')
        folder_shot = self.home / 'folder.ppm'
        self.run_editor([self.alpha, self.a], ['shot ' + folder_shot.as_posix()])
        self.assertEqual(file_shot.read_bytes(), folder_shot.read_bytes())

    def test_a_changed_setting_saves_the_panels_as_set(self):
        self.assertEqual(self.run_editor([self.a], ['cmd toggle_whitespace', 'print-panels']), [HIDDEN])
        self.assertEqual(self.setting('sidebar'), 'true')

    def test_toggles_bring_the_panels_back(self):
        before = self.config.read_bytes()
        out = self.run_editor([self.a], ['cmd toggle_sidebar', 'print-panels'])
        self.assertEqual(out, [SHOWN])
        # it was on in the settings already: nothing to save
        self.assertEqual(self.config.read_bytes(), before)
        # once back, a toggle hides a panel as in any window, and that is saved
        out = self.run_editor([self.a], ['cmd toggle_sidebar', 'cmd toggle_sidebar', 'print-panels'])
        self.assertEqual(out, [HIDDEN])
        self.assertEqual(self.setting('sidebar'), 'false')

    def test_a_toggle_turns_on_a_panel_set_off(self):
        self.configure('sidebar = false\n')
        out = self.run_editor([self.a], ['cmd toggle_sidebar', 'print-panels'])
        self.assertEqual(out, [SHOWN])
        self.assertEqual(self.setting('sidebar'), 'true')

    def test_focus_commands_show_the_panels(self):
        out = self.run_editor([self.a], ['cmd focus_explorer', 'print-panels'])
        self.assertEqual(out, [SHOWN])

    def test_a_settings_row_holds_in_the_window(self):
        # the explorer's row turned off and on again: the window follows the setting from then on
        y = settings_row_y('sidebar')
        out = self.run_editor([self.a], ['cmd settings', f'click 1027 {y}', 'print-panels',
                                         f'click 1027 {y}', 'print-panels'], size='1400x4200')
        self.assertEqual(out, [HIDDEN, SHOWN])
        self.assertEqual(self.setting('sidebar'), 'true')

    def test_opening_a_folder_shows_the_panels(self):
        for name, folder in (('another folder', self.beta), ("the file's own folder", self.alpha)):
            with self.subTest(folder=name):
                out = self.run_editor([self.a], [f'open {folder.as_posix()}', 'print-panels',
                                                 'print-project'])
                self.assertEqual(out[0], SHOWN)
                self.assertTrue(out[1].replace('\\', '/').endswith('work/' + folder.name), out[1])


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class FileLaunchReload(unittest.TestCase):
    """A config file written while the window runs (another raftaar saving its settings) leaves the
    panels of a file launch hidden."""
    def setUp(self):
        # a short path: a unix socket's path has at most 103 bytes
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-fl-', dir='/tmp')
        self.home = Path(self.tmp.name).resolve()
        self.file = self.home / 'notes.txt'
        self.file.write_text('notes\n', encoding='utf-8')
        self.config = self.home / 'config/raftaar/config'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(CONFIG + '[ui]\nsidebar = true\n', encoding='utf-8')
        env = dict(os.environ, HOME=self.home.as_posix(), RAFTAAR_APPEARANCE='dark',
                   XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                   XDG_STATE_HOME=(self.home / 'state').as_posix())
        control = self.home / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.file), '--headless', '1000x700',
                                         '--control', str(control)], env=env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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

    def tearDown(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=10)
        self.reader.close()
        self.client.close()
        self.tmp.cleanup()

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def test_a_reloaded_config_keeps_the_panels_hidden(self):
        self.assertEqual(self.command('print-panels'), HIDDEN + '\n')
        self.config.write_text(CONFIG + '[ui]\nsidebar = true\n'
                               'dark_theme = nord\n', encoding='utf-8')
        deadline = time.monotonic() + 10
        while 'theme=nord' not in self.command('print-state') and time.monotonic() < deadline:
            self.command('wait 50')
        self.assertIn('theme=nord', self.command('print-state'))
        self.assertEqual(self.command('print-panels'), HIDDEN + '\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
