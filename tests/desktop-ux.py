#!/usr/bin/env python3
"""Startup project precedence and desktop actions, with isolated user state."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

with tempfile.TemporaryDirectory(prefix='raftaar-desktop-') as temporary:
    work = Path(temporary).resolve()
    project = work / 'project café with spaces'
    other = work / 'other'
    project.mkdir()
    other.mkdir()
    file = project / "file ' $test.txt"
    file.write_text('hello\n')
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
               XDG_STATE_HOME=(work / 'state').as_posix())

    def configure(enabled=None, tabs=True):
        restore = '' if enabled is None else 'restore_project = ' + str(enabled).lower() + '\n'
        config.write_text('[files]\n' + restore +
                          'restore_session = ' + str(tabs).lower() +
                          '\n[updates]\ncheck = false\n[git]\nenabled = false\n')

    def run(paths=(), lines=('print-project', 'print-state', 'quit')):
        script = work / 'commands.rsc'
        script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), *map(str, paths), '--headless', '1000x700',
                                 '--script', str(script)], cwd=other, env=env,
                                capture_output=True, timeout=20, check=True)
        return result.stdout.decode('utf-8')

    def check_project(output, name):
        assert f'project=~/{name}\n' in output, output

    configure()
    run([project, file])
    output = run()
    check_project(output, project.name)
    assert 'tabs=1 ' in output, output
    print('ok   desktop/default-restore-project-and-tabs')

    check_project(run([other]), other.name)
    run([project])
    marker = work / 'state/raftaar/last-project'
    previous = marker.read_bytes()
    # A file opened without a folder brings its folder in as the project: the explorer shows it and
    # new files start there. It is not remembered as the last project.
    output = run([file], ['print-project', 'print-state', 'cmd new_folder', 'print-palette',
                          'key Escape', 'quit'])
    check_project(output, project.name)
    assert 'tabs=1 active=' + file.name in output, output
    assert f'prompt=New folder\nfield={project.as_posix()}/\n' in output, output
    assert marker.read_bytes() == previous
    output = run([file, other / 'second.rb'])
    check_project(output, project.name)
    assert 'tabs=2 ' in output, output
    assert marker.read_bytes() == previous
    print('ok   desktop/explicit-folder-and-file-win')
    output = run(['--empty'])
    assert 'project=\n' in output and 'tabs=0 ' in output, output
    assert marker.read_bytes() == previous
    print('ok   desktop/explicit-empty-window')
    # A program waiting for the editor (EDITOR="raftaar --wait") gets just the file.
    output = run(['--wait', file])
    assert 'project=\n' in output and 'tabs=1 active=' + file.name in output, output
    assert marker.read_bytes() == previous
    print('ok   desktop/wait-file-without-project')

    stored = other / 'stored.rb'
    stored.write_text('stored\n')
    run([other, stored])
    output = run([file], ['type pending', f'open {other.as_posix()}', 'print-project', 'print-state',
                        'key Escape', 'print-project', 'cmd save', f'open {other.as_posix()}',
                        'print-project', 'print-state', 'quit'])
    assert output.count(f'project=~/{project.name}\n') == 2, output
    assert 'dirty=1 ' in output, output
    check_project(output, other.name)
    assert 'tabs=1 active=stored.rb' in output, output
    print('ok   desktop/standalone-folder-switch-preserves-edits-and-restores-session')
    run([project])

    # The folder of a file launch keeps its own session: the launch neither restores nor saves it.
    extra = project / 'extra.txt'
    extra.write_text('extra\n')
    run([project, file, extra])
    sessions = list((work / 'state/raftaar').glob('*project*.session'))
    assert len(sessions) == 1, sessions
    saved = sessions[0].read_bytes()
    loose = project / 'loose.txt'
    loose.write_text('loose\n')
    output = run([loose], ['print-project', 'print-state', 'type x', 'cmd save', 'quit'])
    check_project(output, project.name)
    assert 'tabs=1 active=loose.txt' in output, output
    assert sessions[0].read_bytes() == saved
    assert marker.read_text(encoding='utf-8') == project.as_posix()
    print('ok   desktop/file-folder-keeps-its-session')
    # Opening that folder makes it the project: its session joins the open file and is saved again.
    output = run([loose], [f'open {project.as_posix()}', 'print-project', 'print-state', 'quit'])
    check_project(output, project.name)
    assert 'tabs=3 ' in output, output
    assert b'loose.txt' in sessions[0].read_bytes(), sessions[0].read_bytes()
    print('ok   desktop/opening-the-file-folder-adopts-it')
    run([project, file])

    configure(tabs=False)
    run([project])
    output = run()
    check_project(output, project.name)
    assert 'tabs=0 ' in output, output
    print('ok   desktop/project-without-tab-restoration')

    configure(enabled=False)
    check_project(run(), other.name)
    configure()
    marker = work / 'state/raftaar/last-project'
    marker.write_text((work / 'missing').as_posix(), encoding='utf-8')
    check_project(run(), other.name)
    marker.write_text('', encoding='utf-8')
    check_project(run(), other.name)
    marker.unlink()
    check_project(run(), other.name)
    print('ok   desktop/disabled-missing-empty-first-launch')

    # A project switch is remembered immediately, including without saved tabs.
    configure(tabs=False)
    run([other], [f'open {project.as_posix()}', 'quit'])
    check_project(run(), project.name)
    print('ok   desktop/switched-project')

    # Another instance can replace the marker while this project is still open.
    # Simulate that write, then verify that quitting remembers this project's folder.
    run([project], [f'open {marker.as_posix()}', 'key ctrl+a',
                    f'type {other.as_posix()}', 'cmd save', 'quit'])
    # The marker is UTF-8; Windows would otherwise decode it in the ANSI code page.
    remembered = marker.read_text(encoding='utf-8')
    assert remembered == project.as_posix(), remembered
    check_project(run(), project.name)
    print('ok   desktop/last-closed-project')

    # Never open real desktop applications in the automated suite.
    if os.name != 'nt':
        bin_dir = work / 'bin'
        bin_dir.mkdir()
        opener = bin_dir / ('open' if sys.platform == 'darwin' else 'xdg-open')
        # a call: its arguments a line each, then an empty line
        opener.write_text('#!/bin/sh\nprintf "%s\\n" "$@" "" >> "$RAFTAAR_DESKTOP_LOG"\n')
        opener.chmod(0o755)
        log = work / 'opened'
        env.update(PATH=str(bin_dir) + os.pathsep + os.environ.get('PATH', ''),
                   RAFTAAR_DESKTOP_LOG=str(log))

        def opens(paths, lines):
            """the output, and the opener's calls once there is one. raftaar starts the opener and
            goes on, so each action gets a run of its own: nothing depends on which process ends
            first"""
            log.unlink(missing_ok=True)
            output = run(paths, [*lines, 'quit'])
            deadline = time.monotonic() + 10
            while not (log.exists() and log.read_text().endswith('\n\n')):
                assert time.monotonic() < deadline, f'{lines} opened nothing'
                time.sleep(.02)
            return output, [call.split('\n') for call in log.read_text().split('\n\n')[:-1]]

        links = [('website', 'https://rhun.app'), ('email', 'mailto:hi@rhun.app?subject=rhun%20feedback'),
                 ('feedback', 'https://github.com/vshvedov/rhun/issues')]
        for name, url in links:
            calls = opens([project, file], ['cmd ' + name])[1]
            assert calls == [[url]], (name, calls)
        reveal = ['-R', file.as_posix()] if sys.platform == 'darwin' else [project.as_posix()]
        calls = opens([project, file], ['cmd reveal_file'])[1]
        assert calls == [reveal], calls
        print('ok   desktop/links-and-literal-file-path')

        with config.open('a') as settings:
            settings.write('[ui]\nagents_panel = false\nsidebar_width = 240\n')
        buttons = [*links, ('discord', 'https://discord.gg/Aj4drpFbWf')]
        for x, (_, url) in zip((300, 410, 510, 695), buttons):
            calls = opens([project], ['cmd settings', f'click {x} 166'])[1]
            assert calls == [[url]], (x, calls)
        print('ok   desktop/settings-links')

        # The menu operates on a directory as well as a file, with the same path rules.
        directory = project / 'a folder café'
        directory.mkdir()
        output, calls = opens([project], ['click 50 100 right', 'print-menu', 'click 110 148'])
        label = 'Show in Finder' if sys.platform == 'darwin' else 'Open in File Manager'
        assert label in output, output
        expected = ['-R', directory.as_posix()] if sys.platform == 'darwin' else [project.as_posix()]
        assert calls == [expected], calls
        print('ok   desktop/directory-context-menu-action')
