#!/usr/bin/env python3
"""Native copy/paste must survive a short clipboard lock from another process."""
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / 'build/windows/raftaar.exe'


@unittest.skipUnless(os.name == 'nt', 'native Windows clipboard')
class Clipboard(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-clipboard-')
        self.work = Path(self.tmp.name).resolve()
        self.user = ctypes.WinDLL('user32', use_last_error=True)
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.user.CreateWindowExW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR,
            wintypes.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, ctypes.c_void_p]
        self.user.CreateWindowExW.restype = wintypes.HWND
        self.user.DestroyWindow.argtypes = [wintypes.HWND]
        self.user.OpenClipboard.argtypes = [wintypes.HWND]
        self.user.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
        self.user.SetClipboardData.restype = wintypes.HANDLE
        self.user.GetClipboardData.argtypes = [wintypes.UINT]
        self.user.GetClipboardData.restype = wintypes.HANDLE
        self.kernel.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
        self.kernel.GlobalAlloc.restype = wintypes.HANDLE
        self.kernel.GlobalLock.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalLock.restype = ctypes.c_void_p
        self.kernel.GlobalUnlock.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalFree.argtypes = [wintypes.HANDLE]
        self.kernel.GlobalFree.restype = wintypes.HANDLE
        self.window = self.user.CreateWindowExW(0, 'STATIC', 'raftaar clipboard fixture', 0,
                                              0, 0, 1, 1, None, None, None, None)
        self.assertTrue(self.window)
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[ui]\nagents_panel = false\n[updates]\ncheck = false\n'
                          '[git]\nenabled = false\n', encoding='utf-8')
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'))

    def tearDown(self):
        self.user.DestroyWindow(self.window)
        self.tmp.cleanup()

    def open_clipboard(self):
        for _ in range(100):
            if self.user.OpenClipboard(self.window):
                return
            time.sleep(0.01)
        self.fail('fixture could not acquire the clipboard')

    def seed(self, text):
        data = (text + '\0').encode('utf-16-le')
        handle = self.kernel.GlobalAlloc(2, len(data))
        self.assertTrue(handle)
        try:
            pointer = self.kernel.GlobalLock(handle)
            self.assertTrue(pointer)
            ctypes.memmove(pointer, data, len(data))
            self.kernel.GlobalUnlock(handle)
            self.open_clipboard()
            try:
                self.assertTrue(self.user.EmptyClipboard())
                self.assertTrue(self.user.SetClipboardData(13, handle))
                handle = None
            finally:
                self.user.CloseClipboard()
        finally:
            if handle:
                self.kernel.GlobalFree(handle)

    def text(self):
        self.open_clipboard()
        try:
            handle = self.user.GetClipboardData(13)
            self.assertTrue(handle)
            pointer = self.kernel.GlobalLock(handle)
            self.assertTrue(pointer)
            try:
                return ctypes.wstring_at(pointer)
            finally:
                self.kernel.GlobalUnlock(handle)
        finally:
            self.user.CloseClipboard()

    def contend(self, text, before, operation, release_after_operation=False):
        file = self.work / 'document.txt'
        file.write_text(text, encoding='utf-8')
        script = self.work / 'clipboard.rsc'
        script.write_text('\n'.join([*before, 'echo clipboard-ready', 'cmd ' + operation,
            'cmd save', 'quit']) + '\n', encoding='utf-8')
        locked, release = threading.Event(), threading.Event()
        errors = []
        def holder():
            try:
                self.open_clipboard()
                locked.set()
                try:
                    release.wait(10)
                finally:
                    self.user.CloseClipboard()
            except Exception as error:
                errors.append(error)
                locked.set()
        thread = threading.Thread(target=holder)
        thread.start()
        process = None
        try:
            self.assertTrue(locked.wait(3))
            self.assertEqual(errors, [])
            process = subprocess.Popen([str(EXE), str(self.work), str(file), '--script', str(script)],
                env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            first = []
            reader = threading.Thread(target=lambda: first.append(process.stdout.readline()), daemon=True)
            reader.start()
            reader.join(timeout=10)
            self.assertEqual(first, [b'clipboard-ready\n'])
            # The operation starts while the lock is held, then the other app releases it.
            if release_after_operation:
                process.wait(timeout=3)
            else:
                time.sleep(0.15)
            release.set()
            _, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, error)
        finally:
            release.set()
            thread.join(timeout=3)
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        return file.read_text(encoding='utf-8')

    def test_copy_waits_for_another_clipboard_user(self):
        self.seed('old clipboard value')
        self.contend('copied café\n', ['cmd select_all'], 'copy')
        self.assertEqual(self.text(), 'copied café\n')

    def test_paste_waits_for_another_clipboard_user(self):
        self.seed('pasted Ω😀\n')
        self.assertEqual(self.contend('', [], 'paste'), 'pasted Ω😀\n')

    def test_unavailable_clipboard_returns_and_preserves_contents(self):
        for operation in ('copy', 'paste'):
            with self.subTest(operation=operation):
                self.seed('unchanged clipboard')
                original = 'unchanged document\n' if operation == 'copy' else ''
                before = ['cmd select_all'] if operation == 'copy' else []
                self.assertEqual(self.contend(original, before, operation,
                                             release_after_operation=True), original)
                self.assertEqual(self.text(), 'unchanged clipboard')


if __name__ == '__main__':
    unittest.main(verbosity=2)
