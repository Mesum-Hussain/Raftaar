#!/usr/bin/env python3
"""Capture X11 setup requests using isolated authority files and a fake server."""
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
LOCAL = 256
WILD = 65535
HOST = socket.gethostname().encode()
COOKIE = bytes.fromhex('00112233445566778899aabbccddeeff')
STALE = bytes.fromhex('ffeeddccbbaa99887766554433221100')
PROTOCOL = b'MIT-MAGIC-COOKIE-1'


def record(family=LOCAL, address=HOST, cookie=COOKIE, number=b'77', name=PROTOCOL):
    fields = (address, number, name, cookie)
    return struct.pack('!H', family) + b''.join(struct.pack('!H', len(f)) + f for f in fields)


def receive(conn, size):
    data = b''
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise AssertionError('Incomplete X11 setup request')
        data += chunk
    return data


@unittest.skipUnless(sys.platform == 'linux', 'Linux X11 only')
class X11Auth(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-x11-auth-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.directory = Path('/tmp/.X11-unix')
        try:
            self.directory.mkdir(mode=0o1777)
        except FileExistsError:
            pass
        else:
            self.addCleanup(self.remove_directory)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(self.server.close)
        # A private display socket, without touching any existing server's socket.
        self.number = str(100000 + os.getpid()).encode()
        self.path = self.directory / ('X' + self.number.decode())
        self.server.bind(str(self.path))
        self.addCleanup(self.path.unlink)
        self.server.listen(1)
        self.server.settimeout(5)
        self.env = dict(os.environ, DISPLAY=':' + self.number.decode(), HOME=str(self.home),
                        XAUTHORITY=str(self.home / 'Xauthority'),
                        XDG_RUNTIME_DIR=str(self.home), XDG_CONFIG_HOME=str(self.home / 'config'),
                        XDG_STATE_HOME=str(self.home / 'state'), SHELL='/nonexistent')
        self.env.pop('WAYLAND_DISPLAY', None)
        self.env.pop('WAYLAND_SOCKET', None)
        self.env.pop('XAUTHLOCALHOSTNAME', None)

    def remove_directory(self):
        try:
            self.directory.rmdir()
        except OSError:
            # Another X11 client may have created a socket while this test ran.
            pass

    def entry(self, **kwargs):
        return record(**dict(number=self.number, **kwargs))

    def check_cookie(self, entries, expected):
        (self.home / 'Xauthority').write_bytes(b''.join(entries))
        with subprocess.Popen([str(EXE), str(self.home), '--wait'], env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as editor:
            try:
                conn, _ = self.server.accept()
                with conn:
                    conn.settimeout(5)
                    header = receive(conn, 12)
                    self.assertEqual(header[0], ord('l'))
                    self.assertEqual(struct.unpack_from('<H', header, 2)[0], 11)
                    name_len, data_len = struct.unpack_from('<HH', header, 6)
                    name_size = (name_len + 3) & ~3
                    payload = receive(conn, name_size + ((data_len + 3) & ~3))
                    name = payload[:name_len]
                    cookie = payload[name_size:name_size + data_len]
                    # Reject after capturing authentication; no full X server is needed.
                    conn.sendall(struct.pack('<BBHHH', 0, 0, 11, 0, 0))
                _, stderr = editor.communicate(timeout=5)
            finally:
                if editor.poll() is None:
                    editor.kill()
                    editor.communicate()
        self.assertEqual(editor.returncode, 1, stderr.decode())
        self.assertEqual(name, PROTOCOL if expected else b'')
        self.assertEqual(cookie, expected)

    def test_current_host(self):
        self.check_cookie([self.entry()], COOKIE)

    def test_stale_host_before_current(self):
        self.check_cookie([self.entry(address=HOST + b'-old', cookie=STALE), self.entry()], COOKIE)

    def test_current_host_before_stale(self):
        self.check_cookie([self.entry(), self.entry(address=HOST + b'-old', cookie=STALE)], COOKIE)

    def test_stale_host_before_wildcard(self):
        self.check_cookie([self.entry(address=HOST + b'-old', cookie=STALE),
                           self.entry(family=WILD, address=b'')], COOKIE)

    def test_wildcard_with_another_address(self):
        self.check_cookie([self.entry(family=WILD, address=b'another-host')], COOKIE)

    def test_only_stale_host(self):
        self.check_cookie([self.entry(address=HOST + b'-old', cookie=STALE)], b'')

    def test_other_family_with_current_hostname(self):
        self.check_cookie([self.entry(family=0, cookie=STALE), self.entry()], COOKIE)

    def test_local_address_must_match_exactly(self):
        for address in (b'', HOST[:-1], HOST + b'-old'):
            with self.subTest(address=address):
                self.check_cookie([self.entry(address=address, cookie=STALE)], b'')

    def test_local_hostname_override(self):
        self.env['XAUTHLOCALHOSTNAME'] = 'authority-host'
        self.check_cookie([self.entry(address=b'authority-host')], COOKIE)

    def test_stale_host_before_override(self):
        self.env['XAUTHLOCALHOSTNAME'] = 'authority-host'
        self.check_cookie([self.entry(address=HOST + b'-old', cookie=STALE),
                           self.entry(address=b'authority-host')], COOKIE)

    def test_override_keeps_current_hostname_usable(self):
        self.env['XAUTHLOCALHOSTNAME'] = 'authority-host'
        self.check_cookie([self.entry()], COOKIE)

    def test_stale_override_does_not_shadow_current_host(self):
        self.env['XAUTHLOCALHOSTNAME'] = 'authority-host'
        self.check_cookie([self.entry(address=b'authority-host', cookie=STALE), self.entry()], COOKIE)

    def test_stale_override_does_not_shadow_wildcard(self):
        self.env['XAUTHLOCALHOSTNAME'] = 'authority-host'
        self.check_cookie([self.entry(address=b'authority-host', cookie=STALE),
                           self.entry(family=WILD, address=b'')], COOKIE)

    def test_wrong_display_is_skipped(self):
        self.check_cookie([record(number=b'0', cookie=STALE), self.entry()], COOKIE)

    def test_empty_display_matches(self):
        self.check_cookie([record(number=b'')], COOKIE)

    def test_wrong_protocol_is_skipped(self):
        self.check_cookie([self.entry(name=b'OTHER-AUTH', cookie=STALE), self.entry()], COOKIE)

    def test_wrong_cookie_length_is_skipped(self):
        self.check_cookie([self.entry(cookie=STALE[:-1]), self.entry()], COOKIE)


if __name__ == '__main__':
    unittest.main(verbosity=2)
