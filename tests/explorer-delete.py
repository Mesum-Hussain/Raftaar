#!/usr/bin/env python3
"""Explorer deletion confirms with buttons and removes complete trees without following links."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

with tempfile.TemporaryDirectory(prefix='raftaar-delete-') as temporary:
    work = Path(temporary).resolve()
    project = work / 'project'
    project.mkdir()
    config = work / 'config/raftaar/config'
    config.parent.mkdir(parents=True)
    config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                      '[updates]\ncheck = false\n[git]\nenabled = false\n')
    env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_STATE_HOME=str(work / 'state'))

    def run(lines, file=None):
        script = work / 'commands.rsc'
        script.write_text('\n'.join([*lines, 'quit']) + '\n')
        result = subprocess.run([str(EXE), str(project), *([str(file)] if file else []),
                                 '--headless', '1000x700', '--script', str(script)],
                                env=env, capture_output=True, timeout=20, check=True)
        return result.stdout.decode()

    ask = ['click 50 100 right', 'click 110 340', 'print-state']
    target = project / "a folder café ' $test"
    nested = target / 'nested' / 'deeper'
    nested.mkdir(parents=True)
    (nested / 'file.txt').write_text('nested content\n')
    (target / '.hidden').write_text('hidden content\n')
    (target / '.git').mkdir()
    (target / '.git' / 'config').write_text('excluded content\n')
    # Enough entries to require multiple directory-read buffers.
    bulk = target / 'many files'
    bulk.mkdir()
    for number in range(750):
        (bulk / f'{number:04d} file with a longer name and spaces.txt').write_text('content\n')
    outside = work / 'outside'
    outside.mkdir()
    sentinel = outside / 'keep.txt'
    sentinel.write_text('keep\n')
    if os.name != 'nt':
        (target / 'directory-link').symlink_to(outside, target_is_directory=True)
        (target / 'file-link').symlink_to(sentinel)
        (target / 'dangling-link').symlink_to(work / 'missing')
        (target / 'loop').symlink_to(target, target_is_directory=True)
    else:
        subprocess.run(['cmd', '/c', 'mklink', '/J', str(target / 'directory-link'),
                        str(outside)], check=True, capture_output=True)

    output = run([*ask, 'click 650 345', 'print-state'])
    assert 'focus=5 ' in output, output
    assert target.is_dir() and sentinel.read_text() == 'keep\n'
    assert 'focus=0 ' in output, output
    print('ok   explorer/delete-button-cancel')

    output = run([*ask, 'key Escape', 'print-state'])
    assert target.is_dir() and 'focus=0 ' in output, output
    print('ok   explorer/delete-escape-cancel')

    run([*ask, 'click 550 345'])
    assert not target.exists(), 'non-empty directory was not deleted'
    assert sentinel.read_text() == 'keep\n'
    print('ok   explorer/delete-tree-and-preserve-link-targets')

    empty = project / 'empty'
    empty.mkdir()
    run([*ask, 'click 550 345'])
    assert not empty.exists()
    print('ok   explorer/delete-empty-directory')

    file = project / "file café ' $test.txt"
    file.write_text('file content\n')
    output = run(['cmd delete_file', 'print-state', 'click 650 345'], file)
    assert 'focus=5 ' in output and file.read_text() == 'file content\n', output
    run(['cmd delete_file', 'click 550 345'], file)
    assert not file.exists()
    print('ok   explorer/delete-active-file')

    if os.name != 'nt':
        link = project / 'link'
        link.symlink_to(outside, target_is_directory=True)
        run([*ask, 'click 550 345'])
        assert not link.is_symlink() and sentinel.read_text() == 'keep\n'
        print('ok   explorer/delete-selected-directory-link')

    # A failed traversal leaves the directory intact and reports the failure.
    if os.name != 'nt' and os.geteuid() != 0:
        blocked = project / 'blocked'
        blocked.mkdir()
        (blocked / 'keep').write_text('keep\n')
        blocked.chmod(0)
        try:
            run([*ask, 'click 550 345'])
            assert blocked.exists()
        finally:
            blocked.chmod(0o700)
        assert (blocked / 'keep').read_text() == 'keep\n'
        print('ok   explorer/delete-unreadable-directory')
