#!/usr/bin/env python3
"""Check actual installer output with and without a terminal, using test releases."""
import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run_installer(base, home, terminal=False, overrides=None, options=()):
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               SHELL='/bin/sh', RAFTAAR_RELEASES_URL=base, RAFTAAR_TEAM_ID='not set',
               TERM='xterm-256color', XDG_CURRENT_DESKTOP='')
    env.pop('NO_COLOR', None)
    env.pop('ZDOTDIR', None)
    env.update(overrides or {})
    destination = ['--app-dir', str(home / 'apps')] if sys.platform == 'darwin' else [
        '--prefix', str(home / '.local')]
    command = ['/bin/sh', str(ROOT / 'install.sh'), '--no-modify-path', *destination, *options]
    if not terminal:
        result = subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr.decode()
        assert result.stdout == b'', result.stdout
        return result.stderr

    master, slave = pty.openpty()
    process = subprocess.Popen(command, env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=slave)
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + 30
    try:
        while True:
            if time.monotonic() > deadline:
                raise TimeoutError('Installer did not finish')
            if not select.select([master], [], [], 0.1)[0]:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
        stdout, _ = process.communicate(timeout=5)
        assert process.returncode == 0, output.decode()
        assert stdout == b'', stdout
        return bytes(output)
    finally:
        os.close(master)
        if process.poll() is None:
            process.kill()
            process.wait()


def main():
    with tempfile.TemporaryDirectory(prefix='raftaar-output-') as directory:
        home = Path(directory)
        for label, terminal, overrides, colored in [
            ('redirected', False, {}, False),
            ('terminal', True, {}, True),
            ('no-color', True, {'NO_COLOR': '1'}, False),
            ('dumb-terminal', True, {'TERM': 'dumb'}, False),
        ]:
            output = run_installer(sys.argv[1], home, terminal, overrides)
            assert (b'\x1b[' in output) == colored, output
            assert b'Installing raftaar ' in output and b'1.0.0' in output, output
            assert b'Downloading raftaar 1.0.0' in output, output
            assert b'raftaar 1.0.0 is installed' in output, output
            assert b'Checking latest release' in output, output
            assert b'Download verified' in output, output
            assert b'--configure-files --make-default' in output, output
            assert b'Optional: default editor' in output and b'========================' in output, output
            if colored:
                assert b'\x1b[32m  curl -fsSL ' in output, output
            assert b'[y/N]' not in output, output
            assert b'>_ raftaar' in output, output
            assert b'VERSION' not in output and b'SHA256SUMS' not in output, output
            print(f'ok   install/output-{label}')

        output = run_installer(sys.argv[1], home, options=['--version', '1.0.0'])
        assert b'Installing raftaar 1.0.0' in output, output
        assert b'Checking latest release' not in output, output
        print('ok   install/output-explicit-version')

        target = home / 'apps/raftaar.app' if sys.platform == 'darwin' else home / '.local/bin/raftaar'
        output = run_installer(sys.argv[1], home, terminal=True,
                               options=['--update', '--target', str(target)])
        assert output == b'', output
        print('ok   install/output-quiet-terminal-update')


if __name__ == '__main__':
    main()
