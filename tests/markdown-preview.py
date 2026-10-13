#!/usr/bin/env python3
"""A Markdown file opens as a page in place of its text: the command and the switch in the pane's
corner go between the two, the page takes no edits, its links open and its text can be copied."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

TOGGLE = 'cmd toggle_markdown_preview'
RENDERED, RAW = 'click 895 62', 'click 954 62'   # the switch's two halves, in a window 1000 wide
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
    assert ['preview=1' in line for line in s] == [True, False, True], s
    print('ok   markdown-preview/it-opens-as-a-page-and-the-command-goes-to-the-text-and-back')

    s = states(['print-state', TOGGLE, 'print-state'], 'plain.txt')
    assert not any('preview=1' in line for line in s), s
    print('ok   markdown-preview/only-markdown-has-a-page')

    s = states([RAW, 'print-state', RENDERED, 'print-state', RAW, 'key End', RAW, 'print-state'])
    assert ['preview=1' in line for line in s] == [False, True, False], s
    assert ' col=38 ' in s[2], s        # a press on the switch is not one on the text under it
    print('ok   markdown-preview/the-switch-turns-it')

    out = run(['type XYZ', 'key BackSpace', 'key Return', 'cmd paste', 'cmd undo',
               'cmd delete_line', 'print-state', TOGGLE, 'type XYZ', 'print-state'])
    s = [line for line in out if line.startswith('tabs=')]
    assert ' dirty=0 ' in s[0] and ' col=1 ' in s[0], s
    assert ' dirty=1 ' in s[1] and ' col=4 ' in s[1], s
    print('ok   markdown-preview/the-page-takes-no-edits')

    s = states(['key End', 'key Home', 'key PageDown', 'key Down', 'print-state'])
    assert 'preview=1' in s[0] and ' line=1 col=1 ' in s[0], s
    print('ok   markdown-preview/its-keys-scroll-the-page')

    s = states(['cmd find', 'print-state'])
    assert 'preview=1' not in s[0], s
    print('ok   markdown-preview/find-goes-back-to-the-text')

    out = run(['wait 50', 'print-tabs', LINK, 'wait 100', 'print-tabs'])
    tabs = [line for line in out if line.startswith('tabs=')]
    assert tabs == ['tabs=*page.md', 'tabs=page.md | *other.md'], tabs
    print('ok   markdown-preview/a-link-opens-its-file')

    out = run(['wait 50', 'click 380 76', 'wait 100', 'print-tabs'])
    tabs = [line for line in out if line.startswith('tabs=')]
    assert tabs == ['tabs=*page.md'], tabs
    print('ok   markdown-preview/a-link-to-nothing-opens-nothing')

    def pasted(lines, name):
        """what the clipboard holds after the lines: pasted into a new file and printed"""
        out = run(['wait 50', *lines, 'wait 50', 'cmd new_file', 'cmd paste', 'print-doc'], name)
        return '\n'.join(out[:out.index('<eod>')])

    (project / 'words.md').write_text('Some **bold** words and `code` here.\n\nSecond one.\n',
                                      encoding='utf-8')
    assert pasted(['cmd select_all', 'cmd copy'], 'words.md') == \
        'Some bold words and code here.\nSecond one.', pasted(['cmd select_all', 'cmd copy'], 'words.md')
    print('ok   markdown-preview/select-all-and-copy-take-the-text-of-the-page')

    text = pasted(['move 312 76', 'down', 'wait 20', 'move 380 76', 'wait 20', 'up', 'cmd copy'],
                  'words.md')
    assert text == 'bold words', repr(text)
    print('ok   markdown-preview/a-drag-selects-by-the-character')

    (project / 'code.md').write_text('```python\ndef f():\n    return 1\n```\n', encoding='utf-8')
    text = pasted(['click 940 76'], 'code.md')
    assert text == 'def f():\n    return 1', repr(text)
    print('ok   markdown-preview/copy-takes-a-code-block')

    # a page with what HTML it knows, a picture that is there and one that is not: it draws
    (project / 'pic.ppm').write_bytes(b'P6 2 2 255\n' + bytes(range(12)))
    (project / 'html.md').write_text('<h1 align="center">Title</h1>\n\n<p align="center">\n'
                                     '<img src="pic.ppm" width="40"><br><b>bold</b></p>\n\n'
                                     '![here](pic.ppm) ![gone](gone.png) ![web](https://example.com/a.png)\n',
                                     encoding='utf-8')
    s = states(['wait 50', 'print-state', 'key End', 'wait 50', 'print-state'], 'html.md')
    assert all('preview=1' in line for line in s) and len(s) == 2, s
    print('ok   markdown-preview/html-and-pictures-draw')
