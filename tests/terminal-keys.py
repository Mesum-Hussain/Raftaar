#!/usr/bin/env python3
"""Keys a program in the terminal receives (issue 54). A program that turns on the kitty keyboard
protocol the way Pi does (CSI > 7 u, CSI ? u, then DA) learns that raftaar keeps flag 1 and gets
Shift+Enter as CSI 13;2u, Alt+Enter as CSI 13;3u and Escape as CSI 27 u; plain Enter stays CR.
Without the protocol, and after the program pops its flags, keys are the legacy bytes again."""
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

# prints the negotiation reply and each key it reads, made readable (ESC, ^M), until q; READY and END
# carry the run's number, so a run does not wait on the text of the one before
READER = r'''
import os, sys, termios, tty
kitty = sys.argv[1] == 'kitty'
run = sys.argv[2]
old = termios.tcgetattr(0)
tty.setraw(0)
def show(data):
    return ''.join('ESC' if c == 27 else '^' + chr(c + 64) if c < 32 else chr(c) for c in data)
def say(text):
    os.write(1, (text + '\r\n').encode())
try:
    if kitty:
        os.write(1, b'\x1b[>7u\x1b[?u\x1b[c')
        reply = b''
        while not reply.endswith(b'c'):
            reply += os.read(0, 64)
        say('R:' + show(reply))
    say('READY' + run)
    while True:
        data = os.read(0, 64)
        if data == b'q':
            break
        say('K:' + show(data))
finally:
    if kitty:
        os.write(1, b'\x1b[<u')
    termios.tcsetattr(0, termios.TCSADRAIN, old)
    say('END' + run)
'''


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class TerminalKeys(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-keys-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        self.reader_py = self.work / 'reader.py'
        self.reader_py.write_text(READER, encoding='utf-8')
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[editor]\ncursor_blink = false\n'
                          '[ui]\nagents_panel = false\nsidebar = false\n'
                          '[terminal]\nshell = /bin/sh\nheight = 600\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), PS1='$ ', ENV='', HISTFILE='/dev/null')
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

    def read_keys(self, mode, keys):
        """Runs the reader, presses keys, and returns its reply line and what each key sent."""
        self.runs = getattr(self, 'runs', 0) + 1
        self.command(f'type {sys.executable} {self.reader_py.as_posix()} {mode} {self.runs}')
        self.command('key Return')
        self.command(f'wait-term READY{self.runs}')
        for key in keys:
            self.command('key ' + key)
            self.command('wait 50')
        self.command('type q')
        self.command(f'wait-term END{self.runs}')
        lines = self.command('print-term').splitlines()
        start = max(i for i, line in enumerate(lines) if 'reader.py' in line)
        reply = next((l[2:].strip() for l in lines[start:] if l.startswith('R:')), None)
        return reply, [l[2:].strip() for l in lines[start:] if l.startswith('K:')]

    def test_kitty_protocol_keys(self):
        reply, sent = self.read_keys('kitty', ['shift+Return', 'alt+Return', 'Return', 'Escape',
                                               'alt+x', 'shift+Tab'])
        self.assertTrue(reply.startswith('ESC[?1u'), reply)
        self.assertEqual(sent, ['ESC[13;2u', 'ESC[13;3u', '^M', 'ESC[27u', 'ESC[120;3u',
                                'ESC[9;2u'])

    def test_legacy_keys_without_the_protocol(self):
        _, sent = self.read_keys('legacy', ['shift+Return', 'alt+Return', 'Return', 'Escape',
                                            'shift+Tab'])
        self.assertEqual(sent, ['^M', 'ESC^M', '^M', 'ESC', 'ESC[Z'])

    def test_keys_are_legacy_again_after_the_program_pops_its_flags(self):
        self.read_keys('kitty', ['shift+Return'])
        _, sent = self.read_keys('legacy', ['shift+Return'])
        self.assertEqual(sent, ['^M'])

    def test_a_running_program_gets_the_keys_of_raftaars_commands(self):
        _, sent = self.read_keys('legacy', ['ctrl+n', 'ctrl+b', 'ctrl+e', 'ctrl+p', 'ctrl+o',
                                            'ctrl+c', 'ctrl+a'])
        self.assertEqual(sent, ['^N', '^B', '^E', '^P', '^O', '^C', '^A'])
        self.assertIn('tabs=1 ', self.command('print-state'))

    def test_raftaars_commands_keep_their_keys_at_the_prompt(self):
        self.command('wait-term $')
        self.command('key ctrl+n')
        self.assertIn('tabs=2 ', self.command('print-state'))
        self.command('cmd close_tab')
        self.command('key ctrl+p')
        self.assertTrue(self.command('print-palette').startswith('field='))
        self.command('key Escape')
        # a document's commands are the shell's keys: ctrl+a is the start of the line, not Select All
        self.command('type cho here$((1 + 1))')
        self.command('key ctrl+a')
        self.command('type e')
        self.command('key Return')
        self.command('wait-term here2')


if __name__ == '__main__':
    unittest.main()
