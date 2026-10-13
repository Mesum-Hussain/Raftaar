#!/usr/bin/env python3
"""Keep installer extension lists and desktop declarations aligned with the grammars."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
# MIME names from the shared MIME database. Ambiguous binary types are excluded.
TEXT_MIMES = '''
text/plain text/markdown text/org text/css text/html text/javascript text/julia text/rust
text/tcl text/vbscript text/vnd.graphviz text/vnd.trolltech.linguist
text/x-adasrc text/x-bibtex text/x-c++hdr text/x-c++src text/x-chdr text/x-cmake
text/x-cobol text/x-common-lisp text/x-crystal text/x-csharp text/x-csrc
text/x-dbus-service text/x-dsrc text/x-elixir text/x-emacs-lisp text/x-erlang
text/x-fortran text/x-go text/x-gradle text/x-groovy text/x-haskell text/x-java
text/x-kotlin text/x-literate-haskell text/x-log text/x-lua text/x-makefile
text/x-matlab text/x-nim text/x-nimscript text/x-objc++src text/x-objcsrc
text/x-ocaml text/x-opencl-src text/x-pascal text/x-patch text/x-python text/x-python3
text/x-rst text/x-sass text/x-scala text/x-scheme text/x-scss text/x-svhdr text/x-svsrc
text/x-systemd-unit text/x-tex text/x-twig text/x-typst text/x-vala text/x-vb
text/x-verilog text/x-vhdl
application/atom+xml application/geo+json application/json application/json5
application/schema+json application/sql application/toml application/vnd.dart
application/x-awk application/x-bat application/x-cue application/x-desktop
application/x-fishscript application/x-perl application/x-php application/x-powershell
application/x-ruby application/x-shellscript application/xhtml+xml application/xml
application/xslt+xml application/yaml
'''.split()
IMAGE_MIMES = '''image/png image/jpeg image/gif image/bmp image/x-icon image/vnd.microsoft.icon image/x-win-bitmap
image/qoi image/x-portable-bitmap image/x-portable-graymap image/x-portable-pixmap
image/x-portable-anymap image/x-tga'''.split()


def text_extensions():
    extensions = {'txt', 'text', 'log', 'conf', 'cfg', 'ini'}
    for grammar in (ROOT / 'runtime/syntax').glob('*.syn'):
        for patterns in re.findall(r'^files\s*=\s*(.*)$', grammar.read_text(), re.M):
            for pattern in patterns.split():
                if re.fullmatch(r'\*\.[A-Za-z0-9_-]+', pattern):
                    extensions.add(pattern[2:].lower())
    return sorted(extensions)


def outputs():
    extensions = text_extensions()
    shell = ROOT / 'install.sh'
    content = shell.read_text()
    content = re.sub(r'(?<=    # BEGIN TEXT EXTENSIONS\n).*?(?=    # END TEXT EXTENSIONS)',
                     "    echo '" + ' '.join(extensions) + "'\n", content, flags=re.S)
    yield shell, content
    windows = ROOT / 'install.ps1'
    content = re.sub(r'(?<=# BEGIN TEXT EXTENSIONS\n).*?(?=# END TEXT EXTENSIONS)',
                     "$textExtensions = @(\n" + '\n'.join(
                         '    ' + ', '.join("'" + e + "'" for e in extensions[i:i + 10]) +
                         (',' if i + 10 < len(extensions) else '') for i in range(0, len(extensions), 10)
                     ) + '\n)\n', windows.read_text(), flags=re.S)
    yield windows, content
    desktop = ROOT / 'assets/raftaar.desktop'
    yield desktop, re.sub(r'^MimeType=.*$', 'MimeType=' + ';'.join(
        ['inode/directory', *sorted(TEXT_MIMES), 'image/svg+xml', *sorted(IMAGE_MIMES)]) + ';',
        desktop.read_text(), flags=re.M)
    plist = ROOT / 'assets/mac/Info.plist'
    content = plist.read_text()
    # Extension-only declarations cover types without a system-defined UTI.
    # Keep them separate: LSItemContentTypes takes precedence in the same dictionary.
    block = '\t\t<dict>\n\t\t\t<key>CFBundleTypeName</key>\n\t\t\t<string>Source and configuration</string>\n\t\t\t<key>CFBundleTypeRole</key>\n\t\t\t<string>Editor</string>\n\t\t\t<key>LSHandlerRank</key>\n\t\t\t<string>Alternate</string>\n\t\t\t<key>CFBundleTypeExtensions</key>\n\t\t\t<array>\n' + ''.join(
        '\t\t\t\t<string>' + e + '</string>\n' for e in extensions) + '\t\t\t</array>\n\t\t</dict>\n'
    content = re.sub(r'\t\t<dict>\n\t\t\t<key>CFBundleTypeName</key>\n\t\t\t<string>Source and configuration</string>.*?\t\t</dict>\n', '', content, flags=re.S)
    at = content.index('\t\t<dict>\n\t\t\t<key>CFBundleTypeName</key>\n\t\t\t<string>Folder</string>')
    content = content[:at] + block + content[at:]
    content = content.replace('\t\t\t\t<string>public.data</string>\n', '')
    yield plist, content


if __name__ == '__main__':
    check = sys.argv[1:] == ['--check']
    if sys.argv[1:] and not check:
        raise SystemExit('usage: tools/file-associations.py [--check]')
    stale = []
    for path, content in outputs():
        if path.read_text() != content:
            if check:
                stale.append(str(path.relative_to(ROOT)))
            else:
                path.write_text(content)
    if stale:
        raise SystemExit('Refresh file associations with tools/file-associations.py: ' + ', '.join(stale))
