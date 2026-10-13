#!/usr/bin/env python3
"""Scrolling through the real X11 and Wayland input paths (issue 47). A wheel notch and a touchpad's
travel scroll as far as on the other systems, small touchpad steps add up in both directions instead
of rounding away, and scroll_sensitivity scales them. usage: linux-scroll.py [--wayland]"""
import itertools
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

if sys.platform != 'linux':
    print('skip linux/scroll (requires Linux)')
    sys.exit(0)
ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
wayland = '--wayland' in sys.argv


def until(predicate, message, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix='raftaar-scroll-') as directory:
    work = Path(directory)
    processes = []
    logs = []
    env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_STATE_HOME=str(work / 'state'))
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    file = work / 'lines.txt'
    file.write_text(''.join(f'line {i}\n' for i in range(3000)))

    def start(args, **kwargs):
        log = open(work / ('process-' + str(len(processes)) + '.log'), 'w')
        logs.append(log)
        kwargs.setdefault('stdout', log)
        p = subprocess.Popen(args, env=env, stderr=log, **kwargs)
        processes.append(p)
        return p

    def output(args):
        return subprocess.check_output(args, env=env, text=True).strip()

    def offset(scroll, sensitivity='1.0'):
        """the editor's scroll offset in 1/256 lines once scroll() has sent its events"""
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          f'scroll_sensitivity = {sensitivity}\n'
                          '[editor]\ncursor_blink = false\nline_height = 1.5\nfont_size = 14\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n')
        control = work / 'control'
        control.unlink(missing_ok=True)
        editor = start([str(EXE), str(file), '--control', str(control)])
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

        def y():
            return int(command('print-scroll').split('y=')[1].split()[0])
        try:
            until(lambda: 'tabs=1' in command('print-state'), 'the file did not open')
            until(shown, 'the editor did not show')
            command('wait 300')
            scroll()
            # the events reach the editor on their own: wait until the offset stops moving
            last = None
            for _ in range(40):
                command('wait 100')
                now = y()
                if now == last:
                    return now
                last = now
            return last
        finally:
            command('quit')
            reader.close()
            client.close()
            editor.wait(timeout=10)

    def near(value, expected, message):
        assert abs(value - expected) <= expected * .03, f'{message}: {value}, expected {expected}'

    try:
        if wayland:
            runtime = work / 'runtime'
            runtime.mkdir(mode=0o700)
            env.update(XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS='headless',
                       WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
            env.pop('DISPLAY', None)
            env.pop('WAYLAND_DISPLAY', None)
            compositor = work / 'sway.conf'
            compositor.write_text('output * resolution 1280x800\n')
            start(['sway', '-d', '-c', str(compositor)])
            until(lambda: bool(list(runtime.glob('sway-ipc.*.sock'))), 'Sway did not start')
            env['SWAYSOCK'] = str(next(runtime.glob('sway-ipc.*.sock')))
            env['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*')
                                          if not p.name.endswith('.lock'))

            def nodes(tree):
                yield tree
                for child in tree.get('nodes', []) + tree.get('floating_nodes', []):
                    yield from nodes(child)

            def shown():
                """whether the editor's window is on screen"""
                tree = json.loads(output(['swaymsg', '-t', 'get_tree', '-r']))
                return any(n.get('app_id') == 'raftaar' and n.get('visible') for n in nodes(tree))
            program = work / 'wayland-pointer'
            subprocess.run(['cc', str(ROOT / 'tests/wayland-pointer.c'), '-lwayland-client',
                            '-o', str(program)], check=True)
            pointer = start([str(program)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            assert pointer.stdout.readline() == 'ready\n', 'the pointer did not start'
            moves = itertools.count()

            def events(source, value, count):
                def scroll():
                    # a move first, so that the editor's new window has the pointer
                    pointer.stdin.write(f'{600 + next(moves) % 2} 400 wheel 0 0\n'
                                        f'640 400 {source} {value} {count}\n')
                    pointer.stdin.flush()
                    assert pointer.stdout.readline() == 'ok\n'
                    assert pointer.stdout.readline() == 'ok\n'
                return scroll

            def both(*steps):
                return lambda: [step() for step in steps]
            # a libinput wheel notch is 15; a touchpad's events are a few pixels or less
            notches = offset(events('wheel', 15, 4))
            assert notches > 0, 'the wheel did not scroll'
            near(offset(events('wheel', 15 / 8, 32)), notches, "a high-resolution wheel's eighths of a notch")
            near(offset(events('finger', 2, 50)), notches, '50 touchpad events of 2 px and 4 wheel notches')
            near(offset(events('finger', .4, 250)), notches, '250 touchpad events of 0.4 px')
            near(offset(both(events('finger', 2, 100), events('finger', -.4, 250))), notches,
                 '600 px down, then 250 touchpad events of 0.4 px back up')
            near(offset(events('continuous', .4, 250)), notches, 'a continuous source')
            near(offset(events('finger', .4, 250), '0.5'), notches / 2, 'scroll_sensitivity = 0.5')
            near(offset(events('wheel', 15, 4), '2.5'), notches * 2.5, 'scroll_sensitivity = 2.5')
        else:
            read_fd, write_fd = os.pipe()
            start(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                  pass_fds=(write_fd,))
            os.close(write_fd)
            with os.fdopen(read_fd) as pipe:
                env['DISPLAY'] = ':' + pipe.readline().strip()
            env['RAFTAAR_BACKEND'] = 'x11'
            env.pop('WAYLAND_DISPLAY', None)
            # Openbox handles events only from its main loop on, which --startup runs just before
            started = work / 'openbox-started'
            start(['openbox', '--startup', 'touch ' + str(started)])
            until(started.exists, 'Openbox did not start')

            def shown():
                """whether the editor's window is on screen"""
                return subprocess.run(['xdotool', 'search', '--onlyvisible', '--class', '^raftaar$'],
                                      env=env, capture_output=True).returncode == 0

            def clicks(button, count):
                def scroll():
                    window = output(['xdotool', 'search', '--onlyvisible', '--class', '^raftaar$']).splitlines()[0]
                    output(['xdotool', 'mousemove', '--window', window, '400', '300'])
                    output(['xdotool', 'click', '--repeat', str(count), '--delay', '20', str(button)])
                return scroll
            notches = offset(clicks(5, 5))
            assert notches > 0, 'the wheel did not scroll'
            near(offset(clicks(5, 10)), notches * 2, '10 notches')
            near(offset(clicks(5, 5), '2.5'), notches * 2.5, 'scroll_sensitivity = 2.5')
            near(offset(clicks(5, 5), '0.5'), notches / 2, 'scroll_sensitivity = 0.5')
        print('ok   linux/' + ('wayland' if wayland else 'x11') + '-wheel-and-touchpad-scroll')
    except BaseException:
        for process, log in zip(processes, logs):
            log.flush()
            print('Process ' + str(process.args) + ':', file=sys.stderr)
            print(Path(log.name).read_text()[-4000:], file=sys.stderr)
        raise
    finally:
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
