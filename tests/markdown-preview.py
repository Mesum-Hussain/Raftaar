#!/usr/bin/env python3
"""A Markdown file can be shown as a page in place of its text: the command and the switch in the
pane's corner go between the two, the page takes no edits, and its links open."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

TOGGLE = 'cmd toggle_markdown_preview'
PREVIEW, EDIT = 'click 898 62', 'click 952 62'   # the switch's two halves, in a window 1000 wide
LINK = 'click 285 76'                             # the page's first word

with tempfile.TemporaryDirectory(prefix='raftaar-markdown-') as temporary:
    work = Path(temporary).resolve()
    project = work / 'project'
    project.mkdir()
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[ui]\nsidebar_width = 240\n[files]\nrestore_session = false\n'
                      'restore_project = false\n[updates]\ncheck = false\n[git]\nenabled = false\n',
                      encoding='utf-8')
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
               XDG_STATE_HOME=(work / 'state').as_posix())
    (project / 'page.md').write_text('[other](other.md) and [gone](gone.md)\n\n# Title\n\n'
                                     '- one\n- two\n\n| a | b |\n| --- | ---: |\n| 1 | 2 |\n\n'
                                     '```\ncode\n```\n' + 'More text.\n\n' * 80, encoding='utf-8')
    (project / 'other.md').write_text('Other.\n', encoding='utf-8')
    (project / 'plain.txt').write_text('plain\n', encoding='utf-8')

    def run(lines, name='page.md'):
        script = work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), project.as_posix(), (project / name).as_posix(),
                                 '--headless', '1000x700', '--scale', '1', '--script', script.as_posix()],
                                env=env, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        out = result.stdout.decode('utf-8')
        assert 'unknown command' not in out, out
        return out.splitlines()

    def states(lines, name='page.md'):
        return [line for line in run(lines, name) if line.startswith('tabs=')]

    s = states(['print-state', TOGGLE, 'print-state', TOGGLE, 'print-state'])
    assert ['preview=1' in line for line in s] == [False, True, False], s
    print('ok   markdown-preview/the-command-goes-to-the-page-and-back')

    s = states([TOGGLE, 'print-state'], 'plain.txt')
    assert 'preview=1' not in s[0], s
    print('ok   markdown-preview/only-markdown-has-a-page')

    s = states([PREVIEW, 'print-state', EDIT, 'print-state', 'key End', EDIT, 'print-state'])
    assert ['preview=1' in line for line in s] == [True, False, False], s
    assert ' col=38 ' in s[2], s        # a press on the switch is not one on the text under it
    print('ok   markdown-preview/the-switch-turns-it')

    out = run([TOGGLE, 'type XYZ', 'key BackSpace', 'key Return', 'cmd paste', 'cmd undo',
               'cmd delete_line', 'print-state', TOGGLE, 'type XYZ', 'print-state'])
    s = [line for line in out if line.startswith('tabs=')]
    assert ' dirty=0 ' in s[0] and ' col=1 ' in s[0], s
    assert ' dirty=1 ' in s[1] and ' col=4 ' in s[1], s
    print('ok   markdown-preview/the-page-takes-no-edits')

    s = states([TOGGLE, 'key End', 'key Home', 'key PageDown', 'key Down', 'print-state'])
    assert 'preview=1' in s[0] and ' line=1 col=1 ' in s[0], s
    print('ok   markdown-preview/its-keys-scroll-the-page')

    s = states([TOGGLE, 'cmd find', 'print-state'])
    assert 'preview=1' not in s[0], s
    print('ok   markdown-preview/find-goes-back-to-the-text')

    out = run([TOGGLE, 'wait 50', 'print-tabs', LINK, 'wait 100', 'print-tabs'])
    tabs = [line for line in out if line.startswith('tabs=')]
    assert tabs == ['tabs=*page.md', 'tabs=page.md | *other.md'], tabs
    print('ok   markdown-preview/a-link-opens-its-file')

    out = run([TOGGLE, 'wait 50', 'click 380 76', 'wait 100', 'print-tabs'])
    tabs = [line for line in out if line.startswith('tabs=')]
    assert tabs == ['tabs=*page.md'], tabs
    print('ok   markdown-preview/a-link-to-nothing-opens-nothing')
