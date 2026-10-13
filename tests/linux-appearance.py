#!/usr/bin/env python3
"""Follow system dark mode on Linux, through the real X11 and Wayland backends, against the sources
desktops use (src/plat/appearance.s): the XDG desktop portal's color-scheme on a session bus, as
GNOME, KDE Plasma and others serve it (a scripted portal, and the real xdg-desktop-portal-gtk with
GNOME's settings in dconf), XSETTINGS' Net/ThemeName as Xfce and MATE publish it (xsettingsd), and
GTK's settings.ini as window managers' tools write it. Each changes while raftaar runs.
usage: linux-appearance.py [--wayland]"""
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

if sys.platform != 'linux':
    print('skip linux/appearance (requires Linux)')
    sys.exit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
wayland = '--wayland' in sys.argv
NAME = 'linux/' + ('wayland' if wayland else 'x11') + '-appearance'
for tool in ['dbus-daemon'] + (['sway'] if wayland else ['Xvfb']):
    if not shutil.which(tool):
        print(f'skip {NAME} (requires {tool})')
        sys.exit(0)
PORTAL = Path('/usr/libexec/xdg-desktop-portal')
PORTAL_GTK = Path('/usr/libexec/xdg-desktop-portal-gtk')


def until(predicate, message, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)


# ---- D-Bus, enough to own a name, answer Read and send SettingChanged

def pad(data, n):
    return data + b'\0' * (-len(data) % n)


def marshal(sig, values, data=b''):
    """values of a signature of s, o, g, u and v (a (sig, value) pair) appended to data"""
    for kind, value in zip(sig, values):
        if kind in 'so':
            raw = value.encode()
            data = pad(data, 4) + struct.pack('<I', len(raw)) + raw + b'\0'
        elif kind == 'g':
            data += bytes([len(value)]) + value.encode() + b'\0'
        elif kind == 'u':
            data = pad(data, 4) + struct.pack('<I', value)
        elif kind == 'v':
            data = marshal('gX'.replace('X', value[0]), [value[0], value[1]], data)
    return data


def message(kind, serial, fields, sig='', body=(), flags=0):
    body = marshal(sig, body) if sig else b''
    if sig:
        fields = fields + [(8, 'g', sig)]
    header = b''
    for code, type_, value in fields:
        header = pad(header, 8) + bytes([code, 1, ord(type_), 0])
        header = marshal(type_, [value], header)
    data = b'l' + bytes([kind, flags, 1]) + struct.pack('<III', len(body), serial, len(header)) + header
    return pad(data, 8) + body


def unmarshal(sig, data, offset):
    values = []
    for kind in sig:
        if kind in 'so':
            offset += -offset % 4
            n, = struct.unpack_from('<I', data, offset)
            values.append(data[offset + 4:offset + 4 + n].decode())
            offset += 5 + n
        elif kind == 'g':
            n = data[offset]
            values.append(data[offset + 1:offset + 1 + n].decode())
            offset += 2 + n
        elif kind == 'u':
            offset += -offset % 4
            values.append(struct.unpack_from('<I', data, offset)[0])
            offset += 4
    return values, offset


class Bus:
    """a connection to a bus: a name it owns, Read answered from `settings`"""

    def __init__(self, address, name=None):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        kind, value = address.split(':', 1)[1].split(',')[0].split('=', 1)
        self.sock.connect(value if kind == 'path' else '\0' + value)
        self.sock.sendall(b'\0AUTH EXTERNAL ' + str(os.getuid()).encode().hex().encode() + b'\r\n')
        assert self.sock.recv(4096).startswith(b'OK '), 'the bus refused us'
        self.sock.sendall(b'BEGIN\r\n')
        self.serial = 0
        self.lock = threading.Lock()
        self.buffer = b''
        self.settings = {}              # (namespace, key) -> (signature, value) or None (not found)
        self.delay = 0
        self.mute = False
        self.calls = 0
        self.call('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'Hello')
        self.next()
        if name:
            self.call('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                      'RequestName', 'su', (name, 4))
            while True:
                kind, fields, values = self.next()
                if kind == 2 and fields.get(5) == self.serial:
                    assert values == [1], 'the name is taken'
                    break
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def send(self, kind, fields, sig='', body=(), flags=0):
        with self.lock:
            self.serial += 1
            self.sock.sendall(message(kind, self.serial, fields, sig, body, flags))

    def call(self, destination, path, interface, member, sig='', body=()):
        self.send(1, [(1, 'o', path), (6, 's', destination), (2, 's', interface), (3, 's', member)],
                  sig, body)

    def next(self):
        while True:
            if len(self.buffer) >= 16:
                body_len, serial, fields_len = struct.unpack_from('<III', self.buffer, 4)
                start = 16 + fields_len + (-(16 + fields_len) % 8)
                if len(self.buffer) >= start + body_len:
                    data, self.buffer = self.buffer[:start + body_len], self.buffer[start + body_len:]
                    fields, offset = {}, 16
                    while offset < 16 + fields_len:
                        offset += -offset % 8
                        code, type_ = data[offset], chr(data[offset + 2])
                        (value,), offset = unmarshal(type_, data, offset + 4)
                        fields[code] = value
                    values = []
                    sig = fields.get(8, '')
                    if sig and 'v' not in sig:
                        values, _ = unmarshal(sig, data, start)
                    return data[1], dict(fields, serial=serial), values
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError
            self.buffer += chunk

    def serve(self):
        try:
            while True:
                kind, fields, values = self.next()
                if kind != 1 or fields.get(3) != 'Read':
                    continue
                self.calls += 1
                if self.mute:
                    continue
                if self.delay:
                    time.sleep(self.delay)
                reply = [(5, 'u', fields['serial']), (6, 's', fields[7])]
                setting = self.settings.get(tuple(values))
                if setting is None:
                    self.send(3, reply + [(4, 's', 'org.freedesktop.portal.Error.NotFound')],
                              's', ['Requested setting not found'])
                else:
                    # Read answers with the value in one more variant
                    self.send(2, reply, 'v', [('v', setting)])
        except (EOFError, OSError):
            pass

    def changed(self, namespace, key, sig, value):
        self.settings[namespace, key] = (sig, value)
        self.send(4, [(1, 'o', '/org/freedesktop/portal/desktop'),
                      (2, 's', 'org.freedesktop.portal.Settings'), (3, 's', 'SettingChanged')],
                  'ssv', [namespace, key, (sig, value)])

    def close(self):
        self.sock.close()


APPEARANCE = 'org.freedesktop.appearance'
GNOME = 'org.gnome.desktop.interface'


with tempfile.TemporaryDirectory(prefix='raftaar-appearance-') as directory:
    work = Path(directory)
    processes, logs = [], []
    runtime = work / 'runtime'
    runtime.mkdir(mode=0o700)
    base = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
                XDG_STATE_HOME=str(work / 'state'), XDG_RUNTIME_DIR=str(runtime),
                XDG_DATA_HOME=str(work / 'data'))
    for key in ('DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_CURRENT_DESKTOP',
                'RAFTAAR_APPEARANCE', 'GTK_THEME'):
        base.pop(key, None)
    env = dict(base)
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                      '[editor]\ncursor_blink = false\n'
                      '[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    gtk3 = work / 'config/gtk-3.0'
    project = work / 'project'
    project.mkdir()

    def start(args, environment=None, **kwargs):
        log = open(work / ('process-' + str(len(processes)) + '.log'), 'w')
        logs.append(log)
        kwargs.setdefault('stdout', log)
        p = subprocess.Popen(args, env=environment or env, stderr=log, **kwargs)
        processes.append(p)
        return p

    def stop(p):
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

    def bus(services=False):
        """a session bus of our own; with services, the system's activatable ones (the portal)"""
        socket_path = work / ('bus-' + str(len(processes)))
        conf = work / ('bus-' + str(len(processes)) + '.conf')
        conf.write_text('<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"'
                        ' "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">\n<busconfig>'
                        '<type>session</type><listen>unix:path=' + str(socket_path) + '</listen>'
                        '<auth>EXTERNAL</auth>' + ('<standard_session_servicedirs/>' if services else '') +
                        '<policy context="default"><allow send_destination="*" eavesdrop="true"/>'
                        '<allow eavesdrop="true"/><allow own="*"/></policy></busconfig>')
        daemon = start(['dbus-daemon', '--nofork', '--config-file', str(conf)])
        until(socket_path.exists, 'dbus-daemon did not start')
        return daemon, 'unix:path=' + str(socket_path)

    class Raftaar:
        def __init__(self, environment):
            control = work / 'control'
            control.unlink(missing_ok=True)
            self.started = time.monotonic()
            self.process = start([str(EXE), str(project), '--control', str(control)], environment)
            until(control.exists, 'raftaar did not start')
            self.ready = time.monotonic() - self.started
            self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.client.settimeout(20)
            self.client.connect(str(control))
            self.reader = self.client.makefile('r', encoding='utf-8')

        def command(self, line):
            self.client.sendall((line + '\n').encode())
            parts = []
            while True:
                reply = self.reader.readline()
                if reply == 'ok\n':
                    return ''.join(parts)
                assert reply not in ('', 'error\n'), (line, reply)
                parts.append(reply)

        def state(self):
            return dict(part.split('=', 1) for part in self.command('print-appearance').split())

        def expect(self, system, shown, message):
            state = {}

            def check():
                state.update(self.state())
                return state['system'] == system and state['shown'] == shown
            try:
                until(check, '', 10)
            except AssertionError:
                raise AssertionError(f'{message}: {state}') from None

        def pixel(self):
            """the color in the editor's empty area of the frame on screen"""
            shot = work / 'shot.ppm'
            shot.unlink(missing_ok=True)
            self.command('shot ' + str(shot))
            until(lambda: shot.exists() and shot.stat().st_size > 100, 'no shot')
            time.sleep(.2)
            data = shot.read_bytes()
            head = data.split(b'\n', 3)
            width = int(head[1].split()[0])
            i = (width * 600 + 600) * 3
            return head[3][i:i + 3]

        def close(self):
            try:
                self.command('quit')
            except (AssertionError, OSError):
                pass
            self.reader.close()
            self.client.close()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                stop(self.process)

    def settings_ini(text):
        gtk3.mkdir(parents=True, exist_ok=True)
        (gtk3 / 'settings.ini').write_text('[Settings]\n' + text)

    try:
        if wayland:
            env.update(WLR_BACKENDS='headless', WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
            compositor = work / 'sway.conf'
            compositor.write_text('output * resolution 1280x800\n')
            start(['sway', '-d', '-c', str(compositor)])
            until(lambda: bool(list(runtime.glob('sway-ipc.*.sock'))), 'Sway did not start')
            env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*')
                                          if not p.name.endswith('.lock'))
        else:
            read_fd, write_fd = os.pipe()
            start(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                  pass_fds=(write_fd,))
            os.close(write_fd)
            with os.fdopen(read_fd) as pipe:
                env['DISPLAY'] = ':' + pipe.readline().strip()
            env['RAFTAAR_BACKEND'] = 'x11'

        # Nothing to go by: the dark theme, as before
        raftaar = Raftaar(env)
        raftaar.expect('unknown', 'raftaar-dark', 'without sources')
        dark = raftaar.pixel()
        # settings.ini, written while raftaar runs (its folder too)
        settings_ini('gtk-theme-name=Adwaita\n')
        raftaar.expect('light', 'raftaar-light', 'settings.ini with a light theme')
        light = raftaar.pixel()
        assert light != dark, 'the frame on screen did not change'
        settings_ini('gtk-theme-name=Adwaita\ngtk-application-prefer-dark-theme=1\n')
        raftaar.expect('dark', 'raftaar-dark', 'settings.ini preferring dark')
        settings_ini('gtk-theme-name=Arc-Darker\n')
        raftaar.expect('dark', 'raftaar-dark', 'settings.ini with a dark theme name')
        (gtk3 / 'settings.ini').unlink()
        raftaar.expect('unknown', 'raftaar-dark', 'settings.ini removed')
        # a config folder that does not exist yet
        late = work / 'late/config'
        later = Raftaar(dict(env, XDG_CONFIG_HOME=str(late)))
        later.expect('unknown', 'raftaar-dark', 'no config folder')
        (late / 'gtk-3.0').mkdir(parents=True, exist_ok=True)
        (late / 'gtk-3.0/settings.ini').write_text('[Settings]\ngtk-theme-name=Adwaita\n')
        later.expect('light', 'raftaar-light', 'settings.ini in a config folder made later')
        later.close()
        # made at once (mkdir -p) and removed, again and again: a folder made just before raftaar began
        # to watch the one above it is found all the same (missed about 1 round in 20 before)
        deep = work / 'deep'
        root = deep / 'a/b/config'
        again = Raftaar(dict(env, XDG_CONFIG_HOME=str(root)))
        again.expect('unknown', 'raftaar-dark', 'no config folder yet')
        for n in range(1, 61):
            (root / 'gtk-3.0').mkdir(parents=True)
            (root / 'gtk-3.0/settings.ini').write_text('[Settings]\ngtk-theme-name=Adwaita\n')
            again.expect('light', 'raftaar-light', f'a config folder made at once, round {n}')
            shutil.rmtree(deep)
            again.expect('unknown', 'raftaar-dark', f'that folder removed, round {n}')
        again.close()
        if not wayland:
            window = subprocess.check_output(['xdotool', 'search', '--class', '^raftaar$'], env=env,
                                             text=True).split()[0]

            def variant():
                return subprocess.check_output(['xprop', '-id', window, '_GTK_THEME_VARIANT'],
                                               env=env, text=True)
            until(lambda: '"dark"' in variant(), '_GTK_THEME_VARIANT is not dark')
        print('ok   ' + NAME + '/gtk-settings-ini')

        if not wayland and shutil.which('xsettingsd'):
            # XSETTINGS: a manager's theme, changed, gone, and a new one
            xs = work / 'xsettingsd.conf'
            xs.write_text('Net/ThemeName "Greybird"\nNet/IconThemeName "elementary-xfce-dark"\n')
            manager = start(['xsettingsd', '-c', str(xs)])
            raftaar.expect('light', 'raftaar-light', 'XSETTINGS with a light theme')
            until(lambda: '"light"' in variant(), '_GTK_THEME_VARIANT is not light')
            xs.write_text('Gtk/FontName "Sans 10"\nNet/ThemeName "Greybird-dark"\nXft/DPI 98304\n')
            manager.send_signal(signal.SIGHUP)
            raftaar.expect('dark', 'raftaar-dark', 'XSETTINGS changed to a dark theme')
            settings_ini('gtk-theme-name=Adwaita-dark\n')
            xs.write_text('Net/ThemeName "Adwaita"\n')
            manager.send_signal(signal.SIGHUP)
            raftaar.expect('light', 'raftaar-light', "XSETTINGS' theme over settings.ini's")
            stop(manager)
            raftaar.expect('dark', 'raftaar-dark', 'the manager quit: settings.ini again')
            (gtk3 / 'settings.ini').unlink()
            xs.write_text('Net/ThemeName "Yaru-dark"\n')
            manager = start(['xsettingsd', '-c', str(xs)])
            raftaar.expect('dark', 'raftaar-dark', 'a manager started later')
            stop(manager)
            raftaar.expect('unknown', 'raftaar-dark', 'the manager quit')
            raftaar.close()
            # a config from before dark_theme and light_theme keeps its theme, though XSETTINGS is
            # read only with the window, after the config
            config_text = config.read_text()
            config.write_text(config_text.replace('[ui]\n', '[ui]\ntheme = nord\n', 1))
            xs.write_text('Net/ThemeName "Greybird"\n')
            manager = start(['xsettingsd', '-c', str(xs)])
            until(lambda: subprocess.run(['xprop', '-root', '_XSETTINGS_S0'], env=env,
                                         capture_output=True).returncode == 0, 'no manager')
            time.sleep(.5)
            raftaar = Raftaar(env)
            raftaar.expect('light', 'nord', 'an old config with a light XSETTINGS theme')
            state = raftaar.state()
            assert (state['dark'], state['light']) == ('nord', 'nord'), state
            raftaar.close()
            # also when a source XSETTINGS outranks answers before it: settings.ini's light theme,
            # then XSETTINGS' dark one with the window
            config.write_text(config_text.replace('[ui]\n', '[ui]\ntheme = github-light\n', 1))
            settings_ini('gtk-theme-name=Adwaita\n')
            xs.write_text('Net/ThemeName "Greybird-dark"\n')
            manager.send_signal(signal.SIGHUP)
            time.sleep(.5)
            raftaar = Raftaar(env)
            raftaar.expect('dark', 'github-light', 'an old config, settings.ini light, XSETTINGS dark')
            state = raftaar.state()
            assert (state['dark'], state['light']) == ('github-light', 'github-light'), state
            raftaar.close()
            (gtk3 / 'settings.ini').unlink()
            stop(manager)
            config.write_text(config_text)
            raftaar = Raftaar(env)
            print('ok   ' + NAME + '/xsettings')
        else:
            print('skip ' + NAME + '/xsettings')
        raftaar.close()

        # A portal like KDE's: dark or light, live; it wins over GTK's theme
        daemon, address = bus()
        portal = Bus(address, 'org.freedesktop.portal.Desktop')
        portal.settings[APPEARANCE, 'color-scheme'] = ('u', 1)
        settings_ini('gtk-theme-name=Breeze\n')
        session = dict(env, DBUS_SESSION_BUS_ADDRESS=address)
        raftaar = Raftaar(session)
        raftaar.expect('dark', 'raftaar-dark', 'the portal says dark')
        portal.changed(APPEARANCE, 'color-scheme', 'u', 2)
        raftaar.expect('light', 'raftaar-light', 'the portal changed to light')
        portal.changed(APPEARANCE, 'color-scheme', 'u', 1)
        raftaar.expect('dark', 'raftaar-dark', 'the portal changed to dark')
        # other settings and other namespaces change nothing
        portal.changed(APPEARANCE, 'accent-color', 'u', 7)
        portal.changed('org.gnome.desktop.wm.preferences', 'color-scheme', 'u', 2)
        raftaar.command('wait 300')
        raftaar.expect('dark', 'raftaar-dark', 'unrelated settings')
        raftaar.close()
        print('ok   ' + NAME + '/portal-color-scheme')

        # GNOME's Default style: no preference, and the GTK theme it names
        (gtk3 / 'settings.ini').unlink()
        portal.changed(APPEARANCE, 'color-scheme', 'u', 0)
        portal.changed(GNOME, 'gtk-theme', 's', 'Adwaita')
        raftaar = Raftaar(session)
        raftaar.expect('light', 'raftaar-light', 'no preference with Adwaita')
        portal.changed(GNOME, 'gtk-theme', 's', 'Adwaita-dark')
        raftaar.expect('dark', 'raftaar-dark', 'no preference with Adwaita-dark')
        portal.changed(APPEARANCE, 'color-scheme', 'u', 2)
        raftaar.expect('light', 'raftaar-light', 'prefer light over a dark GTK theme')
        raftaar.close()
        print('ok   ' + NAME + '/portal-no-preference')

        # A portal without the settings: GTK's theme decides
        portal.settings = {}
        settings_ini('gtk-theme-name=Adwaita-dark\n')
        raftaar = Raftaar(session)
        raftaar.expect('dark', 'raftaar-dark', 'the portal has no setting: settings.ini')
        raftaar.close()
        (gtk3 / 'settings.ini').unlink()
        # A portal answering late: the startup goes on, the answer still counts
        portal.settings[APPEARANCE, 'color-scheme'] = ('u', 2)
        portal.delay = 2
        raftaar = Raftaar(session)
        state = raftaar.state()
        assert state['system'] == 'unknown', state
        raftaar.expect('light', 'raftaar-light', 'the late answer')
        raftaar.close()
        # A portal that never answers: raftaar starts without it
        portal.delay = 0
        portal.mute = True
        calls = portal.calls
        raftaar = Raftaar(session)
        assert raftaar.ready < 5, f'startup took {raftaar.ready:.1f} s'
        until(lambda: portal.calls >= calls + 2, 'raftaar did not ask the portal')
        raftaar.expect('unknown', 'raftaar-dark', 'no answer')
        portal.mute = False
        portal.changed(APPEARANCE, 'color-scheme', 'u', 2)
        raftaar.expect('light', 'raftaar-light', 'a signal after no answer')
        # The bus goes away: raftaar keeps the mode, and settings.ini still counts
        portal.close()
        stop(daemon)
        raftaar.command('wait 300')
        raftaar.expect('light', 'raftaar-light', 'the bus went away')
        settings_ini('gtk-application-prefer-dark-theme=true\n')
        raftaar.expect('light', 'raftaar-light', 'the last portal answer stays')
        raftaar.close()
        (gtk3 / 'settings.ini').unlink()
        print('ok   ' + NAME + '/portal-late-silent-gone')

        # Bus addresses: entries that fail first, escapes, abstract names, and the default socket
        daemon, address = bus()
        portal = Bus(address, 'org.freedesktop.portal.Desktop')
        portal.settings[APPEARANCE, 'color-scheme'] = ('u', 2)
        path = address.split('path=', 1)[1]
        escaped = ''.join('%2f' if c == '/' else c for c in path)
        for value in ('tcp:host=localhost,port=1;unix:path=/nonexistent/bus;unix:guid=1,path=' + escaped,
                      'unix:path=' + path + ',guid=0123456789abcdef'):
            raftaar = Raftaar(dict(env, DBUS_SESSION_BUS_ADDRESS=value))
            raftaar.expect('light', 'raftaar-light', 'address ' + value)
            raftaar.close()
        os.symlink(path, runtime / 'bus')
        raftaar = Raftaar(env)
        raftaar.expect('light', 'raftaar-light', 'the default $XDG_RUNTIME_DIR/bus')
        raftaar.close()
        (runtime / 'bus').unlink()
        portal.close()
        stop(daemon)
        # an abstract socket name, as older distributions' session buses have
        name = 'raftaar-appearance-' + str(os.getpid())
        abstract = work / 'abstract.conf'
        abstract.write_text('<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"'
                            ' "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">\n<busconfig>'
                            '<type>session</type><listen>unix:abstract=' + name + '</listen>'
                            '<auth>EXTERNAL</auth><policy context="default">'
                            '<allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/>'
                            '<allow own="*"/></policy></busconfig>')
        daemon = start(['dbus-daemon', '--nofork', '--config-file', str(abstract)])
        address = 'unix:abstract=' + name
        until(lambda: '@' + name in Path('/proc/net/unix').read_text(), 'dbus-daemon did not start')
        portal = Bus(address, 'org.freedesktop.portal.Desktop')
        portal.settings[APPEARANCE, 'color-scheme'] = ('u', 1)
        settings_ini('gtk-theme-name=Adwaita\n')
        raftaar = Raftaar(dict(env, DBUS_SESSION_BUS_ADDRESS=address + ',guid=0123456789abcdef'))
        raftaar.expect('dark', 'raftaar-dark', 'an abstract address')
        raftaar.close()
        (gtk3 / 'settings.ini').unlink()
        portal.close()
        stop(daemon)
        print('ok   ' + NAME + '/bus-addresses')

        # The real portal, xdg-desktop-portal-gtk, serving GNOME's settings from dconf
        if PORTAL.exists() and PORTAL_GTK.exists() and shutil.which('gsettings'):
            daemon, address = bus(services=True)
            portals = work / 'config/xdg-desktop-portal'
            portals.mkdir(parents=True, exist_ok=True)
            (portals / 'portals.conf').write_text('[preferred]\ndefault=gtk\n')
            session = dict(env, DBUS_SESSION_BUS_ADDRESS=address, XDG_CURRENT_DESKTOP='GNOME',
                           GSETTINGS_BACKEND='dconf')

            def gsettings(key, value):
                subprocess.run(['gsettings', 'set', GNOME, key, value], env=session, check=True)
            gsettings('color-scheme', 'prefer-dark')
            gsettings('gtk-theme', 'Adwaita')
            raftaar = Raftaar(session)
            raftaar.expect('dark', 'raftaar-dark', 'GNOME prefer-dark')
            gsettings('color-scheme', 'default')
            raftaar.expect('light', 'raftaar-light', 'GNOME default')
            gsettings('gtk-theme', 'Adwaita-dark')
            raftaar.expect('dark', 'raftaar-dark', 'GNOME default with Adwaita-dark')
            gsettings('color-scheme', 'prefer-light')
            raftaar.expect('light', 'raftaar-light', 'GNOME prefer-light')
            raftaar.close()
            # follow_system off: the system's changes no longer switch the theme
            config_text = config.read_text()
            config.write_text(config_text.replace('[ui]\n', '[ui]\nfollow_system = false\ntheme = nord\n', 1))
            raftaar = Raftaar(session)
            raftaar.expect('light', 'nord', 'follow_system off')
            gsettings('color-scheme', 'prefer-dark')
            raftaar.expect('dark', 'nord', 'follow_system off, the system changed')
            raftaar.close()
            config.write_text(config_text)
            stop(daemon)
            print('ok   ' + NAME + '/xdg-desktop-portal-gtk')
        else:
            print('skip ' + NAME + '/xdg-desktop-portal-gtk (not installed)')
    except BaseException:
        for process, log in zip(processes, logs):
            log.flush()
            print('Process ' + str(process.args) + ':', file=sys.stderr)
            print(Path(log.name).read_text()[-3000:], file=sys.stderr)
        raise
    finally:
        for process in reversed(processes):
            stop(process)
        for log in logs:
            log.close()
