#!/bin/sh
# install.sh against fake releases (stand-in programs that print their version), in a scratch HOME;
# prints ok/FAIL for each case. Run it as a normal user: root may write where the test expects a
# refusal. On Linux run it in a container, since it calls the desktop's tools.
# usage: tests/install.sh [http]   (http: the releases over http with python3, for wget)
set -u
cd "$(dirname "$0")/.."
root=$PWD
python3 tests/file-associations.py || exit 1
w=$(cd "$(mktemp -d)" && pwd -P)
server=
trap 'if [ -n "$server" ]; then kill $server 2>/dev/null; fi; chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail=0
os=linux
if [ "$(uname -s)" = Darwin ]; then os=mac; fi
H=$w/home
mkdir -p "$H" "$w/rel/latest/download" "$w/shim"

# release VERSION: a fake release: the archive, SHA256SUMS and the installer
release() {
    v=$1
    d=$w/rel/download/v$v
    s=$w/stage-$v
    mkdir -p "$d" "$s"
    if [ $os = linux ]; then
        r=$s/raftaar-$v
        mkdir -p "$r/bin" "$r/share/applications" "$r/share/icons/hicolor/scalable/apps" \
            "$r/share/icons/hicolor/256x256/apps" "$r/share/icons/hicolor/512x512/apps"
        printf '#!/bin/sh\nif [ "${1:-}" = --version ]; then echo "raftaar %s"; exit 0; fi\nsleep "${1:-0}"\n' "$v" > "$r/bin/raftaar"
        chmod 755 "$r/bin/raftaar"
        cp assets/raftaar.desktop "$r/share/applications/"
        cp assets/icons/raftaar.svg "$r/share/icons/hicolor/scalable/apps/"
        cp assets/icons/raftaar-256.png "$r/share/icons/hicolor/256x256/apps/raftaar.png"
        cp assets/icons/raftaar-512.png "$r/share/icons/hicolor/512x512/apps/raftaar.png"
        tar -czf "$d/raftaar-$v-linux-x86_64.tar.gz" -C "$s" "raftaar-$v"
    else
        mkdir -p "$s/rhun.app/Contents/MacOS"
        sed "s/@VERSION@/$v/" assets/mac/Info.plist > "$s/rhun.app/Contents/Info.plist"
        cat > "$s/raftaar.c" <<EOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--version")) { puts("raftaar $v"); return 0; }
    if (argc > 1) sleep(atoi(argv[1]));
    return 0;
}
EOF
        clang -o "$s/rhun.app/Contents/MacOS/raftaar" "$s/raftaar.c" || exit 1
        codesign -s - -f "$s/rhun.app" 2>/dev/null || exit 1
        ditto -c -k --keepParent "$s/rhun.app" "$d/raftaar-$v-macos-arm64.zip"
    fi
    (cd "$d" && for f in raftaar-*; do
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f"; else shasum -a 256 "$f"; fi
    done > SHA256SUMS)
    cp install.sh "$d/"
}

url=file://$w/rel
if [ "${1:-}" = http ]; then
    port=$((18000 + $$ % 1000))
    python3 -m http.server --bind 127.0.0.1 "$port" --directory "$w/rel" >/dev/null 2>&1 &
    server=$!
    url=http://127.0.0.1:$port
    sleep 1
fi

# inst ARGS...: install.sh in the scratch HOME, with the variables that name config folders pointing
# there too (CI runners set XDG_CONFIG_HOME); status in $st, output in $w/out
inst() {
    st=0
    env -u ZDOTDIR HOME="$H" XDG_CONFIG_HOME="$H/.config" SHELL=/bin/zsh PATH="$w/shim:$PATH" \
        RAFTAAR_RELEASES_URL="$url" RAFTAAR_TEAM_ID="not set" XDG_CURRENT_DESKTOP= \
        sh "$root/install.sh" "$@" > "$w/out" 2>&1 || st=$?
}
case_failed=
t() { # WHAT CMD...: CMD must succeed
    what=$1
    shift
    if ! "$@"; then
        echo "FAIL install/$c: $what"
        sed 's/^/    | /' "$w/out"
        case_failed=1
        fail=1
    fi
}
begin() {
    c=$1
    case_failed=
}
end() {
    if [ -z "$case_failed" ]; then echo "ok   install/$c"; fi
}
said() { grep -qF "$1" "$w/out"; }
inode() { ls -i "$1" | awk '{ print $1 }'; }

bin=$H/.local/bin/raftaar
if [ $os = linux ]; then
    set --
    target=$bin
    exe=$bin
else
    set -- --app-dir "$w/apps"
    target=$w/apps/rhun.app
    exe=$target/Contents/MacOS/raftaar
fi

release 1.0.0
echo 1.0.0 > "$w/rel/latest/download/VERSION"
# the user has bash (with a line of their own), fish and tcsh besides zsh, their $SHELL
printf 'alias ll="ls -l"\n' > "$H/.bashrc"
cp "$H/.bashrc" "$w/bashrc.orig"
mkdir -p "$H/.config/fish"
: > "$H/.tcshrc"

# finds SHELL-BIN RCFILE: that shell, reading the file with PATH as a desktop gives it, finds raftaar
finds() {
    case $1 in
    fish) out=$(env -i HOME="$H" PATH=/usr/bin:/bin fish -c "source '$2'; source '$2'; command -v raftaar; string join \n \$PATH" 2>&1) ;;
    tcsh) out=$(env -i HOME="$H" PATH=/usr/bin:/bin tcsh -f -c "source '$2'; source '$2'; which raftaar; echo \$PATH | tr : '\\n'" 2>&1) ;;
    *) out=$(env -i HOME="$H" PATH=/usr/bin:/bin "$1" -c ". '$2'; . '$2'; command -v raftaar; echo \"\$PATH\" | tr : '\\n'" 2>&1) ;;
    esac
    printf '%s\n' "$out" | grep -qxF "$H/.local/bin/raftaar" &&
        [ "$(printf '%s\n' "$out" | grep -cxF "$H/.local/bin")" = 1 ]
}

begin fresh
st=0
cat install.sh | env -u ZDOTDIR HOME="$H" XDG_CONFIG_HOME="$H/.config" SHELL=/bin/zsh PATH="$PATH" \
    RAFTAAR_RELEASES_URL="$url" RAFTAAR_TEAM_ID="not set" XDG_CURRENT_DESKTOP= sh -s -- "$@" > "$w/out" 2>&1 || st=$?
t "exit $st" [ $st = 0 ]
t "raftaar --version" [ "$("$bin" --version 2>&1)" = "raftaar 1.0.0" ]
t "said where" said "raftaar 1.0.0 is installed"
t "release discovery feedback" said "Checking latest release"
t "resolved version feedback" said "Installing raftaar 1.0.0"
t "archive download feedback" said "Downloading raftaar 1.0.0"
t "checksum feedback" said "Download verified"
t "manual default-editor command" said "To use raftaar as your default editor, for files and for git, run this command manually:"
t "manual configuration flags" grep -qF -- '--configure-files --make-default' "$w/out"
t "no default-editor prompt" sh -c '! grep -qF "[y/N]" "$1"' sh "$w/out"
t "no metadata filename feedback" sh -c '! grep -qF "VERSION" "$1"' sh "$w/out"
if [ $os = linux ]; then
    t "Exec is the binary's path" grep -qxF "Exec=$bin %F" "$H/.local/share/applications/raftaar.desktop"
    t "icons" [ -f "$H/.local/share/icons/hicolor/scalable/apps/raftaar.svg" ]
    t "icons" [ -f "$H/.local/share/icons/hicolor/256x256/apps/raftaar.png" ]
    t "icons" [ -f "$H/.local/share/icons/hicolor/512x512/apps/raftaar.png" ]
else
    t "the app" [ -x "$exe" ]
    t "the wrapper starts the app" grep -qF "$target/Contents/MacOS/raftaar" "$bin"
fi
t "PATH in .zshrc" [ "$(grep -c '^# raftaar$' "$H/.zshrc")" = 1 ]
t "PATH in .bashrc" [ "$(grep -c '^# raftaar$' "$H/.bashrc")" = 1 ]
t "PATH for fish" grep -qF "$H/.local/bin" "$H/.config/fish/conf.d/raftaar.fish"
t "PATH in .tcshrc" [ "$(grep -c '^# raftaar$' "$H/.tcshrc")" = 1 ]
t "the user's line stays" grep -qxF 'alias ll="ls -l"' "$H/.bashrc"
for sh in zsh bash dash fish tcsh; do
    command -v $sh >/dev/null 2>&1 || continue
    case $sh in
    zsh) rc=$H/.zshrc ;;
    bash) rc=$H/.bashrc ;;
    dash) rc=$H/.bashrc ;;
    fish) rc=$H/.config/fish/conf.d/raftaar.fish ;;
    tcsh) rc=$H/.tcshrc ;;
    esac
    t "$sh finds raftaar" finds $sh "$rc"
done
inst "$@"
t "again: exit $st" [ $st = 0 ]
t "again: PATH once" [ "$(grep -c '^# raftaar$' "$H/.zshrc")" = 1 ]
end

python3 tests/install-output.py "$url" || fail=1

release 99.0.0
begin update
cp -R "$target" "$w/old"
"$exe" 5 &
running=$!
inst --update --target "$target" --version 99.0.0
t "exit $st" [ $st = 0 ]
t "quiet" [ ! -s "$w/out" ]
t "raftaar --version" [ "$("$bin" --version 2>&1)" = "raftaar 99.0.0" ]
t "the running copy goes on" kill -0 $running
kill $running 2>/dev/null
wait $running 2>/dev/null
end

begin same
before=$(inode "$exe")
inst --update --target "$target" --version 99.0.0
t "exit $st" [ $st = 0 ]
t "untouched" [ "$(inode "$exe")" = "$before" ]
end

begin unwritable
if [ "$(id -u)" = 0 ]; then
    echo "skip install/$c (root)"
else
    mkdir -p "$w/ro"
    cp -R "$w/old" "$w/ro/$(basename "$target")"
    chmod 555 "$w/ro"
    inst --update --target "$w/ro/$(basename "$target")" --version 99.0.0
    t "exit $st" [ $st = 1 ]
    t "says why" said "is not writable"
    chmod 755 "$w/ro"
    end
fi

begin badsum
release 98.0.0
sed 's/^[0-9a-f]*/0000000000000000000000000000000000000000000000000000000000000000/' \
    "$w/rel/download/v98.0.0/SHA256SUMS" > "$w/sums" && cp "$w/sums" "$w/rel/download/v98.0.0/SHA256SUMS"
inst --version 98.0.0 "$@"
t "exit $st" [ $st = 1 ]
t "says why" said "does not match its checksum"
t "installation untouched" [ "$("$bin" --version 2>&1)" = "raftaar 99.0.0" ]
end

begin missing
inst --version 5.5.5 "$@"
t "exit $st" [ $st = 1 ]
t "says why" said "could not download raftaar-5.5.5"
end

begin badversion
inst --version '1.0;rm' "$@"
t "exit $st" [ $st = 1 ]
t "says why" said "is not a version"
end

begin platform
printf '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo aarch64 ;; esac\n' > "$w/shim/uname"
chmod 755 "$w/shim/uname"
inst "$@"
t "exit $st" [ $st = 1 ]
t "says why" said "raftaar runs on Linux x86-64 and macOS on Apple silicon"
rm "$w/shim/uname"
end

begin help
inst --help
t "exit $st" [ $st = 0 ]
t "usage" said "usage: install.sh"
end

begin uninstall
mkdir -p "$H/.config/raftaar"
echo "[ui]" > "$H/.config/raftaar/config"
inst --uninstall "$@"
t "exit $st" [ $st = 0 ]
t "binary gone" [ ! -e "$bin" ]
t "app gone" [ ! -e "$target" ]
if [ $os = linux ]; then
    t "desktop entry gone" [ ! -e "$H/.local/share/applications/raftaar.desktop" ]
    t "icons gone" [ ! -e "$H/.local/share/icons/hicolor/512x512/apps/raftaar.png" ]
fi
t "PATH lines gone" sh -c "! grep -q '^# raftaar' '$H/.zshrc' '$H/.tcshrc'"
t ".bashrc as it was" cmp -s "$H/.bashrc" "$w/bashrc.orig"
t "fish file gone" [ ! -e "$H/.config/fish/conf.d/raftaar.fish" ]
t "settings kept" [ -f "$H/.config/raftaar/config" ]
end

python3 tests/install-download.py || fail=1
exit $fail
