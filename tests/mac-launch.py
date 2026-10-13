#!/usr/bin/env python3
"""Real Launch Services file events, ordinary tabs and foreground activation."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid
import unicodedata

if sys.platform != 'darwin':
    print('skip mac/launch (requires macOS)')
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[1]
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

def jxa(expression):
    return subprocess.check_output(['osascript', '-l', 'JavaScript', '-e',
        "ObjC.import('AppKit'); " + expression], text=True).strip()

def until(predicate, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)

with tempfile.TemporaryDirectory(prefix='raftaar-launch-', dir='/tmp') as directory:
    work = Path(directory).resolve()
    bundle = work / 'raftaar.app'
    shutil.copytree(ROOT / 'build/raftaar.app', bundle)
    identifier = 'com.r13.raftaar.test.' + uuid.uuid4().hex
    plist = bundle / 'Contents/Info.plist'
    metadata = plistlib.loads(plist.read_bytes())
    metadata['CFBundleIdentifier'] = identifier
    plist.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['codesign', '-s', '-', '-f', str(bundle)], check=True, capture_output=True)
    exe = bundle / 'Contents/MacOS/raftaar'
    project = work / 'previous project'
    project.mkdir()
    old = project / 'previous.txt'
    old.write_text('previous\n')
    file = work / 'opened café.rb'
    file.write_text('puts "hello"\n')
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[files]\nrestore_project = true\nrestore_session = true\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    env = dict(os.environ, XDG_CONFIG_HOME=str(work / 'config'), XDG_STATE_HOME=str(work / 'state'))
    seed = work / 'seed.rsc'
    seed.write_text('quit\n')
    subprocess.run([str(exe), str(project), str(old), '--headless', '800x600', '--script', str(seed)],
                   env=env, check=True, capture_output=True)
    marker = work / 'state/raftaar/last-project'
    previous = marker.read_bytes()
    front = jxa('$.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js')
    process_id = None
    client = None
    reader = None
    try:
        control = work / 'control'
        subprocess.run(['open', '-n', '-a', str(bundle), str(file),
            '--env', 'XDG_CONFIG_HOME=' + env['XDG_CONFIG_HOME'],
            '--env', 'XDG_STATE_HOME=' + env['XDG_STATE_HOME'],
            '--stdout', str(work / 'stdout'), '--stderr', str(work / 'stderr'),
            '--args', '--control', str(control)], check=True)
        def find_pid():
            return jxa('var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(' +
                       json.dumps(identifier) + '); Number(apps.count) ? Number(apps.objectAtIndex(0).processIdentifier) : 0')
        until(lambda: find_pid() != '0', 'test app did not launch')
        process_id = int(find_pid())
        until(control.exists, 'control socket did not appear')
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(15)
        client.connect(str(control))
        reader = client.makefile('r', encoding='utf-8')
        def command(line):
            client.sendall((line + '\n').encode())
            output = []
            while True:
                reply = reader.readline()
                if reply == 'ok\n':
                    return ''.join(output)
                assert reply not in ('', 'error\n'), (line, reply)
                output.append(reply)
        command('wait 200')
        state = command('print-state')
        assert 'tabs=1 active=' + file.name in unicodedata.normalize('NFC', state), state
        # the file's folder is the project, but not remembered as the last one
        assert unicodedata.normalize('NFC', command('print-project')) == 'project=' + work.as_posix() + '\n'
        # a file launch is a quick edit: no explorer
        assert command('print-panels') == 'explorer=0 term=0\n'
        assert marker.read_bytes() == previous
        until(lambda: jxa('$.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js') == identifier,
              'file launch did not activate raftaar')
        print('ok   mac/finder-file-only-tab-and-foreground')
        # A file delivered to a running app remains a normal tab and activates it again.
        command('type #pending')
        second = work / 'second.rb'
        second.write_text('second\n')
        jxa('$.NSRunningApplication.runningApplicationsWithBundleIdentifier(' + json.dumps(identifier) +
            ').objectAtIndex(0).hide')
        jxa('var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(' + json.dumps(front) +
            '); if (Number(apps.count)) apps.objectAtIndex(0).activateWithOptions(3)')
        subprocess.run(['open', '-a', str(bundle), str(second)], check=True)
        until(lambda: 'tabs=2 active=second.rb' in command('print-state'), 'warm file event did not open a tab')
        until(lambda: jxa('$.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js') == identifier,
              'warm file event did not activate raftaar')
        command('cmd next_tab')
        document = command('print-doc')
        assert '#pending' in document, document
        command('cmd save')
        command('quit')
        until(lambda: find_pid() == '0', 'app did not quit')
        process_id = None
        assert marker.read_bytes() == previous
        print('ok   mac/running-file-tab-and-foreground')
    finally:
        if reader:
            reader.close()
        if client:
            client.close()
        if process_id:
            try:
                os.kill(process_id, 15)
            except ProcessLookupError:
                pass
        subprocess.run([LSREGISTER, '-u', str(bundle)], check=False, capture_output=True)
        if front:
            jxa('var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(' + json.dumps(front) +
                '); if (Number(apps.count)) apps.objectAtIndex(0).activateWithOptions(3)')
