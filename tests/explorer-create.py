#!/usr/bin/env python3
"""Explorer creation: the header's New File and New Folder buttons, the prompt saying what it creates,
and the menu of the empty space below the rows (the project folder, without Rename and Delete)."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

# 1000x700 at scale 1: the explorer header's buttons (New File, New Folder, Refresh) end 8 points from
# its right edge at 240; the first row is at 80. A menu opened at 600 is moved up to fit; its items are
# 32 high, with lines between the groups: Open in Terminal, the file manager, New File, New Folder,
# Copy Path, Refresh.
NEW_FILE = 'click 162 60'
NEW_FOLDER = 'click 190 60'
EMPTY = 'click 120 600 right'
ITEM = ['click 180 574', 'click 180 606', 'click 180 646', 'click 180 534']   # New File, New Folder, Copy Path, the file manager

with tempfile.TemporaryDirectory(prefix='raftaar-create-') as temporary:
    work = Path(temporary).resolve()
    project = work / "project café ' $test"
    project.mkdir()
    (project / 'src').mkdir()
    (project / 'src' / 'main.c').write_text('int main(void) { return 0; }\n')
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n[ui]\nagents_panel = false\n'
                      # nothing draws frames by itself: a blinking cursor, a tooltip
                      'tooltips = false\nsidebar_width = 240\n[editor]\ncursor_blink = false\n')
    env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_STATE_HOME=str(work / 'state'))

    def run(lines):
        script = work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), str(project), '--headless', '1000x700', '--scale', '1',
                                 '--script', str(script)], env=env, capture_output=True, timeout=20, check=True)
        return result.stdout.decode('utf-8')

    def field(output):
        # the prompt's text, with the platform's separators as /
        lines = [line for line in output.splitlines() if line.startswith('field=')]
        return [line[6:].replace('\\', '/') for line in lines]

    output = run([NEW_FILE, 'print-palette', 'type docs/notes.md', 'key Return', 'print-state'])
    assert 'prompt=New file\n' in output, output
    assert field(output)[0].endswith('/' + project.name + '/'), output
    assert (project / 'docs' / 'notes.md').is_file()
    assert 'active=notes.md ' in output, output
    print('ok   explorer/new-file-button')

    output = run([NEW_FOLDER, 'print-palette', 'type assets/icons', 'key Return', 'print-palette'])
    assert 'prompt=New folder\n' in output and output.endswith('none\n'), output
    assert (project / 'assets' / 'icons').is_dir()
    print('ok   explorer/new-folder-button')

    # The hint keeps its distance from the field: the card is 640 wide from x 180 and 48 down, the
    # title takes 32, the field 32 more from 88, so its lower border is row 119. The rows just under
    # it, where the hint's text starts, stay the card's color.
    shot = work / 'prompt.ppm'
    run([NEW_FOLDER, f'shot {shot.as_posix()}'])
    magic, size, maximum, pixels = shot.read_bytes().split(b'\n', 3)
    width = int(size.split()[0])
    def pixel(x, y):
        return pixels[(y * width + x) * 3:(y * width + x) * 3 + 3]
    card = pixel(700, 123)
    assert all(pixel(x, y) == card for y in range(120, 126) for x in range(196, 600)), 'hint touches the field'
    assert any(pixel(x, y) != card for y in range(126, 144) for x in range(196, 600)), 'no hint under the field'
    print('ok   explorer/prompt-hint-spacing')

    # The empty space's menu creates in the project folder, even after a folder's row was selected.
    output = run(['click 50 100', EMPTY, 'print-menu', ITEM[1], 'print-palette', 'type empty-space',
                  'key Return'])
    label = {'darwin': 'Show in Finder', 'win32': 'Show in Explorer'}.get(sys.platform, 'Open in File Manager')
    assert f'Open in Terminal\n{label}\n-\nNew File\nNew Folder\n-\nCopy Path\nRefresh\n' in output, output
    assert 'Rename' not in output and 'Delete' not in output, output
    assert 'prompt=New folder\n' in output and field(output)[0].endswith('/' + project.name + '/'), output
    assert (project / 'empty-space').is_dir()
    output = run([EMPTY, ITEM[0], 'print-palette', 'key Escape'])
    assert 'prompt=New file\n' in output and field(output)[0].endswith('/' + project.name + '/'), output
    print('ok   explorer/empty-space-menu-creates-at-the-top')

    output = run([EMPTY, ITEM[2], 'cmd new_file', 'key ctrl+v', 'print-doc'])
    assert output.replace('\\', '/').rstrip('\n').removesuffix('<eod>').rstrip('\n').endswith('/' + project.name), output
    print('ok   explorer/empty-space-copy-path')

    # A clicked item runs once the menu is drawn whole, and the frame without the menu follows at
    # once: the menu stayed on screen, cut after Copy Path, until the pointer moved. (The wait lets the
    # frames of startup pass first.)
    output = run(['wait 300', EMPTY, ITEM[2], 'print-frames', 'wait 100', 'print-frames', 'print-menu'])
    frames = [int(line[7:]) for line in output.splitlines() if line.startswith('frames=')]
    assert frames[1] >= 1 and output.endswith('none\n'), output
    print('ok   explorer/menu-click-redraws')

    # Rename and Delete never take the project folder from that menu.
    output = run([EMPTY, 'key Escape', 'cmd focus_explorer', 'cmd delete_file', 'print-state',
                  'cmd rename_file', 'print-palette'])
    assert 'focus=5 ' not in output and output.endswith('none\n'), output
    assert project.is_dir() and (project / 'src' / 'main.c').is_file()
    print('ok   explorer/empty-space-keeps-project-safe')
