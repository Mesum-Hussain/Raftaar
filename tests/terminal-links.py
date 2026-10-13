#!/usr/bin/env python3
"""Links in the terminal: Cmd+click on macOS, Ctrl+click elsewhere. An http(s) URL goes to the default
browser (a stand-in opener on PATH notes it here), the path of a file that exists opens in a tab, at
its :LINE:COL, relative to the shell's current folder. A plain click still selects."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
CLICK = '⌘ click' if sys.platform == 'darwin' else 'Ctrl+click'


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class TerminalLinks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-links-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        (self.project / 'sub').mkdir(parents=True)
        (self.project / 'notes.txt').write_text('line one\nline two\nline three\nline four\n',
                                                encoding='utf-8')
        (self.project / 'sub/inner.md').write_text('# inner\n', encoding='utf-8')
        # the desktop's opener: open on macOS, xdg-open elsewhere
        self.opened = self.work / 'opened.txt'
        bin_dir = self.work / 'bin'
        bin_dir.mkdir()
        for name in ('open', 'xdg-open'):
            opener = bin_dir / name
            opener.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "' + self.opened.as_posix() + '"\n',
                              encoding='utf-8')
            opener.chmod(0o755)
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[editor]\ncursor_blink = false\n'
                          '[ui]\nagents_panel = false\nsidebar = false\n'
                          '[terminal]\nshell = /bin/sh\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), PS1='$ ', ENV='', HISTFILE='/dev/null',
                        PATH=bin_dir.as_posix() + os.pathsep + os.environ.get('PATH', ''))
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), '--headless', '1280x800',
                                         '--scale', '1', '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(15)
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
        self.command('cmd toggle_terminal')
        self.command('wait 300')

    def tearDown(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=10)
        self.reader.close()
        self.client.close()
        self.process.stderr.close()
        # the shell goes on a moment after raftaar and can still write in its home folder
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.1)
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

    def run_line(self, line, marker=None):
        """Types a command into the shell and waits for its output: for a line only the output has
        (the screen also shows the command as typed), and then for marker"""
        self.marks = getattr(self, 'marks', 0) + 1
        self.command(f'type {line}; echo done$(({self.marks} + 1000))')
        self.command('key Return')
        self.command(f'wait-term done{self.marks + 1000}')
        if marker:
            self.assertIn(marker, self.command('print-term'))

    def cell(self, text, offset=1):
        """The middle of a cell of text in the output (not on a prompt line): x, y."""
        rows = self.command('print-term').splitlines()
        for row, line in enumerate(rows):
            if text in line and not line.startswith('$ '):
                x, y = self.command(f'print-term-cell {row} {line.index(text) + offset}').split()
                return int(x), int(y)
        self.fail(f'{text!r} is not on the screen: {rows}')

    def link_at(self, text, offset=1):
        x, y = self.cell(text, offset)
        self.command(f'move {x} {y}')
        self.command('wait 50')
        return self.command('print-link').strip()

    def state(self):
        return self.command('print-state').strip()

    def openers(self):
        deadline = time.monotonic() + 5
        while not self.opened.exists() and time.monotonic() < deadline:
            self.command('wait 50')
        return self.opened.read_text(encoding='utf-8').splitlines() if self.opened.exists() else []

    def test_a_file_listed_by_ls_opens_in_a_tab(self):
        self.run_line('ls -F', 'notes.txt')
        notes = (self.project / 'notes.txt').as_posix()
        self.assertEqual(self.link_at('notes.txt', 3), 'link=file ' + notes)
        # a folder, and a word that names nothing, are not links
        self.assertEqual(self.link_at('sub/'), 'link=')
        x, y = self.cell('notes.txt')
        self.command(f'click {x} {y}')
        self.assertNotIn('active=', self.state(), 'a plain click opened the file')
        self.command(f'click {x} {y} ctrl')
        self.assertIn('active=notes.txt line=1 col=1', self.state())
        self.assertIn(' focus=0 ', self.state())

    def test_relative_paths_start_in_the_shells_folder(self):
        self.run_line('cd sub && ls', 'inner.md')
        inner = (self.project / 'sub/inner.md').as_posix()
        self.assertEqual(self.link_at('inner.md'), 'link=file ' + inner)
        x, y = self.cell('inner.md')
        self.command(f'click {x} {y} ctrl')
        self.assertIn('active=inner.md ', self.state())

    def test_the_project_follows_a_cd(self):
        # the shell's folder is the project: a name printed before the cd is not looked for in the
        # folder the shell left
        self.run_line('ls && cd sub && echo moved', 'moved')
        self.assertEqual(self.command('print-project'), f'project={self.project.as_posix()}/sub\n'
                         .replace(self.work.as_posix(), '~'))
        self.assertEqual(self.link_at('notes.txt'), 'link=')

    def test_line_and_column(self):
        self.run_line('echo notes.txt:3:6: error and ./notes.txt:2, too', 'error and')
        notes = (self.project / 'notes.txt').as_posix()
        self.assertEqual(self.link_at('notes.txt:3'), f'link=file {notes}:3:6')
        self.assertEqual(self.link_at('./notes.txt:2'), f'link=file {notes}:2')
        # on the punctuation after the name: no link
        self.assertEqual(self.link_at('./notes.txt:2,', len('./notes.txt:2,')), 'link=')
        x, y = self.cell('notes.txt:3')
        self.command(f'click {x} {y} ctrl')
        self.assertIn('active=notes.txt line=3 col=6 ', self.state())

    def test_column_counts_characters_not_bytes(self):
        # rustc and tsc count characters: :1:2 is after the first é, not inside its two UTF-8 bytes
        (self.project / 'utf.txt').write_text('ééé x\n', encoding='utf-8')
        self.run_line('echo utf.txt:1:2: here', 'here')
        x, y = self.cell('utf.txt:1')
        self.command(f'click {x} {y} ctrl')
        self.assertIn('active=utf.txt line=1 col=2 ', self.state())
        self.command('type Z')
        self.assertIn('éZéé x\n', self.command('print-doc'))

    def test_source_columns_ignore_tabs_and_character_display_width(self):
        # rustc's short diagnostic for the third case is :2:10, before "missing".
        # Tabs, wide glyphs, combining marks and supplementary characters each count once.
        cases = [('\tlet x = missing;', 10), ('let 日 = missing;', 9),
                 ('\tlet 日 = missing;', 10), ('e\u0301x', 3), ('😀x', 2), ('abc', 99)]
        for index, (line, column) in enumerate(cases):
            with self.subTest(line=line, column=column):
                if index:
                    self.command('cmd toggle_terminal')  # return focus from the editor
                name = f'column-{index}.txt'
                (self.project / name).write_text('header\n' + line + '\nnext\n', encoding='utf-8')
                self.run_line(f'echo {name}:2:{column}: diagnostic', 'diagnostic')
                x, y = self.cell(name + ':2')
                self.command(f'click {x} {y} ctrl')
                self.command('type Z')
                offset = min(column - 1, len(line))
                expected = 'header\n' + line[:offset] + 'Z' + line[offset:] + '\nnext\n'
                self.assertIn(expected, self.command('print-doc'))

    def test_a_word_longer_than_a_path_is_no_link(self):
        # an unbroken run of thousands of characters (a hex or base64 blob) across wrapped rows
        self.run_line("head -c 6000 /dev/zero | tr '\\0' a; echo", 'aaaa')
        self.assertEqual(self.link_at('aaaa'), 'link=')
        self.assertIn('term=1', self.state())

    def test_absolute_and_home_paths(self):
        (self.work / 'home.txt').write_text('home\n', encoding='utf-8')
        notes = (self.project / 'notes.txt').as_posix()
        # quoted, so the shell leaves ~ for raftaar
        self.run_line(f"echo 'File \"{notes}\", line 1 and ~/home.txt'", 'line 1')
        self.assertEqual(self.link_at(notes), 'link=file ' + notes)
        self.assertEqual(self.link_at('~/home.txt'), 'link=file ' + (self.work / 'home.txt').as_posix())

    def test_urls_go_to_the_browser(self):
        self.run_line("echo '  Local:   http://localhost:5173/ (see https://en.wikipedia.org/wiki/A_(b)).'",
                      'Local:')
        self.assertEqual(self.link_at('localhost'), 'link=url http://localhost:5173/')
        self.assertEqual(self.link_at('http://'), 'link=url http://localhost:5173/')
        self.assertEqual(self.link_at('wikipedia'), 'link=url https://en.wikipedia.org/wiki/A_(b)')
        self.assertEqual(self.link_at('Local'), 'link=')
        self.link_at('localhost')
        self.command('wait 650')
        self.assertEqual(self.command('print-tip'), f'tip=Follow link ({CLICK})\n')
        x, y = self.cell('localhost')
        self.command(f'click {x} {y}')
        self.command('wait 300')
        self.assertFalse(self.opened.exists(), 'a plain click opened the URL')
        self.command(f'click {x} {y} ctrl')
        self.assertEqual(self.openers(), ['http://localhost:5173/'])
        self.assertNotIn('active=', self.state())

    def test_a_url_wrapped_onto_the_next_row(self):
        url = 'https://example.com/' + 'a' * 150 + '/end'
        self.run_line(f"echo '{url}'", '/end')
        self.assertEqual(self.link_at('/end'), 'link=url ' + url)

    def test_a_program_that_takes_the_mouse_still_lets_links_open(self):
        self.run_line(r"printf '\033[?1000h' && echo 'mouse on https://rhun.app/docs'", 'mouse on')
        x, y = self.cell('rhun.app')
        self.command(f'click {x} {y} ctrl')
        self.assertEqual(self.openers(), ['https://rhun.app/docs'])
        self.run_line(r"printf '\033[?1000l' && echo off", 'off')


if __name__ == '__main__':
    unittest.main(verbosity=2)
