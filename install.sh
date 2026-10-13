#!/bin/sh
# Installs raftaar from its GitHub releases, updates it and removes it; no root needed.
#   curl -fsSL https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
#   wget -qO- https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
#   ... | sh -s -- [options]
#
#   --version X             install X instead of the latest release
#   --prefix DIR            Linux: install under DIR (default ~/.local)
#   --app-dir DIR           macOS: where rhun.app goes (default /Applications, or ~/Applications
#                           when that is not writable)
#   --no-modify-path        leave shell startup files alone (by default every shell the user has
#                           gets raftaar's folder on PATH: zsh, bash, sh, fish, nushell, tcsh)
#   --make-default          with --configure-files: use raftaar for text, source and configuration files,
#                           and as the editor programs such as git ask for (VISUAL and EDITOR)
#   --no-make-default       accepted for compatibility; installation never prompts for defaults
#   --configure-files       configure an existing installation without downloading it
#   --uninstall             remove what the installer put in place (settings stay)
#   --update --target PATH  what raftaar runs to update itself: replace the installation at PATH (the
#                           binary, or on macOS the .app) with --version
#
# RAFTAAR_RELEASES_URL and RAFTAAR_TEAM_ID are for tests: another place for the releases, and the team
# the macOS app must be signed by.
#
# Everything is in functions called from the last line, so a download cut short runs nothing.

set -eu

RELEASES=https://github.com/vshvedov/rhun/releases
TEAM_ID=G29V3JRMJJ
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

output_style() {
    bold='' dim='' cyan='' green='' red='' reset=''
    if [ -t 2 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
        bold=$(printf '\033[1m') dim=$(printf '\033[2m')
        cyan=$(printf '\033[36m') green=$(printf '\033[32m') red=$(printf '\033[31m')
        reset=$(printf '\033[0m')
    fi
}

say() {
    if [ -z "$quiet" ]; then printf '  %s›%s %s\n' "$cyan" "$reset" "$*" >&2; fi
}

banner() {
    printf '\n%s%s' "$bold" "$cyan" >&2
    cat <<'EOF' >&2
         _       ^
    _ __| |__  _   _ _ __
   | '__| '_ \| | | | '_ \
   | |  | | | | |_| | | | |
   |_|  |_| |_|\__,_|_| |_|
EOF
    printf '%s\n  %sraftaar installer%s\n\n' "$reset" "$dim" "$reset" >&2
}

installed() {
    printf '\n  %s✓%s %sraftaar %s is installed%s\n  %s%s%s\n\n' \
        "$green" "$reset" "$bold" "$version" "$reset" "$dim" "$1" "$reset" >&2
}

fail() {
    printf '  %s✗%s raftaar install: %s\n' "$red" "$reset" "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
usage: install.sh [options]   (curl -fsSL .../install.sh | sh -s -- [options])
  --version X             install X instead of the latest release
  --prefix DIR            Linux: install under DIR (default ~/.local)
  --app-dir DIR           macOS: where rhun.app goes (default /Applications)
  --no-modify-path        leave shell startup files alone
  --configure-files       configure an existing installation without downloading it
                          add --make-default to make raftaar the default editor manually
                          (files, and VISUAL and EDITOR for git and the like)
  --uninstall             remove what the installer put in place (settings stay)
EOF
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# platform: sets os (linux, mac) and the archive's name ending
platform() {
    msg="raftaar runs on Linux x86-64 and macOS on Apple silicon"
    case "$(uname -s)" in
    Linux)
        case "$(uname -m)" in
        x86_64 | amd64) os=linux; ending=linux-x86_64.tar.gz; platform_name='Linux, x86-64' ;;
        *) fail "$msg; this is Linux on $(uname -m)" ;;
        esac
        ;;
    Darwin)
        # a shell under Rosetta says x86_64: ask the hardware
        if [ "$(uname -m)" = arm64 ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
            os=mac; ending=macos-arm64.zip; platform_name='macOS, Apple silicon'
        else
            fail "$msg; this Mac has an Intel processor"
        fi
        ;;
    *) fail "$msg; this is $(uname -s)" ;;
    esac
}

# downloader: curl, else wget
downloader() {
    if have curl; then
        dl=curl
    elif have wget; then
        dl=wget
    else
        fail "needs curl or wget to download raftaar"
    fi
}

# fetch URL FILE [progress]
fetch() {
    progress=${3:-}
    if [ "$dl" = curl ]; then
        url=$1 file=$2
        set -- -fsSL
        if [ -z "$quiet" ] && [ -t 2 ] && [ "$progress" = progress ]; then set -- -fL --progress-bar; fi
        # Bound connection setup and stalled transfers, without limiting healthy downloads.
        set -- "$@" --connect-timeout 10 --speed-limit 1 --speed-time 30 --retry 3
        if [ -z "${RAFTAAR_RELEASES_URL:-}" ]; then set -- "$@" --proto =https --proto-redir =https; fi
        if [ -n "$quiet" ]; then
            # Recovered retries stay quiet; report diagnostics only when downloading fails.
            curl "$@" -o "$file" "$url" 2>"$tmp/download-errors" && return 0
            cat "$tmp/download-errors" >&2
            return 1
        fi
        curl "$@" -o "$file" "$url"
    else
        url=$1 file=$2
        set -- -nv
        if [ -n "$quiet" ]; then
            set -- -q
        elif [ -t 2 ] && [ "$progress" = progress ]; then
            set -- -nv --show-progress
            wget "$@" --dns-timeout=10 --connect-timeout=10 --read-timeout=30 --tries=4 \
                --retry-on-http-error=429,500,502,503,504 -O "$file" "$url"
            return $?
        fi
        wget "$@" --dns-timeout=10 --connect-timeout=10 --read-timeout=30 --tries=4 \
            --retry-on-http-error=429,500,502,503,504 -O "$file" "$url" 2>"$tmp/download-errors" && return 0
        cat "$tmp/download-errors" >&2
        return 1
    fi
}

valid_version() {
    [ ${#1} -le 31 ] && printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
}

latest_version() {
    say 'Checking latest release'
    fetch "$base/latest/download/VERSION" "$tmp/VERSION" || fail "could not find the latest release at $base"
    tr -d ' \r\n' < "$tmp/VERSION"
}

# download: the archive of $version into $tmp, checked against the release's SHA256SUMS
download() {
    name=raftaar-$version-$ending
    say "Downloading raftaar $version"
    fetch "$base/download/v$version/$name" "$tmp/$name" progress || fail "could not download $name; is $version a release?"
    say 'Checking download integrity'
    fetch "$base/download/v$version/SHA256SUMS" "$tmp/SHA256SUMS" || fail "could not download the checksums of $version"
    want=$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")
    [ -n "$want" ] || fail "$name is not in the checksums of $version"
    if have sha256sum; then
        got=$(sha256sum "$tmp/$name" | awk '{ print $1 }')
    elif have shasum; then
        got=$(shasum -a 256 "$tmp/$name" | awk '{ print $1 }')
    else
        fail "needs sha256sum or shasum to check the download"
    fi
    [ "$got" = "$want" ] || fail "$name does not match its checksum; nothing was installed"
    say 'Download verified'
}

# installed_version TARGET: the version the installation reports, or nothing
installed_version() {
    exe=$1
    if [ "$os" = mac ]; then exe=$1/Contents/MacOS/raftaar; fi
    if [ -x "$exe" ]; then
        "$exe" --version 2>/dev/null | sed -n 's/^raftaar //p' || true
    fi
}

# ---------------- Linux ----------------

unpack_linux() {
    say 'Unpacking archive'
    mkdir "$tmp/x"
    tar -xzf "$tmp/$name" -C "$tmp/x" || fail "could not unpack $name"
    src=$tmp/x/raftaar-$version
    [ -f "$src/bin/raftaar" ] || fail "$name has no bin/raftaar"
}

# place_binary DEST: a new file renamed over the old one, so a running raftaar keeps its copy
place_binary() {
    dir=$(dirname "$1")
    mkdir -p "$dir"
    cp "$src/bin/raftaar" "$dir/.raftaar.new"
    chmod 755 "$dir/.raftaar.new"
    mv -f "$dir/.raftaar.new" "$1"
}

# place_desktop PREFIX EXE: the desktop entry, which starts EXE by its path (graphical sessions often
# lack ~/.local/bin in PATH), and the icons
place_desktop() {
    apps=$1/share/applications
    mkdir -p "$apps"
    exe=$2
    case "$exe" in *" "*) exe="\"$exe\"" ;; esac
    exe=$(printf '%s' "$exe" | sed 's/[&|\\]/\\&/g')
    sed "s|^Exec=raftaar |Exec=$exe |" "$src/share/applications/raftaar.desktop" > "$apps/.raftaar.desktop.new"
    mv -f "$apps/.raftaar.desktop.new" "$apps/raftaar.desktop"
    for d in scalable 256x256 512x512; do
        for f in "$src/share/icons/hicolor/$d/apps"/raftaar.*; do
            if [ -f "$f" ]; then
                mkdir -p "$1/share/icons/hicolor/$d/apps"
                cp "$f" "$1/share/icons/hicolor/$d/apps/"
            fi
        done
    done
    refresh_desktop "$1"
}

# refresh_desktop PREFIX: menus and icon caches of whatever desktop there is
refresh_desktop() {
    if have update-desktop-database; then update-desktop-database -q "$1/share/applications" 2>/dev/null || true; fi
    if have gtk-update-icon-cache; then gtk-update-icon-cache -qtf "$1/share/icons/hicolor" 2>/dev/null || true; fi
    if have xdg-desktop-menu; then xdg-desktop-menu forceupdate 2>/dev/null || true; fi
    case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*)
        if have kbuildsycoca6; then
            kbuildsycoca6 >/dev/null 2>&1 || true
        elif have kbuildsycoca5; then
            kbuildsycoca5 >/dev/null 2>&1 || true
        fi
        ;;
    esac
}

# ---------------- macOS ----------------

unpack_mac() {
    say 'Unpacking archive'
    mkdir "$tmp/x"
    ditto -x -k "$tmp/$name" "$tmp/x" || fail "could not unpack $name"
    src=$tmp/x/rhun.app
    [ -d "$src" ] || fail "$name has no rhun.app"
    say 'Verifying app signature'
    codesign --verify --strict --deep "$src" 2>/dev/null || fail "the signature of rhun.app is not valid; nothing was installed"
    team=$(codesign -dv "$src" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$team" = "${RAFTAAR_TEAM_ID:-$TEAM_ID}" ] || fail "rhun.app is not signed by raftaar's developer ($team); nothing was installed"
}

# place_app DEST: the bundle unpacked beside DEST and swapped in by renames, so a running raftaar keeps
# its code
place_app() {
    dir=$(dirname "$1")
    mkdir -p "$dir"
    rm -rf "$dir/.rhun.app.new" "$dir/.rhun.app.old"
    ditto "$src" "$dir/.rhun.app.new"
    if [ -e "$1" ]; then mv "$1" "$dir/.rhun.app.old"; fi
    mv "$dir/.rhun.app.new" "$1"
    rm -rf "$dir/.rhun.app.old"
    if [ -x "$LSREGISTER" ]; then "$LSREGISTER" -f "$1" >/dev/null 2>&1 || true; fi
}

# place_wrapper APP: ~/.local/bin/raftaar starts the app's binary from a terminal
place_wrapper() {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/sh\nexec "%s/Contents/MacOS/raftaar" "$@"\n' "$1" > "$HOME/.local/bin/.raftaar.new"
    chmod 755 "$HOME/.local/bin/.raftaar.new"
    mv -f "$HOME/.local/bin/.raftaar.new" "$HOME/.local/bin/raftaar"
}

default_app_dir() {
    if [ -w /Applications ]; then echo /Applications; else echo "$HOME/Applications"; fi
}

# Text extensions are kept in sync with the built-in grammars by tools/file-associations.py.
text_extensions() {
    # BEGIN TEXT EXTENSIONS
    echo 'ada adb adoc ads applescript asciidoc asm astro atom awk bash bat bazel bib bzl c capnp cbl cc cfg cjs cl clj cljc cljs cls cmake cmd cob cobol comp conf cpp cppm cpy cr cron crontab cs cshtml csproj css csx cts cu cue cuh cxx d dart ddl desktop dhall di diff djhtml dockerfile dot dpk dpr dtx ebuild editorconfig edn ejs el elm env erb erl escript ex exs f f03 f08 f77 f90 f95 fish fnl for frag fs fsi fsproj fsscript fsx gemspec geojson geom gleam glsl go gql gradle graphql groovy gv gvy h haml handlebars hbs hcl hh hlsl hpp hrl hs htm html http hx hxx idr inc ini ipp itcl iuml ixx j2 jade janet java jinja jinja2 jl js json json5 jsonc jsonl jsonnet jsx just kdl ksh kt kts lean less lhs libsonnet lidr liquid lisp log lpr ltx lua m mak markdown md mdx mermaid metal mjs mk ml mli mll mly mm mmd mojo mount mts mustache nasm ndjson nginx nim nimble nims ninja nix njk nomad nunjucks odin org p6 pas patch php phtml pkl pl pl6 plantuml plist pm pm6 pp prisma prolog properties props proto ps1 psd1 psm1 psql pu pug puml purs py pyi pyw r rake raku rakumod rakutest razor rb rego rest rhtml rkt rmd rockspec ron rs rss rst s sass sbt sc scala scm scss service sh slim socket sol sql ss star sty sv svelte svg svh swift syn t target targets tcl tesc tese tex text tf tfvars theme thrift timer tk toml tpp ts tsx twig txt typ v vala vapi vb vbs vcxproj vert vh vhd vhdl vim vsh vue webmanifest wgsl wsdl xaml xhtml xml xsd xsl xslt yaml yml zig zon zsh'
    # END TEXT EXTENSIONS
}

quote_arg() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

print_default_editor_command() {
    url=$base/latest/download/install.sh
    [ -z "$version" ] || url=$base/download/v$version/install.sh
    if [ "$os" = linux ]; then option=--prefix; destination=$prefix; else option=--app-dir; destination=$appdir; fi
    printf '\n%s%s  Optional: default editor\n  ========================%s\n' "$bold" "$cyan" "$reset" >&2
    say 'To use raftaar as your default editor, for files and for git, run this command manually:'
    printf '%s%s  curl -fsSL %s | sh -s -- --configure-files --make-default %s %s%s\n\n' \
        "$bold" "$green" "$(quote_arg "$url")" "$option" "$(quote_arg "$destination")" "$reset" >&2
}

choose_default_editor() {
    if [ "$make_default" != yes ]; then print_default_editor_command; return 0; fi
    set_file_defaults
    if [ "$os" = linux ]; then
        set_editor "$prefix/bin/raftaar"
    elif [ -x "$HOME/.local/bin/raftaar" ] && grep -qF "\"$appdir/rhun.app/Contents/MacOS/raftaar\"" "$HOME/.local/bin/raftaar"; then
        set_editor "$HOME/.local/bin/raftaar"     # the terminal command, when it starts this app
    else
        set_editor "$appdir/rhun.app/Contents/MacOS/raftaar"
    fi
}

# set_file_defaults: raftaar opens text, source and configuration files
set_file_defaults() {
    if [ "$os" = linux ]; then
        desktop=$prefix/share/applications/raftaar.desktop
        [ -f "$desktop" ] || fail "no desktop entry at $desktop; rerun the installer"
        if ! have xdg-mime; then
            say 'Default editor was not changed: install xdg-utils or choose raftaar in your desktop settings'
            return 0
        fi
        # xdg-mime resolves desktop IDs through XDG_DATA_HOME and XDG_DATA_DIRS.
        # Custom prefixes must be visible to the desktop too, not just to this process.
        data_home=${XDG_DATA_HOME:-$HOME/.local/share}
        visible=no
        [ "$prefix/share" = "$data_home" ] && visible=yes
        old_ifs=$IFS; IFS=:
        for data_dir in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
            [ "$prefix/share" = "$data_dir" ] && visible=yes
        done
        IFS=$old_ifs
        if [ "$visible" = no ]; then
            say "Default editor was not changed: add $prefix/share to your desktop's XDG_DATA_DIRS first"
            return 0
        fi
        types=$(sed -n 's/^MimeType=//p' "$desktop" | tr ';' '\n' | \
            sed '/^$/d; /^inode\//d; /^image\//d; /^text\/html$/d; /^application\/xhtml+xml$/d; /^x-scheme-handler\//d')
        if [ -z "$types" ]; then
            say 'Default editor was not changed: the desktop entry has no text types; update raftaar first'
            return 0
        fi
        missed=0
        # one call for every type: each xdg-mime run rewrites mimeapps.list
        # shellcheck disable=SC2086
        xdg-mime default raftaar.desktop $types || true
        for type in $types; do
            [ "$(xdg-mime query default "$type" 2>/dev/null)" = raftaar.desktop ] || missed=$((missed + 1))
        done
        if [ "$missed" = 0 ]; then
            say 'raftaar is the default editor for text and code files; browser and image defaults are kept'
        else
            say "Some default associations were not changed ($missed); choose them in your desktop settings"
        fi
    else
        [ -d "$appdir/rhun.app" ] || fail "no rhun.app in $appdir; set --app-dir or rerun the installer"
        # Use Launch Services, rather than writing its private preferences. Arguments are data.
        if ! osascript -l JavaScript - "$appdir/rhun.app" "$(text_extensions)" <<'JXA'
ObjC.import('Foundation');
ObjC.import('CoreServices');
function run(argv) {
    var bundle = $.NSBundle.bundleWithPath(argv[0]);
    if (!bundle || ObjC.unwrap(bundle.bundleIdentifier) !== 'com.r13.raftaar')
        throw new Error('The installed raftaar app was not found');
    var seen = {}, failures = [];
    var preserveTypes = ['public.image', 'public.html', 'public.xhtml', 'public.url'];
    argv[1].split(' ').forEach(function(ext) {
        var uti = $.UTTypeCreatePreferredIdentifierForTag($('public.filename-extension'), $(ext), $('public.text'));
        if (!uti) return;
        // HTML viewing is tied to the default browser. Keep browser and image handlers intact.
        if (preserveTypes.some(function(type) { return $.UTTypeConformsTo(uti, $(type)); })) return;
        var name = ObjC.unwrap(ObjC.castRefToObject(uti));
        if (seen[name]) return;
        seen[name] = true;
        var result = $.LSSetDefaultRoleHandlerForContentType(uti, 0xffffffff, bundle.bundleIdentifier);
        var handler = $.LSCopyDefaultRoleHandlerForContentType(uti, 0xffffffff);
        if (result !== 0 || !handler || ObjC.unwrap(ObjC.castRefToObject(handler)) !== 'com.r13.raftaar')
            failures.push(ext);
    });
    if (failures.length) throw new Error('Could not change defaults for: ' + failures.join(', '));
}
JXA
        then
            say 'Some defaults could not be changed. In Finder, use Get Info > Open with > raftaar > Change All for those types'
        else
            say 'raftaar is the default editor for text and code files; browser and image defaults are kept'
        fi
    fi
}

# set_editor EXE: programs that wait for an editor (git's commit message, crontab -e) open raftaar: VISUAL
# and EDITOR are "EXE --wait" in every shell the user has, between "# raftaar editor" and "# raftaar editor
# end" in its startup file. Only where a window can open (a display on Linux, outside SSH on macOS):
# a session without one keeps the editor it had, rather than one that cannot start.
set_editor() {
    case $1 in
    *[!A-Za-z0-9/._+@%:,~-]*) value="$(quote_arg "$1") --wait" ;;
    *) value="$1 --wait" ;;
    esac
    if [ -z "$modify_path" ]; then
        say "to edit commit messages in raftaar, set VISUAL and EDITOR to: $value"
        return 0
    fi
    q=$(quote_arg "$value")
    if [ "$os" = linux ]; then
        posix_test='[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]'
        fish_test='test -n "$DISPLAY$WAYLAND_DISPLAY"'
        nu_test='($env.DISPLAY? | is-not-empty) or ($env.WAYLAND_DISPLAY? | is-not-empty)'
        # csh substitutes a whole line before it runs, so an unset variable is read only in its own if
        csh_pre='set raftaar_display = ""\nif ( $?DISPLAY ) then\n    set raftaar_display = "$DISPLAY"\nendif\nif ( $?WAYLAND_DISPLAY ) then\n    set raftaar_display = "$raftaar_display$WAYLAND_DISPLAY"\nendif\n'
        csh_test='( "$raftaar_display" != "" )'
        csh_post='\nunset raftaar_display'
    else
        posix_test='[ -z "${SSH_CONNECTION:-}" ]'
        fish_test='not set -q SSH_CONNECTION'
        nu_test='($env.SSH_CONNECTION? | is-empty)'
        csh_pre=''
        csh_test='( ! $?SSH_CONNECTION )'
        csh_post=''
    fi
    posix="if $posix_test; then export VISUAL=$q EDITOR=$q; fi"
    done_shells=''
    for sh in $(user_shells); do
        case $sh in
        zsh) put_editor "${ZDOTDIR:-$HOME}/.zshrc" "$posix" zsh ;;
        bash)
            put_editor "$HOME/.bashrc" "$posix" bash
            login=$(bash_login)
            if [ -n "$login" ]; then put_editor "$login" "$posix" ''; fi
            ;;
        sh | dash | ksh | mksh | yash | ash | busybox) put_editor "$HOME/.profile" "$posix" "$sh" ;;
        fish)
            f=${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/raftaar-editor.fish
            mkdir -p "$(dirname "$f")"
            printf '# raftaar editor\nif %s\n    set -gx VISUAL %s\n    set -gx EDITOR %s\nend\n# raftaar editor end\n' \
                "$fish_test" "$q" "$q" > "$f"
            done_shells="$done_shells fish"
            ;;
        nu)
            d=$(nu_dir)
            if [ -n "$d" ]; then
                # a double-quoted nushell string: its single quotes cannot hold a quoted path
                nq=\"$(printf '%s' "$value" | sed 's/[\\"]/\\&/g')\"
                put_editor "$d/env.nu" "load-env (if $nu_test { {VISUAL: $nq, EDITOR: $nq} } else { {} })" nu
            fi
            ;;
        tcsh | csh)
            f=$HOME/.tcshrc
            if [ ! -f "$f" ] && { [ -f "$HOME/.cshrc" ] || [ "$sh" = csh ]; }; then f=$HOME/.cshrc; fi
            # csh expands history (!) even in single quotes, unless a backslash comes first
            cq=$(printf '%s' "$q" | sed 's/!/\\!/g')
            put_editor "$f" "$(printf "${csh_pre}if %s then\\n    setenv VISUAL %s\\n    setenv EDITOR %s\\nendif$csh_post" \
                "$csh_test" "$cq" "$cq")" "$sh"
            ;;
        *) say "$sh: set VISUAL and EDITOR to $value to edit commit messages in raftaar" ;;
        esac
    done
    if [ -n "$done_shells" ]; then
        say "programs that ask for an editor, such as git, open raftaar in new terminals ($(echo "$done_shells" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//'))"
    fi
    if [ -n "${GIT_EDITOR:-}" ]; then
        say "GIT_EDITOR ($GIT_EDITOR) still comes first for git"
    fi
    if have git && core=$(git config --global --get core.editor 2>/dev/null) && [ -n "$core" ]; then
        say "git's core.editor ($core) still comes first; git config --global --unset core.editor uses raftaar"
    fi
}

# put_editor FILE TEXT SHELL: the editor block in FILE, in place of one from before (raftaar may have
# moved); SHELL names the shell for the message
put_editor() {
    remove_block "$1" 'raftaar editor'
    add_block "$1" "$2" 'raftaar editor'
    if [ -n "$3" ]; then done_shells="$done_shells $3"; fi
}

configure_files() {
    if [ "$os" = linux ]; then
        prefix=${prefix:-$HOME/.local}
        [ -x "$prefix/bin/raftaar" ] || fail "no raftaar in $prefix; set --prefix or run the installer"
        refresh_desktop "$prefix"
    else
        if [ -z "$appdir" ]; then
            if [ -d /Applications/rhun.app ]; then appdir=/Applications; else appdir=$HOME/Applications; fi
        fi
        [ -d "$appdir/rhun.app" ] || fail "no rhun.app in $appdir; set --app-dir or run the installer"
        if [ -x "$LSREGISTER" ]; then "$LSREGISTER" -f "$appdir/rhun.app" >/dev/null 2>&1 || true; fi
    fi
    choose_default_editor
}

# ---------------- PATH ----------------

# login_shell: the user's login shell from the user database, else $SHELL
login_shell() {
    s=''
    if [ "$os" = mac ]; then
        s=$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{ print $2 }') || true
    elif have getent; then
        s=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7) || true
    fi
    basename "${s:-${SHELL:-sh}}"
}

nu_dir() { # the nushell configuration folder, when there is one
    for d in "${XDG_CONFIG_HOME:-$HOME/.config}/nushell" "$HOME/Library/Application Support/nushell"; do
        if [ -d "$d" ]; then
            echo "$d"
            return 0
        fi
    done
}

# bash_login: the file bash reads as a login shell (macOS Terminal, a console login): the first of
# .bash_profile, .bash_login and .profile there is; on macOS, whose terminals start login shells,
# .bash_profile when there is none
bash_login() {
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    if [ "$os" = mac ]; then echo "$HOME/.bash_profile"; fi
}

# user_shells: the shells to set up, one per line: the login shell, $SHELL, and every shell with a
# configuration in HOME
user_shells() {
    {
        login_shell
        basename "${SHELL:-sh}"
        if [ -f "${ZDOTDIR:-$HOME}/.zshrc" ] || [ -f "$HOME/.zshenv" ] || [ -f "$HOME/.zprofile" ]; then echo zsh; fi
        if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.bash_profile" ]; then echo bash; fi
        if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/fish" ]; then echo fish; fi
        if [ -n "$(nu_dir)" ]; then echo nu; fi
        if [ -f "$HOME/.tcshrc" ] || [ -f "$HOME/.cshrc" ]; then echo tcsh; fi
    } | awk 'NF && !seen[$0]++'
}

# add_path BIN: BIN on PATH in every shell the user has, each in its own startup file, as a block
# between "# raftaar" and "# raftaar end"; a line that is already there is not added again, and the
# lines check PATH first, so nothing is doubled where the system puts BIN on PATH itself
add_path() {
    if [ -z "$modify_path" ]; then
        say "to start raftaar from a terminal, add $1 to PATH"
        return 0
    fi
    done_shells=''
    for sh in $(user_shells); do
        case $sh in
        zsh) add_posix "${ZDOTDIR:-$HOME}/.zshrc" "$1" zsh ;;
        bash)
            add_posix "$HOME/.bashrc" "$1" bash
            login=$(bash_login)
            if [ -n "$login" ]; then add_posix "$login" "$1" ''; fi
            ;;
        sh | dash | ksh | mksh | yash | ash | busybox) add_posix "$HOME/.profile" "$1" "$sh" ;;
        fish)
            f=${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/raftaar.fish
            mkdir -p "$(dirname "$f")"
            # shellcheck disable=SC2016 # $PATH is fish's
            printf '# raftaar\nif not contains -- "%s" $PATH\n    set -gx PATH "%s" $PATH\nend\n# raftaar end\n' "$1" "$1" > "$f"
            done_shells="$done_shells fish"
            ;;
        nu)
            d=$(nu_dir)
            if [ -n "$d" ]; then
                add_block "$d/env.nu" "\$env.PATH = (\$env.PATH | split row (char esep) | prepend '$1' | uniq)"
                done_shells="$done_shells nu"
            fi
            ;;
        tcsh | csh)
            f=$HOME/.tcshrc
            if [ ! -f "$f" ] && { [ -f "$HOME/.cshrc" ] || [ "$sh" = csh ]; }; then f=$HOME/.cshrc; fi
            add_block "$f" "if ( \" \$path \" !~ *\" $1 \"* ) set path = ( \"$1\" \$path )"
            done_shells="$done_shells $sh"
            ;;
        *) say "$sh: add $1 to PATH to start raftaar from it" ;;
        esac
    done
    if [ -n "$done_shells" ]; then
        say "raftaar is on PATH in new terminals ($(echo "$done_shells" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//'))"
    fi
    case ":$PATH:" in
    *":$1:"*) ;;
    *) say "in this terminal, start it as $1/raftaar or open a new one" ;;
    esac
}

# add_posix FILE BIN SHELL: the block for sh, bash, zsh and the like; SHELL names the shell for the
# message
add_posix() {
    # shellcheck disable=SC2016 # $PATH is for the shell that reads the file
    add_block "$1" "$(printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac' "$2" "$2")"
    if [ -n "$3" ]; then done_shells="$done_shells $3"; fi
}

# add_block FILE TEXT [NAME]: TEXT between "# NAME" and "# NAME end" (NAME is raftaar unless given) at
# the end of FILE, unless FILE has them already
add_block() {
    if [ -f "$1" ] && grep -qxF "# ${3:-raftaar}" "$1"; then return 0; fi
    mkdir -p "$(dirname "$1")"
    if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then echo >> "$1"; fi
    if [ -s "$1" ]; then echo >> "$1"; fi
    printf '# %s\n%s\n# %s end\n' "${3:-raftaar}" "$2" "${3:-raftaar}" >> "$1"
}

# remove_block FILE [NAME]: the block add_block wrote, and the empty line before it
remove_block() {
    if [ -f "$1" ] && grep -qxF "# ${2:-raftaar}" "$1"; then
        awk -v start="# ${2:-raftaar}" -v stop="# ${2:-raftaar} end" '
            skip { if ($0 == stop) skip = 0; next }
            $0 == start { skip = 1; held = 0; next }
            held { print ""; held = 0 }
            $0 == "" { held = 1; next }
            { print }
            END { if (held) print "" }' "$1" > "$tmp/rc"
        cat "$tmp/rc" > "$1"
    fi
}

# ---------------- what the options ask ----------------

install_fresh() {
    printf '\n  %sInstalling raftaar %s%s%s (%s)\n\n' "$bold" "$cyan" "$version" "$reset" "$platform_name" >&2
    download
    if [ "$os" = linux ]; then
        prefix=${prefix:-$HOME/.local}
        unpack_linux
        say 'Installing binary and desktop entry'
        place_binary "$prefix/bin/raftaar"
        place_desktop "$prefix" "$prefix/bin/raftaar"
        add_path "$prefix/bin"
        installed "$prefix"
        say "start it from your applications, or run: raftaar [folder]"
    else
        appdir=${appdir:-$(default_app_dir)}
        unpack_mac
        say 'Installing app and terminal command'
        place_app "$appdir/rhun.app"
        place_wrapper "$appdir/rhun.app"
        add_path "$HOME/.local/bin"
        installed "$appdir"
        say "start it from Launchpad or Spotlight, or run: raftaar [folder]"
    fi
    print_default_editor_command
}

update() {
    [ -n "$target" ] || fail "--update needs --target"
    if [ "$(installed_version "$target")" = "$version" ]; then return 0; fi
    dir=$(dirname "$target")
    if [ "$os" = mac ]; then
        case "$target" in *.app) ;; *) fail "$target is not an app" ;; esac
    fi
    [ -w "$dir" ] || fail "$dir is not writable; run the installer again"
    download
    if [ "$os" = linux ]; then
        unpack_linux
        place_binary "$target"
        # the desktop entry and icons too when the installer put them there
        prefix=$(dirname "$dir")
        if [ -f "$prefix/share/applications/raftaar.desktop" ] && [ -w "$prefix/share/applications" ]; then
            place_desktop "$prefix" "$target"
        fi
    else
        unpack_mac
        place_app "$target"
    fi
}

uninstall() {
    if [ "$os" = linux ]; then
        prefix=${prefix:-$HOME/.local}
        rm -f "$prefix/bin/raftaar" "$prefix/share/applications/raftaar.desktop"
        for d in scalable/apps/raftaar.svg 256x256/apps/raftaar.png 512x512/apps/raftaar.png; do
            rm -f "$prefix/share/icons/hicolor/$d"
        done
        refresh_desktop "$prefix"
        say "raftaar is removed from $prefix"
    else
        if [ -n "$appdir" ]; then
            rm -rf "$appdir/rhun.app"
        else
            rm -rf /Applications/rhun.app "$HOME/Applications/rhun.app" 2>/dev/null || true
        fi
        if [ -f "$HOME/.local/bin/raftaar" ] && grep -q 'rhun.app/Contents/MacOS/raftaar' "$HOME/.local/bin/raftaar"; then
            rm -f "$HOME/.local/bin/raftaar"
        fi
        say "raftaar is removed"
    fi
    for f in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" \
        "$HOME/.profile" "$HOME/.tcshrc" "$HOME/.cshrc"; do
        remove_block "$f"
        remove_block "$f" 'raftaar editor'
    done
    d=$(nu_dir)
    if [ -n "$d" ]; then
        remove_block "$d/env.nu"
        remove_block "$d/env.nu" 'raftaar editor'
    fi
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/raftaar.fish" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/raftaar-editor.fish"
    say "your settings are still in ${XDG_CONFIG_HOME:-$HOME/.config}/raftaar"
}

main() {
    version='' prefix='' appdir='' modify_path=1 mode=install target='' quiet='' make_default=no
    output_style
    while [ $# -gt 0 ]; do
        case $1 in
        --version) version=${2:-}; shift ;;
        --prefix) prefix=${2:-}; shift ;;
        --app-dir) appdir=${2:-}; shift ;;
        --no-modify-path) modify_path= ;;
        --make-default) make_default=yes ;;
        --no-make-default) make_default=no ;;
        --configure-files) mode=configure ;;
        --uninstall) mode=uninstall ;;
        --update) mode=update; quiet=1 ;;
        --target) target=${2:-}; shift ;;
        -h | --help) usage; exit 0 ;;
        *) fail "unknown option $1 (see --help)" ;;
        esac
        shift
    done
    if [ "$make_default" = yes ] && [ "$mode" != configure ]; then
        fail '--make-default requires --configure-files; install raftaar first, then run the printed command'
    fi
    # PATH, the desktop entry, the macOS command and EDITOR name these folders from anywhere
    case $prefix in '' | /*) ;; *) prefix=$(pwd)/$prefix ;; esac
    case $appdir in '' | /*) ;; *) appdir=$(pwd)/$appdir ;; esac
    [ -n "${HOME:-}" ] || fail "HOME is not set"
    platform
    base=${RAFTAAR_RELEASES_URL:-$RELEASES}
    tmp=$(mktemp -d 2>/dev/null || mktemp -d -t raftaar)
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 1' HUP INT TERM
    if [ "$mode" = uninstall ]; then
        uninstall
        return 0
    fi
    if [ "$mode" = configure ]; then
        configure_files
        return 0
    fi
    if [ -z "$quiet" ]; then
        banner
    fi
    downloader
    if [ -z "$version" ]; then version=$(latest_version); fi
    valid_version "$version" || fail "$version is not a version"
    if [ "$mode" = update ]; then
        update
    else
        install_fresh
    fi
}

main "$@"
