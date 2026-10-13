#!/usr/bin/env python3
"""Verify installer choices and registration without changing the user's associations."""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / 'tools/file-associations.py'), '--check'], check=True)
plist = plistlib.loads((ROOT / 'assets/mac/Info.plist').read_bytes())
assert all('public.data' not in d.get('LSItemContentTypes', []) for d in plist['CFBundleDocumentTypes'])
source = next(d for d in plist['CFBundleDocumentTypes'] if d['CFBundleTypeName'] == 'Source and configuration')
assert 'LSItemContentTypes' not in source
assert {'txt', 'md', 'py', 'rs', 'json', 'ts', 'yaml'} <= set(source['CFBundleTypeExtensions'])
assert not {'png', 'jpg', 'gif', 'qoi'} & set(source['CFBundleTypeExtensions'])
images = next(d for d in plist['CFBundleDocumentTypes'] if d['CFBundleTypeName'] == 'Image extensions')
assert 'qoi' in images['CFBundleTypeExtensions']
print('ok   associations/metadata', flush=True)

if os.name == 'nt':
    script = (ROOT / 'install.ps1').read_text()
    functions = script.split('# BEGIN FILE ASSOCIATION FUNCTIONS\n', 1)[1].split('# END FILE ASSOCIATION FUNCTIONS', 1)[0]
    # Registry tests use a temporary subtree, never the user's actual associations.
    tests = r'''
$ErrorActionPreference = 'Stop'
$associationRoot = 'HKCU:\Software\raftaar-association-test-' + [Guid]::NewGuid().ToString('N')
$InstallDir = "C:\Program files café ' $ &\raftaar"
$NoFileAssociations = $false
$NoMakeDefault = $false
$MakeDefault = $false
$NoModifyPath = $false
$openedSettings = @()
function Start-Process($FilePath) { $script:openedSettings += $FilePath }
# VISUAL and EDITOR go to a table, never the user's environment
$userVariables = @{}
function Get-UserVariable([string]$Name) { $script:userVariables[$Name] }
function Set-UserVariable([string]$Name, $Value) {
    if ($null -eq $Value) { $script:userVariables.Remove($Name) } else { $script:userVariables[$Name] = $Value }
}
function Read-Host { throw 'The installer must not prompt for defaults' }
function Notify-FileAssociations { } # No shell refresh for the test registry subtree.
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    Set-AssociationValue "$associationRoot\Classes\.txt" '(default)' 'Other.Text'
    Set-AssociationValue "$associationRoot\Classes\.txt\OpenWithProgids" 'Other.Text' ''
    Set-AssociationValue "$associationRoot\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice" 'ProgId' 'Other.Text'
    Register-FileAssociations
    $command = Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\raftaar.Text\shell\open\command" -Name '(default)'
    Assert ($command -ceq ('"' + (Join-Path $InstallDir 'raftaar.exe') + '" "%1"')) 'Command quoting failed'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\.txt" -Name '(default)') -eq 'Other.Text') 'Existing default changed'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice" -Name 'ProgId') -eq 'Other.Text') 'UserChoice changed'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\raftaar\Capabilities\FileAssociations" -Name '.md') -eq 'raftaar.Text') 'Text registration missing'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\raftaar\Capabilities\FileAssociations" -Name '.qoi') -eq 'raftaar.Image') 'Image registration missing'
    $instructions = Choose-DefaultEditor | Out-String
    Assert ($openedSettings.Count -eq 0) 'Opened Settings without a manual request'
    Assert ($instructions.Contains('-ExecutionPolicy Bypass -File')) 'Manual command missing'
    Assert ($instructions.Contains('Optional: default editor')) 'Manual command heading missing'
    Assert ($instructions.Contains($InstallDir.Replace("'", "''"))) 'Manual command path quoting failed'
    Assert ($userVariables.Count -eq 0) 'Set the editor without a manual request'
    $MakeDefault = $true
    Choose-DefaultEditor | Out-Null
    Assert ($openedSettings.Count -eq 1) 'Manual request did not open Settings'
    # the editor git asks for: raftaar.com, quoted, with forward slashes for git's sh
    $editor = '"C:/Program files café '' \$ &/raftaar/raftaar.com" --wait'
    Assert ($userVariables['VISUAL'] -ceq $editor) "VISUAL is $($userVariables['VISUAL'])"
    Assert ($userVariables['EDITOR'] -ceq $editor) "EDITOR is $($userVariables['EDITOR'])"
    $userVariables.Clear()
    $NoModifyPath = $true
    $said = Set-TerminalEditor | Out-String
    Assert ($userVariables.Count -eq 0) 'NoModifyPath changed the environment'
    Assert ($said.Contains($editor)) 'NoModifyPath did not say what to set'
    $NoModifyPath = $false
    Set-TerminalEditor | Out-Null
    $userVariables['EDITOR'] = 'notepad'
    Remove-TerminalEditor
    Assert (-not $userVariables.ContainsKey('VISUAL')) 'Uninstall left VISUAL'
    Assert ($userVariables['EDITOR'] -eq 'notepad') 'Uninstall removed an editor of the user'
    $installed = $InstallDir
    $InstallDir = 'C:\a`b $HOME\raftaar'
    Assert ((Get-EditorValue) -ceq '"C:/a\`b \$HOME/raftaar/raftaar.com" --wait') "The editor is $(Get-EditorValue)"
    $InstallDir = $installed
    'ok   associations/windows-editor-variables'
    Register-FileAssociations
    $InstallDir = 'C:\Other raftaar'
    Remove-FileAssociations
    Assert (Test-Path -LiteralPath "$associationRoot\Classes\raftaar.Text") 'Removed another installation registration'
    $InstallDir = "C:\Program files café ' $ &\raftaar"
    Remove-FileAssociations
    Assert (-not (Test-Path -LiteralPath "$associationRoot\Classes\raftaar.Text")) 'ProgID left behind'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\.txt\OpenWithProgids" -Name 'Other.Text') -eq '') 'Removed another handler'
    Assert ((Get-ItemPropertyValue -LiteralPath "$associationRoot\Classes\.txt" -Name '(default)') -eq 'Other.Text') 'Uninstall changed another default'
    $NoFileAssociations = $true
    Register-FileAssociations
    Assert (-not (Test-Path -LiteralPath "$associationRoot\Classes\raftaar.Text")) 'Opt-out ignored'
    'ok   associations/windows-register-preserve-defaults-and-uninstall'
} finally {
    if (Test-Path -LiteralPath $associationRoot) { Remove-Item -LiteralPath $associationRoot -Recurse -Force }
}
'''
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'associations.ps1'
        path.write_text(functions + '\n' + tests, encoding='utf-8-sig')
        subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(path)], check=True)
    raise SystemExit(0)

import errno
import fcntl
import pty
import select
import termios
import time

with tempfile.TemporaryDirectory(prefix='raftaar-associations-') as directory:
    temp = Path(directory)
    home = temp / 'home café'
    prefix = home / '.local'
    shim = temp / 'shim'
    shim.mkdir()
    (prefix / 'bin').mkdir(parents=True)
    executable = prefix / 'bin/raftaar'
    executable.write_text('#!/bin/sh\nexit 0\n')
    executable.chmod(0o755)
    desktop = prefix / 'share/applications/raftaar.desktop'
    desktop.parent.mkdir(parents=True)
    desktop.write_bytes((ROOT / 'assets/raftaar.desktop').read_bytes())
    installer = temp / 'install.sh'
    installer.write_text(re.sub(r'^LSREGISTER=.*$', 'LSREGISTER=/nonexistent', (ROOT / 'install.sh').read_text(), flags=re.M))
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               XDG_DATA_HOME=str(prefix / 'share'), XDG_DATA_DIRS='/usr/share',
               PATH=str(shim) + ':' + os.environ['PATH'], RAFTAAR_ASSOC_TEST=str(temp),
               RAFTAAR_RELEASES_URL='file:///nonexistent')
    for name, content in {
        'uname': '#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n',
        'xdg-mime': '''#!/bin/sh
printf '%s\n' "$*" >> "$RAFTAAR_ASSOC_TEST/calls"
case "$1" in
 default) printf '%s' "$2" > "$RAFTAAR_ASSOC_TEST/default";;
 query) cat "$RAFTAAR_ASSOC_TEST/default";;
esac
''',
        'update-desktop-database': '#!/bin/sh\nexit 0\n',
        'gtk-update-icon-cache': '#!/bin/sh\nexit 0\n',
        'xdg-desktop-menu': '#!/bin/sh\nexit 0\n',
        'osascript': '#!/bin/sh\nprintf "%s\\n" "$@" > "$RAFTAAR_ASSOC_TEST/mac-args"\ncat > "$RAFTAAR_ASSOC_TEST/mac-script"\n',
        'curl': '#!/bin/sh\ncat "$RAFTAAR_ASSOC_TEST/install.sh"\n',
    }.items():
        path = shim / name
        path.write_text(content)
        path.chmod(0o755)

    def run(*options, success=True, cwd=None):
        result = subprocess.run(['sh', str(installer), '--configure-files', *options], env=env, cwd=cwd,
                                stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
        assert (result.returncode == 0) == success, result.stderr.decode()
        assert b'Downloading' not in result.stderr
        return result.stderr

    run('--no-make-default')
    assert not (temp / 'calls').exists()
    output = run()
    assert not (temp / 'calls').exists()

    def run_printed_command(output):
        commands = [line.strip().decode() for line in output.splitlines() if line.startswith(b'  curl -fsSL ')]
        assert len(commands) == 1, output
        result = subprocess.run(['sh', '-c', commands[0]], env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=15)
        assert result.returncode == 0, result.stderr.decode()
        return result.stderr

    output = run_printed_command(output)
    calls = (temp / 'calls').read_text().splitlines()
    defaults = [line.split() for line in calls if line.startswith('default ')]
    assert len(defaults) == 1 and defaults[0][1] == 'raftaar.desktop', calls
    assert {'text/plain', 'application/json'} <= set(defaults[0][2:])
    assert not any('image/' in line or 'inode/' in line for line in calls)
    assert not {'text/html', 'application/xhtml+xml'} & set(defaults[0][2:]), defaults
    assert b'raftaar is the default editor' in output
    print('ok   associations/linux-opt-in-and-configure-without-download', flush=True)
    (temp / 'calls').unlink()
    output = run('--make-default', '--prefix', str(home / 'elsewhere'), success=False)
    assert not (temp / 'calls').exists()
    # Failure is reported without pretending the desktop accepted the change.
    (shim / 'xdg-mime').write_text('#!/bin/sh\nexit 1\n')
    output = run('--make-default')
    assert b'Some default associations were not changed' in output
    print('ok   associations/missing-install-and-desktop-failure', flush=True)

    result = subprocess.run(['sh', str(installer), '--make-default'], env=env,
                            stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
    assert result.returncode != 0 and b'requires --configure-files' in result.stderr, result.stderr
    assert b'Downloading' not in result.stderr
    print('ok   associations/install-cannot-change-defaults', flush=True)

    # A piped installer with a terminal still prints instructions without asking for input.
    master, slave = pty.openpty()
    def terminal_session():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    process = subprocess.Popen(['sh', '-s', '--', '--configure-files'], env=env,
                               stdin=subprocess.PIPE, stdout=slave, stderr=slave,
                               preexec_fn=terminal_session)
    os.close(slave)
    process.stdin.write(installer.read_bytes())
    process.stdin.close()
    output = bytearray()
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if not select.select([master], [], [], .1)[0]:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
        assert process.wait(timeout=5) == 0, output
        assert b'[y/N]' not in output and b'--configure-files --make-default' in output, output
        assert not (temp / 'calls').exists()
    finally:
        os.close(master)
        if process.poll() is None:
            process.kill()
            process.wait()
    print('ok   associations/piped-installer-no-terminal-prompt', flush=True)

    # Mac requests use argument data and the bundle ID, never interpolated script code.
    (shim / 'uname').write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; esac\n')
    appdir = home / "Apps ' $ &"
    (appdir / 'raftaar.app').mkdir(parents=True)
    run('--app-dir', str(appdir), '--no-make-default')
    assert not (temp / 'mac-args').exists()
    output = run('--app-dir', str(appdir))
    assert not (temp / 'mac-args').exists()
    run_printed_command(output)
    args = (temp / 'mac-args').read_text().splitlines()
    assert args[:3] == ['-l', 'JavaScript', '-']
    assert args[3] == str(appdir / 'raftaar.app')
    assert {'txt', 'md', 'py'} <= set(args[4].split())
    assert 'LSSetDefaultRoleHandlerForContentType' in (temp / 'mac-script').read_text()
    (shim / 'osascript').write_text('#!/bin/sh\nexit 1\n')
    output = run('--app-dir', str(appdir), '--make-default')
    assert b'Some defaults could not be changed' in output
    print('ok   associations/mac-opt-in-arguments-and-failure', flush=True)

    # --make-default also makes raftaar the editor programs ask for (git's commit message): VISUAL and
    # EDITOR in every shell's startup file, only where a window can open, and gone on --uninstall.
    # The stand-in raftaar writes a message into the file it is given and notes its arguments.
    executable.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$RAFTAAR_ASSOC_TEST/editor-args"\n'
                          'for last; do :; done\n[ "$1" = --wait ] && printf "from raftaar\\n" > "$last"\nexit 0\n')
    env.pop('GIT_EDITOR', None)
    (home / '.zshrc').write_text('alias ll="ls -l"\n')
    (home / '.bashrc').write_text('export EDITOR=vi\n')
    # what bash reads as a login shell here; with bash the login shell or SHELL (as on CI), the Mac
    # runs above gave it a .bash_profile, which would come first
    for name in ('.bash_profile', '.bash_login'):
        (home / name).unlink(missing_ok=True)
    (home / '.profile').write_text('export X=1\n')
    (home / '.tcshrc').write_text('')
    (home / '.config/fish').mkdir(parents=True, exist_ok=True)
    (home / '.config/nushell').mkdir(parents=True, exist_ok=True)
    fish_file = home / '.config/fish/conf.d/raftaar-editor.fish'

    def quoted(path):
        """PATH as sh reads it in single quotes"""
        return "'" + str(path).replace("'", "'\"'\"'") + "'"
    value = quoted(executable) + ' --wait'        # the path has a space: quoted for git's sh

    def editor_in(shell, rc, extra):
        """VISUAL and EDITOR as SHELL exports them after reading RC, with EXTRA in its environment"""
        environment = dict(HOME=str(home), PATH='/usr/bin:/bin', **extra)
        show = 'printenv VISUAL; printenv EDITOR'
        if shell == 'tcsh':
            command = ['tcsh', '-f', '-c', f'source "{rc}"; {show}']
        elif shell == 'fish':
            command = ['fish', '-c', f'source $argv[1]; {show}', str(rc)]
        elif shell == 'nu':
            command = ['nu', '--no-config-file', '-c', f'source "{rc}"; ^printenv VISUAL; ^printenv EDITOR']
        else:
            command = [shell, '-c', '. "$1"; ' + show, shell, str(rc)]
        # stdin from /dev/null: on a socket bash takes itself for an ssh session and reads .bashrc too
        result = subprocess.run(command, env=environment, stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=15)
        return result.stdout.splitlines()

    def check_shells(display, none, expected=None):
        """each shell reads EXPECTED (VALUE) where a window can open (DISPLAY), and keeps its own
        editor without"""
        expected = expected or value
        for shell, rc in (('zsh', home / '.zshrc'), ('bash', home / '.bashrc'), ('dash', home / '.bashrc'),
                          ('bash', home / '.profile'), ('tcsh', home / '.tcshrc'), ('fish', fish_file),
                          ('nu', home / '.config/nushell/env.nu')):
            if not shutil.which(shell):
                continue
            assert editor_in(shell, rc, display) == [expected, expected], (shell, editor_in(shell, rc, display))
            kept = ['vi'] if rc.name == '.bashrc' else []
            assert editor_in(shell, rc, none) == kept, (shell, editor_in(shell, rc, none))

    def blocks(path):
        return path.read_text().splitlines().count('# raftaar editor') if path.exists() else 0

    (shim / 'uname').write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n')
    (shim / 'xdg-mime').write_text('#!/bin/sh\nexit 1\n')     # files stay as they were; the editor does not
    output = run('--make-default')
    assert b'such as git, open raftaar in new terminals' in output, output
    for rc in (home / '.zshrc', home / '.bashrc', home / '.profile', home / '.tcshrc',
               home / '.config/nushell/env.nu'):
        assert blocks(rc) == 1, (rc, rc.read_text())
    assert blocks(fish_file) == 1
    assert not (home / '.bash_profile').exists()       # it would hide .profile from bash
    assert (home / '.zshrc').read_text().startswith('alias ll="ls -l"\n')
    check_shells({'DISPLAY': ':0'}, {})
    check_shells({'WAYLAND_DISPLAY': 'wayland-0'}, {'DISPLAY': '', 'WAYLAND_DISPLAY': ''})
    # as git runs it: through sh, with the file after the editor's words
    note = temp / 'COMMIT_EDITMSG'
    note.write_text('')
    subprocess.run(['sh', '-c', value + ' "$@"', value, str(note)], env=env, check=True)
    assert (temp / 'editor-args').read_text().splitlines() == ['--wait', str(note)]
    assert note.read_text() == 'from raftaar\n'
    if shutil.which('git'):
        repo = temp / 'repo'
        subprocess.run(['git', 'init', '-q', str(repo)], env=env, check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-q', '--allow-empty'], env=dict(env, EDITOR=value, VISUAL=value), check=True)
        log = subprocess.run(['git', '-C', str(repo), 'log', '-1', '--format=%s'], env=env,
                             capture_output=True, text=True, check=True)
        assert log.stdout == 'from raftaar\n', log
    # once more: the block is replaced, not added again
    subprocess.run(['git', 'config', '--global', 'core.editor', 'vim'], env=env, check=True)
    output = run('--make-default')
    assert b"git's core.editor (vim) still comes first" in output, output
    assert blocks(home / '.zshrc') == 1 and blocks(home / '.bashrc') == 1
    # without startup files to change, it only says what to set
    (home / '.zshrc').write_text('')
    output = run('--make-default', '--no-modify-path')
    assert b'set VISUAL and EDITOR to: ' + value.encode() in output, output
    assert blocks(home / '.zshrc') == 0
    # a ! in the path: csh would take it for history unless escaped; given relative to the current
    # folder, and named from anywhere
    bang = temp.resolve() / 'opt !x'
    (bang / 'bin').mkdir(parents=True)
    shutil.copy2(executable, bang / 'bin/raftaar')
    (bang / 'share/applications').mkdir(parents=True)
    shutil.copy2(desktop, bang / 'share/applications/raftaar.desktop')
    run('--make-default', '--prefix', bang.name, cwd=bang.parent)
    check_shells({'DISPLAY': ':0'}, {}, quoted(bang / 'bin/raftaar') + ' --wait')
    print('ok   associations/editor-variables-linux', flush=True)

    # macOS: everywhere but SSH sessions, through the terminal command when it starts this app (as
    # place_wrapper writes it), else through the app's own program
    (shim / 'uname').write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; esac\n')
    ssh = {'SSH_CONNECTION': '192.0.2.1 50000 192.0.2.2 22'}
    executable.write_text(f'#!/bin/sh\nexec "{appdir}/raftaar.app/Contents/MacOS/raftaar" "$@"\n')
    run('--app-dir', str(appdir), '--make-default')
    check_shells({}, ssh)
    executable.write_text('#!/bin/sh\nexec "/Applications/Elsewhere/raftaar.app/Contents/MacOS/raftaar" "$@"\n')
    run('--app-dir', str(appdir), '--make-default')
    check_shells({}, ssh, quoted(appdir / 'raftaar.app/Contents/MacOS/raftaar') + ' --wait')
    print('ok   associations/editor-variables-mac', flush=True)

    # --uninstall takes the blocks away, and leaves the user's lines
    (shim / 'uname').write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n')
    result = subprocess.run(['sh', str(installer), '--uninstall', '--prefix', str(prefix)], env=env,
                            stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr.decode()
    for rc in (home / '.zshrc', home / '.bashrc', home / '.profile', home / '.tcshrc',
               home / '.config/nushell/env.nu'):
        assert blocks(rc) == 0, (rc, rc.read_text())
    assert not fish_file.exists()
    assert (home / '.bashrc').read_text() == 'export EDITOR=vi\n', (home / '.bashrc').read_text()
    assert (home / '.profile').read_text() == 'export X=1\n', (home / '.profile').read_text()
    print('ok   associations/editor-variables-uninstall', flush=True)

subprocess.run([sys.executable, str(ROOT / 'tests/mac-defaults.py')], check=True)
