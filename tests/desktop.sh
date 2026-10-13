#!/bin/sh
# raftaar --install-desktop on Linux: the desktop entry and icons the program carries, as it writes
# them; prints ok/FAIL for each case.
set -u
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Linux ] || exit 0
w=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$w"' EXIT HUP INT TERM
fail=0
case_failed=
t() { # WHAT CMD...: CMD must succeed
    what=$1
    shift
    if ! "$@"; then
        echo "FAIL desktop/$c: $what"
        case_failed=1
        fail=1
    fi
}
begin() {
    c=$1
    case_failed=
}
end() {
    if [ -z "$case_failed" ]; then echo "ok   desktop/$c"; fi
}
entry=share/applications/raftaar.desktop
icons=share/icons/hicolor
mkdir -p "$w/bin"
cp build/raftaar "$w/bin/raftaar"

begin prefix
"$w/bin/raftaar" --install-desktop "$w/pre" > "$w/out" 2>&1
t "exit $?" [ $? = 0 ]
t "quiet" [ ! -s "$w/out" ]
sed "s|^Exec=raftaar |Exec=$w/bin/raftaar |" assets/raftaar.desktop > "$w/want"
t "the entry, with Exec the program's path" cmp -s "$w/want" "$w/pre/$entry"
t "svg" cmp -s assets/icons/raftaar.svg "$w/pre/$icons/scalable/apps/raftaar.svg"
t "256" cmp -s assets/icons/raftaar-256.png "$w/pre/$icons/256x256/apps/raftaar.png"
t "512" cmp -s assets/icons/raftaar-512.png "$w/pre/$icons/512x512/apps/raftaar.png"
# again, over what is there
"$w/bin/raftaar" --install-desktop "$w/pre" > "$w/out" 2>&1
t "again: exit $?" [ $? = 0 ]
t "again: the entry" cmp -s "$w/want" "$w/pre/$entry"
end

begin home
HOME="$w/home" "$w/bin/raftaar" --install-desktop > "$w/out" 2>&1
t "exit $?" [ $? = 0 ]
t "under ~/.local" cmp -s "$w/want" "$w/home/.local/$entry"
end

# a path a desktop would split or expand is quoted
begin quoted
d="$w/a b\$c\`d\"e\\f%g"
mkdir "$d"
cp build/raftaar "$d/raftaar"
"$d/raftaar" --install-desktop "$w/q" > "$w/out" 2>&1
t "exit $?" [ $? = 0 ]
printf 'Exec="%s/a b\\\\$c\\\\`d\\\\"e\\\\\\\\f%%%%g/raftaar" %%F\n' "$w" > "$w/want-exec"
grep '^Exec=' "$w/q/$entry" > "$w/got-exec"
t "Exec" cmp -s "$w/want-exec" "$w/got-exec"
end

begin unwritable
: > "$w/file"
"$w/bin/raftaar" --install-desktop "$w/file/x" > "$w/out" 2>&1
t "exit $?" [ $? = 1 ]
t "says why" grep -qF "could not write $w/file/x/$entry" "$w/out"
end

exit $fail
