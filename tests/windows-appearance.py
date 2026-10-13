#!/usr/bin/env python3
"""Follow system dark mode on Windows: the app mode under the Personalize key at startup, and its
changes as Settings makes them (the value, then WM_SETTINGCHANGE "ImmersiveColorSet" to every
window). It changes the user's app mode (and back), so it runs only with
RAFTAAR_TEST_SYSTEM_APPEARANCE=1, as CI sets it."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

if os.name != 'nt':
    print('skip windows/appearance (requires Windows)')
    sys.exit(0)
if os.environ.get('RAFTAAR_TEST_SYSTEM_APPEARANCE') != '1':
    print('skip windows/appearance (changes the app mode: set RAFTAAR_TEST_SYSTEM_APPEARANCE=1)')
    sys.exit(0)
import ctypes
import winreg

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/windows/raftaar.com')).resolve()
KEY = r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'


def read():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY) as key:
            return winreg.QueryValueEx(key, 'AppsUseLightTheme')[0]
    except FileNotFoundError:
        return None


def write(value):
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, KEY) as key:
        if value is None:
            try:
                winreg.DeleteValue(key, 'AppsUseLightTheme')
            except FileNotFoundError:
                pass
        else:
            winreg.SetValueEx(key, 'AppsUseLightTheme', 0, winreg.REG_DWORD, value)
    result = ctypes.c_size_t()
    # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG
    ctypes.windll.user32.SendMessageTimeoutW(0xffff, 0x1a, 0, ctypes.c_wchar_p('ImmersiveColorSet'),
                                             2, 2000, ctypes.byref(result))


original = read()
with tempfile.TemporaryDirectory(prefix='raftaar-appearance-') as directory:
    work = Path(directory).resolve()
    (work / 'project').mkdir()
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n'
                      '[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
               XDG_STATE_HOME=(work / 'state').as_posix())
    env.pop('RAFTAAR_APPEARANCE', None)
    try:
        def states(lines, changes=()):
            """print-appearance lines of a real window's script, with app mode changes made while
            it waits: (seconds, value) pairs"""
            script = work / 'actions.rsc'
            script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
            timers = [threading.Timer(at, write, (value,)) for at, value in changes]
            process = subprocess.Popen([str(EXE), (work / 'project').as_posix(), '--script',
                                        script.as_posix()], env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE)
            for timer in timers:
                timer.start()
            out, err = process.communicate(timeout=60)
            for timer in timers:
                timer.join()
            assert process.returncode == 0, err.decode(errors='replace')
            return [dict(part.split('=', 1) for part in line.split())
                    for line in out.decode().splitlines() if line.startswith('system=')]

        for value, system, shown in ((1, 'light', 'raftaar-light'), (0, 'dark', 'raftaar-dark'),
                                     (None, 'unknown', 'raftaar-dark')):
            write(value)
            state, = states(['wait 300', 'print-appearance'])
            assert (state['system'], state['shown']) == (system, shown), (value, state)
        write(0)
        result = states(['wait 300', 'print-appearance', 'wait 2500', 'print-appearance',
                         'wait 2500', 'print-appearance'], [(1.5, 1), (4.0, 0)])
        assert [(s['system'], s['shown']) for s in result] == [
            ('dark', 'raftaar-dark'), ('light', 'raftaar-light'), ('dark', 'raftaar-dark')], result
        print('ok   windows/appearance-follows-the-app-mode')
    finally:
        write(original)
