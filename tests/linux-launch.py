#!/usr/bin/env python3
"""Native Linux launch focus with a competing window and focus prevention enabled."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

if sys.platform != 'linux':
    print('skip linux/launch (requires Linux)')
    sys.exit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / 'build/raftaar'
wayland = '--wayland' in sys.argv

def until(predicate, message):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)

with tempfile.TemporaryDirectory(prefix='raftaar-launch-') as directory:
    work = Path(directory)
    processes = []
    client = None
    reader = None
    logs = []
    env = dict(os.environ, XDG_CONFIG_HOME=str(work / 'config'), XDG_STATE_HOME=str(work / 'state'))
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[files]\nrestore_project = true\nrestore_session = true\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    project = work / 'previous project'
    project.mkdir()
    old = project / 'previous.txt'
    old.write_text('previous\n')
    file = work / 'opened.rb'
    file.write_text('puts "hello"\n')
    seed = work / 'seed.rsc'
    seed.write_text('quit\n')
    subprocess.run([str(EXE), str(project), str(old), '--headless', '800x600', '--script', str(seed)],
                   env=env, check=True, capture_output=True)
    marker = work / 'state/raftaar/last-project'
    previous = marker.read_bytes()
    control = work / 'control'

    def start(args, **kwargs):
        log = open(work / ('process-' + str(len(processes)) + '.log'), 'w')
        logs.append(log)
        p = subprocess.Popen(args, env=env, stdout=log, stderr=log, **kwargs)
        processes.append(p)
        return p

    def output(args):
        return subprocess.check_output(args, env=env, text=True).strip()

    try:
        if wayland:
            runtime = work / 'runtime'
            runtime.mkdir(mode=0o700)
            env.update(XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS='headless',
                       WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
            env.pop('DISPLAY', None)
            env.pop('WAYLAND_DISPLAY', None)
            compositor = work / 'sway.conf'
            compositor.write_text('output * resolution 1280x800\n'
                                  'focus_on_window_activation focus\nno_focus [app_id="raftaar"]\n')
            start(['sway', '-d', '-c', str(compositor)])
            until(lambda: bool(list(runtime.glob('sway-ipc.*.sock'))), 'Sway did not start')
            env['SWAYSOCK'] = str(next(runtime.glob('sway-ipc.*.sock')))
            env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*') if not p.name.endswith('.lock'))
            def nodes(tree):
                yield tree
                for child in tree.get('nodes', []) + tree.get('floating_nodes', []):
                    yield from nodes(child)
            def tree():
                return list(nodes(json.loads(output(['swaymsg', '-t', 'get_tree', '-r']))))
            protocols = Path(output(['pkg-config', '--variable=pkgdatadir', 'wayland-protocols']))
            protocol_sources = []
            for name, xml in [('xdg-shell', protocols / 'stable/xdg-shell/xdg-shell.xml'),
                              ('xdg-activation', protocols / 'staging/xdg-activation/xdg-activation-v1.xml')]:
                subprocess.run(['wayland-scanner', 'client-header', str(xml),
                                str(work / (name + '-client-protocol.h'))], check=True)
                source = work / (name + '-protocol.c')
                subprocess.run(['wayland-scanner', 'private-code', str(xml), str(source)], check=True)
                protocol_sources.append(str(source))
            launcher = work / 'launcher'
            subprocess.run(['cc', '-I', str(work), str(ROOT / 'tests/wayland-launcher.c'),
                            *protocol_sources, '-lwayland-client', '-o', str(launcher)], check=True)
            start([str(launcher), str(work / 'token')])
            until(lambda: any(n.get('app_id') == 'raftaar-launcher' and n.get('focused') for n in tree()),
                  'competitor did not focus')
            until(lambda: (work / 'token').exists(), 'focused launcher did not provide a token')
            token = (work / 'token').read_text()
            assert token, 'focused launcher returned an empty activation token'
            # The focused client supplies its surface and focus serial, as a file
            # manager does. A swaymsg exec token cannot activate mapped windows in
            # Sway 1.9. Launch independently so parent PID matching cannot hide a
            # missing activation request.
            env['XDG_ACTIVATION_TOKEN'] = token
            start([str(EXE), str(file), '--control', str(control)])
            active = lambda: any(n.get('app_id') == 'raftaar' and n.get('focused') for n in tree())
        else:
            # Use a private server rather than touching an existing desktop.
            read_fd, write_fd = os.pipe()
            start(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1280x800x24', '-nolisten', 'tcp'], pass_fds=(write_fd,))
            os.close(write_fd)
            with os.fdopen(read_fd) as pipe:
                env['DISPLAY'] = ':' + pipe.readline().strip()
            env['RAFTAAR_BACKEND'] = 'x11'
            env.pop('WAYLAND_DISPLAY', None)
            wm = work / 'openbox.xml'
            wm.write_text('<openbox_config xmlns="http://openbox.org/3.4/rc"><focus><focusNew>no</focusNew>'
                          '</focus></openbox_config>')
            start(['openbox', '--config-file', str(wm)])
            until(lambda: '_NET_SUPPORTING_WM_CHECK(WINDOW)' in output(['xprop', '-root', '_NET_SUPPORTING_WM_CHECK']),
                  'Openbox did not start')
            start(['xmessage', '-name', 'raftaar-competitor', 'Other application'])
            until(lambda: subprocess.run(['xdotool', 'search', '--name', 'raftaar-competitor'], env=env,
                                         capture_output=True).returncode == 0, 'competitor did not map')
            other_window = output(['xdotool', 'search', '--name', 'raftaar-competitor']).splitlines()[0]
            output(['xdotool', 'windowactivate', '--sync', other_window])
            start([str(EXE), str(file), '--control', str(control)])
            def active():
                result = subprocess.run(['xdotool', 'getactivewindow'], env=env,
                                        capture_output=True, text=True)
                windows = subprocess.run(['xdotool', 'search', '--class', '^raftaar$'], env=env,
                                         capture_output=True, text=True)
                return result.returncode == 0 and result.stdout.strip() in windows.stdout.splitlines()
        until(control.exists, 'editor control socket did not appear')
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
        assert 'tabs=1 active=opened.rb' in command('print-state')
        # the file's folder is the project, but not remembered as the last one
        assert command('print-project') == 'project=' + str(work) + '\n'
        # a file launch is a quick edit: no explorer
        assert command('print-panels') == 'explorer=0 term=0\n'
        assert marker.read_bytes() == previous
        until(active, 'file launch did not bring raftaar to the foreground')
        command('quit')
        print('ok   linux/' + ('wayland-token' if wayland else 'x11') + '-file-tab-and-foreground')
    except BaseException:
        if wayland and env.get('SWAYSOCK'):
            result = subprocess.run(['swaymsg', '-t', 'get_tree', '-r'], env=env,
                                    capture_output=True, text=True)
            print('Sway tree:', result.stdout or result.stderr, file=sys.stderr)
        for process, log in zip(processes, logs):
            log.flush()
            print('Process ' + str(process.args) + ':', file=sys.stderr)
            print(Path(log.name).read_text(), file=sys.stderr)
        raise
    finally:
        if reader:
            reader.close()
        if client:
            client.close()
        if wayland and env.get('SWAYSOCK'):
            subprocess.run(['swaymsg', '[app_id="raftaar"]', 'kill'], env=env, capture_output=True)
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for log in logs:
            log.close()
