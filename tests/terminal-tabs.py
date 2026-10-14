#!/usr/bin/env python3
"""Terminals are tabs among the files: Toggle Terminal goes to one and back, New Terminal adds another,
and a terminal's tab closes with its shell."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()


class TerminalTabs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-terminal-tabs-')
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / 'project'
        self.project.mkdir()
        for name in ('a.txt', 'b.txt'):
            (self.project / name).write_text(name + '\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.home.as_posix(),
                        XDG_CONFIG_HOME=(self.home / 'config').as_posix(),
                        XDG_STATE_HOME=(self.home / 'state').as_posix())
        config = self.home / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        # Python provides the same interactive terminal and OSC titles on every platform.
        config.write_text('[ui]\nsidebar = false\n'
                          '[terminal]\nshell = ' + Path(sys.executable).as_posix() + '\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')

    def tearDown(self):
        # Windows releases the folder only once every pseudoconsole's shell has exited.
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    @staticmethod
    def terminal(index, title='tab'):
        """A new terminal that sets its title and prints SESSION_index (the echo of what is typed
        does not have that text, so wait-term waits for the output)."""
        return ['cmd new_terminal', 'wait 300',
                f"type print('\\x1b]0;{title}\\x07SESSION' + '_{index}')", 'key Return',
                f'wait-term SESSION_{index}']

    def run_editor(self, actions, files=('a.txt',), size='1000x700'):
        script = self.home / 'commands.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(self.project), *[str(self.project / f) for f in files],
                                 '--headless', size, '--script', str(script)], env=self.env,
                                capture_output=True, text=True, encoding='utf-8', timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    @staticmethod
    def lines(output, prefix):
        # print-tabs separates the labels with ' | '
        return [line for line in output.replace(' | ', '|').splitlines() if line.startswith(prefix)]

    def test_a_terminal_is_a_tab_after_the_active_file(self):
        output = self.run_editor([*self.terminal(0), 'print-tabs', 'print-state', 'print-panels'],
                                 files=('a.txt', 'b.txt'))
        self.assertEqual(self.lines(output, 'tabs=')[0], 'tabs=a.txt|b.txt|*tab')
        state = self.lines(output, 'tabs=3')[0]
        self.assertIn('focus=8', state)
        self.assertIn('term=1', state)
        self.assertNotIn('hidden', state)
        self.assertIn('explorer=0 term=1', output)

    def test_toggle_goes_to_the_terminal_and_back_to_the_file(self):
        output = self.run_editor(['cmd toggle_terminal', 'wait 300', 'print-tabs',
                                  'cmd toggle_terminal', 'print-tabs', 'print-state',
                                  'cmd toggle_terminal', 'print-tabs', 'print-state'],
                                 files=('a.txt', 'b.txt'))
        tabs = self.lines(output, 'tabs=a.txt')
        self.assertEqual(len(tabs), 3, output)
        # b.txt was active: the terminal opens after it, and the toggle comes back to b.txt
        self.assertTrue(tabs[0].startswith('tabs=a.txt|b.txt|*'), tabs)
        self.assertTrue(tabs[1].startswith('tabs=a.txt|*b.txt|'), tabs)
        self.assertEqual(tabs[2], tabs[0])
        states = self.lines(output, 'tabs=3')
        self.assertIn('active=b.txt', states[0])
        self.assertIn('focus=0', states[0])
        self.assertIn('term=1 hidden', states[0])
        self.assertIn('focus=8', states[1])
        self.assertNotIn('hidden', states[1])

    def test_toggle_returns_to_the_terminal_shown_last(self):
        output = self.run_editor([*self.terminal(0, 'one'), *self.terminal(1, 'two'),
                                  'cmd prev_tab', 'print-tabs', 'cmd toggle_terminal', 'print-tabs',
                                  'cmd toggle_terminal', 'print-tabs', 'print-term'])
        tabs = self.lines(output, 'tabs=')
        self.assertEqual(tabs, ['tabs=a.txt|*one|two', 'tabs=*a.txt|one|two', 'tabs=a.txt|*one|two'])
        self.assertIn('SESSION_0', output)
        self.assertNotIn('SESSION_1', output)

    def test_next_tab_goes_through_terminals_and_files(self):
        output = self.run_editor([*self.terminal(0, 'one'), *self.terminal(1, 'two'),
                                  'key ctrl+Tab', 'print-tabs', 'key ctrl+Tab', 'print-tabs',
                                  'key ctrl+Tab', 'print-tabs', 'key ctrl+PageUp', 'print-tabs'])
        self.assertEqual(self.lines(output, 'tabs='),
                         ['tabs=*a.txt|one|two', 'tabs=a.txt|*one|two', 'tabs=a.txt|one|*two',
                          'tabs=a.txt|*one|two'])

    def test_keys_go_to_the_terminal_shown(self):
        # typed with the second terminal's tab active, after a detour through the file
        output = self.run_editor([*self.terminal(0, 'one'), *self.terminal(1, 'two'),
                                  'cmd toggle_terminal', 'cmd toggle_terminal',
                                  "type print('TYPED_' + 'HERE')", 'key Return', 'wait-term TYPED_HERE',
                                  'print-term', 'print-doc'])
        self.assertIn('\nTYPED_HERE\n', output)
        self.assertIn('SESSION_1', output)
        self.assertNotIn('TYPED_', (self.project / 'a.txt').read_text(encoding='utf-8'))

    @unittest.skipIf(os.name == 'nt', "a pseudoconsole does not report its shell's exit")
    def test_the_tab_closes_when_the_shell_exits(self):
        output = self.run_editor([*self.terminal(0, 'one'), *self.terminal(1, 'two'),
                                  'type exit()', 'key Return', 'wait 800', 'print-tabs', 'print-state',
                                  'print-term'])
        self.assertEqual(self.lines(output, 'tabs=a.txt'), ['tabs=a.txt|*one'])
        state = self.lines(output, 'tabs=2')[0]
        self.assertIn('term=1', state)
        self.assertIn('focus=8', state)
        self.assertIn('SESSION_0', output)

    def test_kill_terminal_closes_its_tab(self):
        output = self.run_editor([*self.terminal(0, 'one'), 'cmd kill_terminal', 'print-tabs',
                                  'print-state'])
        self.assertEqual(self.lines(output, 'tabs=')[0], 'tabs=*a.txt')
        state = self.lines(output, 'tabs=1')[0]
        self.assertIn('focus=0', state)
        self.assertNotIn('term=', state)

    def test_a_middle_click_closes_a_terminal_tab(self):
        # the strip starts at the window's left edge under the 40 px title bar
        output = self.run_editor([*self.terminal(0, 'one'), 'cmd close_all_tabs', 'print-tabs',
                                  'click 80 20 middle', 'wait 100', 'print-state'], files=())
        self.assertEqual(self.lines(output, 'tabs=*')[0], 'tabs=*one')
        state = self.lines(output, 'tabs=0')
        self.assertEqual(len(state), 1, output)
        self.assertNotIn('term=', state[0])

    def test_close_all_tabs_leaves_terminals_running(self):
        output = self.run_editor([*self.terminal(0, 'one'), 'cmd prev_tab', 'cmd close_all_tabs',
                                  'print-tabs', 'print-state', 'print-term'], files=('a.txt', 'b.txt'))
        self.assertEqual(self.lines(output, 'tabs=')[0], 'tabs=*one')
        state = self.lines(output, 'tabs=1')[0]
        self.assertIn('term=1', state)
        self.assertIn('focus=8', state)
        self.assertIn('SESSION_0', output)

    def test_reopen_closed_tab_skips_terminals(self):
        output = self.run_editor([*self.terminal(0, 'one'), 'cmd kill_terminal',
                                  'cmd reopen_closed_tab', 'print-tabs'])
        self.assertEqual(self.lines(output, 'tabs=')[0], 'tabs=*a.txt')

    def test_a_long_title_is_cut_in_the_strip(self):
        title = 'é' * 30                # 60 bytes: cut between characters, at 40 bytes
        output = self.run_editor([*self.terminal(0, title), 'print-tabs'])
        self.assertEqual(self.lines(output, 'tabs=')[0], 'tabs=a.txt|*' + 'é' * 20 + '…')

    def posix_shell(self, restore=False):
        """/bin/sh as the shell, which notes each start in a file: a hundred of them are light."""
        config = self.home / 'config/raftaar/config'
        config.write_text('[ui]\nsidebar = false\n[terminal]\nshell = /bin/sh\n'
                          '[files]\nrestore_session = ' + str(restore).lower() +
                          '\nrestore_project = false\n'
                          '[editor]\nhome_on_launch = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        self.started = self.home / 'started'
        rc = self.home / 'rc'
        rc.write_text(f'echo $PWD >> "{self.started.as_posix()}"\n', encoding='utf-8')
        self.env.update(ENV=rc.as_posix(), PS1='$ ', HISTFILE='/dev/null')

    @unittest.skipIf(os.name == 'nt', 'a POSIX shell')
    def test_a_hundred_terminals_and_no_more(self):
        self.posix_shell()
        lines = []
        for index in range(101):
            lines += ['cmd new_terminal', 'wait 20']
        output = self.run_editor([*lines, 'print-state', 'print-toast'])
        self.assertIn('tabs=101 ', output)
        self.assertIn('term=100', output)
        self.assertIn('Could not start a shell', output)

    @unittest.skipIf(os.name == 'nt', 'the shell\'s folder is not known on Windows')
    def test_terminal_tabs_come_back_and_start_their_shells_when_shown(self):
        self.posix_shell(restore=True)
        sub = self.project / 'sub'
        sub.mkdir()
        # the folder of the shell shown is the project, whose session this is: back in it at the end
        output = self.run_editor(['cmd new_terminal', 'wait-term $',
                                  'type cd sub; echo in$((1 + 1))', 'key Return', 'wait-term in2',
                                  'wait 200', 'cmd new_terminal', 'wait-term $',
                                  'type cd ..; echo up$((1 + 1))', 'key Return', 'wait-term up2',
                                  'wait 200', 'cmd new_terminal', 'wait-term $', 'cmd prev_tab',
                                  'wait 200', 'print-state'])
        self.assertIn('tabs=4 ', output)
        # the tabs are back, in their places and named after their folders; only the one shown has
        # a shell, started where it was
        self.started.unlink()
        output = self.run_editor(['wait-term $', 'print-state', 'print-tabs',
                                  'type pwd; echo at$((1 + 1))', 'key Return', 'wait-term at2',
                                  'print-term'], files=())
        self.assertIn('tabs=4 ', output)
        self.assertIn('term=3', output)
        self.assertEqual(self.started.read_text().splitlines(), [self.project.as_posix()])
        self.assertIn(self.project.as_posix() + '\n', output)
        self.assertEqual(self.lines(output, 'tabs=')[1], 'tabs=a.txt|sub|*sh|project')
        # and the others get theirs as they are looked at
        self.started.unlink()
        self.run_editor(['wait-term $', 'cmd next_tab', 'wait-term $', 'cmd next_tab', 'wait 200',
                         'cmd next_tab', 'wait-term $'], files=())
        self.assertEqual(sorted(self.started.read_text().splitlines()),
                         sorted([sub.as_posix(), self.project.as_posix(), self.project.as_posix()]))

    @unittest.skipIf(os.name == 'nt', 'a POSIX shell')
    def test_files_dropped_from_another_program(self):
        self.posix_shell()
        folder = self.project / 'my dir'
        folder.mkdir()
        (folder / "it's.txt").write_text('quoted-content\n', encoding='utf-8')
        uri = 'file://' + self.project.as_posix() + "/my%20dir/it's.txt"
        other = 'file://localhost' + (self.project / 'b.txt').as_posix()
        # a terminal gets the paths typed, quoted for the shell; a file's tab opens them
        output = self.run_editor(['cmd new_terminal', 'wait-term $', 'type cat', 'key Space',
                                  f'drop {uri}|# a comment|{other}', 'type ; echo at$((1 + 1))',
                                  'key Return', 'wait-term at2', 'print-term',
                                  'cmd prev_tab', f'drop {uri}', 'print-tabs'])
        self.assertIn('quoted-content\nb.txt\n', output)
        self.assertEqual(self.lines(output, 'tabs=')[0], "tabs=a.txt|*it's.txt|sh")


if __name__ == '__main__':
    unittest.main(verbosity=2)
