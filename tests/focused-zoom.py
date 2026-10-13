#!/usr/bin/env python3
"""Editor and terminal font zoom follows focus, persists independently, and leaves images alone."""
import configparser
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
MOD = 'cmd' if sys.platform == 'darwin' else 'ctrl'


class FocusedZoom(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-focused-zoom-')
        self.home = Path(self.tmp.name).resolve()
        self.file = self.home / 'a.txt'
        self.file.write_text('hello\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        self.config = self.home / 'config/raftaar/config'
        self.config.parent.mkdir(parents=True)
        self.configure()

    def tearDown(self):
        # A Windows pseudoconsole's shell can exit just after the editor process.
        for _ in range(50 if os.name == 'nt' else 1):
            try:
                self.tmp.cleanup()
                return
            except PermissionError:
                if os.name != 'nt':
                    raise
                time.sleep(0.2)
        self.tmp.cleanup()

    def configure(self, editor=17, terminal=12, keys=''):
        self.config.write_text('[editor]\nfont_size = ' + str(editor) + '\n'
                               '[terminal]\nfont_size = ' + str(terminal) + '\n'
                               'shell = ' + Path(sys.executable).as_posix() + '\n'
                               '[ui]\nsidebar = false\n'
                               '[updates]\ncheck = false\n[git]\nenabled = false\n' + keys,
                               encoding='utf-8')

    def run_editor(self, actions, path=None):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.home), str(path or self.file),
                                 '--headless', '1000x700', '--script', str(script)],
                                env=self.env, capture_output=True, text=True,
                                encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def sizes(self):
        config = configparser.ConfigParser(interpolation=None, strict=False)
        config.read(self.config, encoding='utf-8')
        return config.getint('editor', 'font_size'), config.getint('terminal', 'font_size')

    def terminal(self):
        return ['cmd new_terminal', 'wait 300']

    def test_zoom_switches_with_the_active_tab_and_persists(self):
        # Toggle Terminal goes back to the file's tab, then to the terminal's again
        self.run_editor([*self.terminal(), 'cmd toggle_terminal', f'key {MOD}+=',
                         'cmd toggle_terminal', f'key {MOD}+=', f'key {MOD}+shift++',
                         f'key {MOD}+-'])
        self.assertEqual(self.sizes(), (18, 13))
        self.run_editor([*self.terminal(), f'key {MOD}+='])
        self.assertEqual(self.sizes(), (18, 14))

    def test_editor_reset_leaves_terminal_size(self):
        self.run_editor([*self.terminal(), 'cmd toggle_terminal', f'key {MOD}+0'])
        self.assertEqual(self.sizes(), (14, 12))

    def test_terminal_reset_leaves_editor_size(self):
        self.run_editor([*self.terminal(), f'key {MOD}+0'])
        self.assertEqual(self.sizes(), (17, 14))

    def test_each_font_uses_its_setting_limits(self):
        # Both settings range over 8..40; zooming never moves a size the other way.
        self.configure(editor=40, terminal=40)
        self.run_editor([f'key {MOD}+=', *self.terminal(), f'key {MOD}+='])
        self.assertEqual(self.sizes(), (40, 40))
        self.configure(editor=8, terminal=8)
        self.run_editor([f'key {MOD}+-', *self.terminal(), f'key {MOD}+-'])
        self.assertEqual(self.sizes(), (8, 8))
        self.configure(editor=30, terminal=30)
        self.run_editor([f'key {MOD}+=', *self.terminal(), f'key {MOD}+='])
        self.assertEqual(self.sizes(), (31, 31))

    def test_palette_zoom_follows_the_focus_it_was_opened_from(self):
        palette = ['cmd command_palette', 'type zoom in', 'key Return']
        self.run_editor([*self.terminal(), *palette])
        self.assertEqual(self.sizes(), (17, 13))
        self.run_editor([*self.terminal(), 'cmd toggle_terminal', *palette])
        self.assertEqual(self.sizes(), (18, 13))
        # Esc returns to the terminal too
        self.run_editor([*self.terminal(), 'cmd command_palette', 'key Escape', f'key {MOD}+='])
        self.assertEqual(self.sizes(), (18, 14))

    def test_terminal_zoom_leaves_the_image_zoom(self):
        output = self.run_editor([*self.terminal(), f'key {MOD}+=', 'cmd toggle_terminal', 'print-state'],
                                 ROOT / 'tests/data/images/rgba.png')
        self.assertEqual(self.sizes(), (17, 13))
        self.assertIn('zoom=100 fit=1', output)

    def test_remapped_zoom_shortcut_works_in_terminal(self):
        self.configure(keys='[keys]\nctrl+j = zoom_in\n')
        self.run_editor([*self.terminal(), f'key {MOD}+j'])
        self.assertEqual(self.sizes(), (17, 13))

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS distinguishes Command from Control')
    def test_physical_control_stays_terminal_input(self):
        self.run_editor([*self.terminal(), 'key ctrl+=', 'key ctrl+-', 'key ctrl+0'])
        self.assertEqual(self.sizes(), (17, 12))


if __name__ == '__main__':
    unittest.main(verbosity=2)
