#!/usr/bin/env python3
"""Follow system dark mode on macOS: a copy of the app follows the system's appearance as it
changes, and shows the change on screen. It switches the whole system's appearance (and back), so
it runs only with RAFTAAR_TEST_SYSTEM_APPEARANCE=1, as CI sets it."""
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

if sys.platform != 'darwin':
    print('skip mac/appearance (requires macOS)')
    sys.exit(0)
if os.environ.get('RAFTAAR_TEST_SYSTEM_APPEARANCE') != '1':
    print('skip mac/appearance (switches the system appearance: set RAFTAAR_TEST_SYSTEM_APPEARANCE=1)')
    sys.exit(0)
ROOT = Path(__file__).resolve().parents[1]
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
# SkyLight's switch, which System Settings uses, for when System Events may not be scripted
HELPER = r'''
#include <dlfcn.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    void (*set)(int) = sky ? (void (*)(int))dlsym(sky, "SLSSetAppearanceThemeLegacy") : 0;
    if (!set) return 2;
    set(argc > 1 && argv[1][0] == '1');
    return 0;
}
'''


def until(predicate, message, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)


def find_pid(identifier):
    return int(subprocess.check_output(['osascript', '-l', 'JavaScript', '-e',
        "ObjC.import('AppKit'); var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("
        + json.dumps(identifier) + '); Number(apps.count) ? Number(apps.objectAtIndex(0).processIdentifier) : 0'],
        text=True).strip())


def system_dark():
    return subprocess.run(['defaults', 'read', '-g', 'AppleInterfaceStyle'], capture_output=True,
                          text=True).stdout.strip() == 'Dark'


with tempfile.TemporaryDirectory(prefix='raftaar-appearance-', dir='/tmp') as directory:
    work = Path(directory).resolve()
    helper = work / 'appearance'
    (work / 'helper.c').write_text(HELPER)

    def set_dark(dark):
        script = ('tell application "System Events" to tell appearance preferences to set dark mode to '
                  + ('true' if dark else 'false'))
        try:
            # an automation prompt nobody answers must not hang the test
            scripted = subprocess.run(['osascript', '-e', script], capture_output=True,
                                      timeout=20).returncode == 0
        except subprocess.TimeoutExpired:
            scripted = False
        if scripted:
            for _ in range(40):
                if system_dark() == dark:
                    return
                time.sleep(.05)
        if not helper.exists():
            subprocess.run(['cc', '-o', str(helper), str(work / 'helper.c')], check=True)
        subprocess.run([str(helper), '1' if dark else '0'], check=True)
        until(lambda: system_dark() == dark, 'the system appearance did not change')

    bundle = work / 'raftaar.app'
    shutil.copytree(ROOT / 'build/raftaar.app', bundle)
    identifier = 'com.r13.raftaar.test.' + uuid.uuid4().hex
    plist = bundle / 'Contents/Info.plist'
    metadata = plistlib.loads(plist.read_bytes())
    metadata['CFBundleIdentifier'] = identifier
    plist.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['codesign', '-s', '-', '-f', str(bundle)], check=True, capture_output=True)
    (work / 'project').mkdir()
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
                      '[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    control = work / 'control'
    original = system_dark()
    client = None
    process_id = 0
    try:
        subprocess.run(['open', '-n', '-a', str(bundle), '--env', 'HOME=' + str(work),
                        '--env', 'XDG_CONFIG_HOME=' + str(work / 'config'),
                        '--env', 'XDG_STATE_HOME=' + str(work / 'state'),
                        '--args', str(work / 'project'), '--control', str(control)], check=True)
        until(lambda: find_pid(identifier) != 0, 'the app did not launch')
        process_id = find_pid(identifier)
        until(control.exists, 'the control socket did not appear')
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(15)
        client.connect(str(control))
        reader = client.makefile('r', encoding='utf-8')

        def command(line):
            client.sendall((line + '\n').encode())
            parts = []
            while True:
                reply = reader.readline()
                if reply == 'ok\n':
                    return ''.join(parts)
                assert reply not in ('', 'error\n'), (line, reply)
                parts.append(reply)

        def state():
            return dict(part.split('=', 1) for part in command('print-appearance').split())

        def pixel():
            shot = work / 'shot.ppm'
            shot.unlink(missing_ok=True)
            command('shot ' + str(shot))
            until(lambda: shot.exists() and shot.stat().st_size > 100, 'no shot')
            time.sleep(.2)
            head = shot.read_bytes().split(b'\n', 3)
            width = int(head[1].split()[0])
            return head[3][(width * 500 + 500) * 3:(width * 500 + 500) * 3 + 3]

        def expect(dark):
            system, shown = ('dark', 'raftaar-dark') if dark else ('light', 'raftaar-light')
            seen = {}
            try:
                until(lambda: seen.update(state()) or (seen['system'], seen['shown']) == (system, shown),
                      '', 10)
            except AssertionError:
                raise AssertionError(f'expected {system}: {seen}') from None

        command('wait 300')
        expect(original)
        before = pixel()
        for dark in (not original, original, not original):
            set_dark(dark)
            expect(dark)
        assert pixel() != before, 'the window did not change'
        set_dark(original)
        expect(original)
        command('quit')
        # it saves its session and settings into the folder that goes next
        until(lambda: find_pid(identifier) == 0, 'the app did not quit')
        process_id = 0
        print('ok   mac/appearance-follows-the-system')
    finally:
        if system_dark() != original:
            set_dark(original)
        if client is not None:
            client.close()
        if process_id:
            try:
                os.kill(process_id, 15)
            except ProcessLookupError:
                pass
        subprocess.run([LSREGISTER, '-u', str(bundle)], check=False, capture_output=True)
        subprocess.run(['defaults', 'delete', identifier], capture_output=True)
