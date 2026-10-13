#!/usr/bin/env python3
"""Exercise the Windows installer against local, checksum-verified release fixtures."""
import functools
import hashlib
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
if os.name != 'nt':
    raise SystemExit('Run installer tests on Windows.')
subprocess.run([sys.executable, str(ROOT / 'tests/file-associations.py')], check=True)
VERSION = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
ASSET = f'raftaar-{VERSION}-windows-x86_64.zip'


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix='raftaar-installer-') as temporary:
    temp = Path(temporary)
    release = temp / 'releases' / 'download' / ('v' + VERSION)
    release.mkdir(parents=True)
    latest = temp / 'releases/latest/download'
    latest.mkdir(parents=True)
    (latest / 'VERSION').write_text(VERSION + '\n')
    shutil.copyfile(ROOT / 'build/windows' / ASSET, release / ASSET)
    digest = hashlib.sha256((release / ASSET).read_bytes()).hexdigest()
    checksums = release / 'SHA256SUMS'
    checksums.write_text(f'{digest}  {ASSET}\n')
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=temp))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    destination = temp / 'Program files café' / 'raftaar'
    url = f'http://127.0.0.1:{server.server_port}/releases'
    before_path = subprocess.check_output(['powershell.exe', '-NoProfile', '-Command',
        "[Environment]::GetEnvironmentVariable('Path', 'User')"])

    def install(*options, success=True, target=destination):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', str(ROOT / 'install.ps1'), '-InstallDir', str(target), '-ReleasesUrl', url,
            '-NoModifyPath', '-NoShortcut', '-NoFileAssociations', *options], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=60)
        assert (result.returncode == 0) == success, result.stdout.decode(errors='replace')
        return result

    def install_while_stage_held(*options, ready):
        """install, with LICENSE in its staging folder held open from before the folder is to move into
        place (ready: the file written just before that) until a second after, as Windows or a scan of
        the staged raftaar.com can right after it runs: the move waits for the file instead of failing"""
        held = []

        def hold():
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                stages = list(destination.parent.glob('.raftaar-stage-*'))
                try:
                    handle = open(stages[0] / 'LICENSE', 'rb') if stages else None
                except OSError:  # not extracted yet
                    handle = None
                if handle is None:
                    time.sleep(0.005)
                    continue
                with handle:
                    while not (stages[0] / ready).exists() and time.monotonic() < deadline:
                        time.sleep(0.005)
                    time.sleep(1)
                    held.append(stages[0].exists())
                return

        holder = threading.Thread(target=hold, daemon=True)
        holder.start()
        result = install(*options)
        holder.join(timeout=60)
        assert held == [True], f'the staging folder was not held while it was to move: {held}'
        return result

    def version():
        assert subprocess.check_output([str(destination / 'raftaar.com'), '--version']).strip() == ('raftaar ' + VERSION).encode()

    try:
        install()  # latest lookup and first install, including a Unicode destination
        version()
        assert (destination / '.raftaar-install').is_file()
        assert 'file-associations: no' in (destination / '.raftaar-install').read_text()
        install_while_stage_held('-Version', VERSION, ready='.raftaar-install')
        version()
        print('ok   install/latest-version-and-reinstall', flush=True)
        checksums.write_text(f'{"0" * 64}  {ASSET}\n')
        install(success=False)
        version()
        checksums.write_text(f'{digest}  {ASSET}\n')
        print('ok   install/checksum-failure-preserves-installation', flush=True)
        unrelated = destination / 'personal.txt'
        unrelated.write_bytes(b'keep this')
        install(success=False)
        install('-Uninstall', success=False)
        assert unrelated.read_bytes() == b'keep this'
        version()
        unrelated.unlink()
        arbitrary = temp / 'unrelated'
        arbitrary.mkdir()
        (arbitrary / 'data').write_bytes(b'keep this too')
        install(target=arbitrary, success=False)
        assert (arbitrary / 'data').read_bytes() == b'keep this too'
        print('ok   install/unrelated-files-preserved', flush=True)
        # A PE overlay distinguishes the old executables from the incoming release,
        # while leaving them runnable for the running-file and rollback checks.
        for name in ('raftaar.exe', 'raftaar.com'):
            with (destination / name).open('ab') as stream:
                stream.write(b'old installation test overlay')
        old_console = (destination / 'raftaar.com').read_bytes()
        script = temp / 'running.rsc'
        script.write_text('print-state\nwait 30000\nquit\n')
        process = subprocess.Popen([str(destination / 'raftaar.com'), str(temp), '--headless', '800x600',
            '--script', str(script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=dict(os.environ, XDG_CONFIG_HOME=str(temp / 'config'), XDG_STATE_HOME=str(temp / 'state')))
        try:
            ready = []
            reader = threading.Thread(target=lambda: ready.append(process.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            assert ready and ready[0].startswith(b'tabs='), 'editor did not become ready'
            refusal = install(success=False)
            assert b'Close raftaar before updating' in refusal.stdout, refusal.stdout
            refusal = install('-Uninstall', success=False)
            assert b'Close raftaar before updating' in refusal.stdout, refusal.stdout
            assert process.poll() is None
            # A portable folder can contain personal files. Preparation must leave it intact.
            unrelated.write_bytes(b'keep this')
            staged = destination.parent / ('.raftaar-update-' + str(process.pid))
            options = ('-Version', VERSION, '-UpdateStage', str(staged), '-WaitPid', str(process.pid))
            old = (destination / 'raftaar.exe').read_bytes()
            checksums.write_text(f'{"0" * 64}  {ASSET}\n')
            install(*options, '-PrepareUpdate', success=False)
            assert not staged.exists()
            checksums.write_text(f'{digest}  {ASSET}\n')
            install_while_stage_held(*options, '-PrepareUpdate', ready='update.json')
            assert process.poll() is None
            assert (destination / 'raftaar.exe').read_bytes() == old
            assert unrelated.read_bytes() == b'keep this'
            assert (staged / 'update.json').is_file()
            install(*options, '-PrepareUpdate', success=False)
            assert (staged / 'update.json').is_file()
            print('ok   update/prepare-while-running-and-preserve-portable-files', flush=True)
        finally:
            process.kill()
            process.wait()
        # A tampered stage must fail before changing the old editor.
        staged_license = staged / 'LICENSE'
        license_bytes = staged_license.read_bytes()
        staged_license.write_bytes(b'tampered')
        install(*options, '-ApplyUpdate', success=False)
        assert (destination / 'raftaar.exe').read_bytes() == old
        staged_license.write_bytes(license_bytes)
        # A second editor instance must prevent apply even after the initiating one exits.
        other = subprocess.Popen([str(destination / 'raftaar.com'), str(temp), '--headless', '800x600',
            '--script', str(script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=dict(os.environ, XDG_CONFIG_HOME=str(temp / 'other-config'), XDG_STATE_HOME=str(temp / 'other-state')))
        try:
            ready = []
            reader = threading.Thread(target=lambda: ready.append(other.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            assert ready and ready[0].startswith(b'tabs='), 'second editor did not become ready'
            install(*options, '-ApplyUpdate', success=False)
            assert (destination / 'raftaar.exe').read_bytes() == old
            assert (destination / 'raftaar.com').read_bytes() == old_console
            assert (staged / 'update.json').exists()
        finally:
            other.kill()
            other.wait()
        print('ok   update/second-editor-prevents-apply', flush=True)
        # Force failure after the first replacement to exercise rollback of both executables.
        locked = destination / 'LICENSE'
        lock_script = temp / 'lock.ps1'
        lock_script.write_text("$f=[IO.File]::Open($args[0], 'Open', 'Read', 'None'); 'ready'; Start-Sleep 30")
        locker = subprocess.Popen(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(lock_script), str(locked)],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            assert locker.stdout.readline().strip() == b'ready'
            install(*options, '-ApplyUpdate', success=False)
            assert (destination / 'raftaar.exe').read_bytes() == old
            assert (destination / 'raftaar.com').read_bytes() == old_console
            version()
            assert unrelated.read_bytes() == b'keep this'
        finally:
            locker.kill()
            locker.wait()
        # Failed apply retains recovery data; discard it before a fresh preparation.
        shutil.rmtree(staged)
        install(*options, '-PrepareUpdate')
        install(*options, '-ApplyUpdate')
        version()
        assert 'file-associations: no' in (destination / '.raftaar-install').read_text()
        assert (destination / 'raftaar.exe').read_bytes() != old
        assert (destination / 'raftaar.com').read_bytes() != old_console
        assert unrelated.read_bytes() == b'keep this'
        assert not staged.exists()
        unrelated.unlink()
        print('ok   update/tamper-detection-rollback-and-apply', flush=True)
        print('ok   install/running-editor-preserved', flush=True)
        install('-Uninstall')
        assert not destination.exists()
        leftovers = list(destination.parent.glob('.raftaar-*'))
        assert not leftovers, f'staging or backup directories leaked: {leftovers}'
        after_path = subprocess.check_output(['powershell.exe', '-NoProfile', '-Command',
            "[Environment]::GetEnvironmentVariable('Path', 'User')"])
        assert before_path == after_path, 'NoModifyPath changed the user PATH'
        print('ok   install/uninstall-and-no-modify-path', flush=True)
    finally:
        server.shutdown()
        server.server_close()
