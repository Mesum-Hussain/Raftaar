#!/bin/sh
# File saves and reloads must preserve both the target and unrelated directory entries.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
bin=$PWD/build/file_test
printf 'saved\n' > "$work/expected"
printf 'original\n' > "$work/original"
fail=0
check() {
    if "$@"; then return; fi
    echo "FAIL files/$case"
    fail=1
}

case=regular
cp "$work/original" "$work/file"
chmod 751 "$work/file"
check "$bin" write "$work/file"
check cmp -s "$work/file" "$work/expected"
check test -x "$work/file"
mode() {
    if [ "$(uname -s)" = Darwin ]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi
}
check test "$(mode "$work/file")" = 751

case=new-file-umask
check sh -c 'umask 077; "$1" write "$2"' sh "$bin" "$work/private"
check test "$(mode "$work/private")" = 600

case=exclusive-temp-retry
check sh -c '
    printf "original\n" > "$2/.raftaar-$$-1.tmp"
    exec "$1" write "$2/retry"
' sh "$bin" "$work"
check cmp -s "$work/retry" "$work/expected"
for f in "$work"/.raftaar-*.tmp; do
    check cmp -s "$f" "$work/original"
    rm -f "$f"
done

case=temp-collision
cp "$work/original" "$work/file.raftaar-tmp"
check "$bin" write "$work/file"
check cmp -s "$work/file.raftaar-tmp" "$work/original"

case=temp-symlink
rm -f "$work/file.raftaar-tmp"
cp "$work/original" "$work/other"
ln -s other "$work/file.raftaar-tmp"
check "$bin" write "$work/file"
check test -L "$work/file.raftaar-tmp"
check cmp -s "$work/other" "$work/original"

case=relative-symlink
mkdir "$work/links" "$work/targets"
cp "$work/original" "$work/targets/file"
ln -s ../targets/file "$work/links/file"
ln -s links/file "$work/link"
check "$bin" write "$work/link"
check test -L "$work/link"
check test -L "$work/links/file"
check cmp -s "$work/targets/file" "$work/expected"

case=absolute-symlink
ln -s "$work/targets/file" "$work/absolute"
check "$bin" write "$work/absolute"
check test -L "$work/absolute"
check cmp -s "$work/targets/file" "$work/expected"

case=dangling-symlink
ln -s targets/new "$work/dangling"
check "$bin" write "$work/dangling"
check test -L "$work/dangling"
check cmp -s "$work/targets/new" "$work/expected"

case=symlink-loop
ln -s loop "$work/loop"
if "$bin" write "$work/loop"; then check false; fi
check test -L "$work/loop"

case=failed-rename
mkdir "$work/directory"
if "$bin" write "$work/directory"; then check false; fi
check test -d "$work/directory"

case=special-file
mkfifo "$work/pipe"
ln -s pipe "$work/pipe-link"
if "$bin" write "$work/pipe"; then check false; fi
if "$bin" write "$work/pipe-link"; then check false; fi
check test -p "$work/pipe"
check test -L "$work/pipe-link"

case=long-basename
name=$(awk 'BEGIN { for (i=0; i<250; i++) printf "x" }')
check "$bin" write "$work/$name"
check cmp -s "$work/$name" "$work/expected"

case=reload-crlf
printf 'before\r\n' > "$work/reload"
printf 'a\rb\r\nc\r\n' > "$work/replacement"
printf 'a\rb\nc\n' > "$work/text"
check sh -c '"$1" reload "$2" "$3" > "$4"' sh "$bin" "$work/reload" "$work/replacement" "$work/out"
check cmp -s "$work/reload" "$work/replacement"
check cmp -s "$work/out" "$work/text"

case=reload-lf-to-crlf
printf 'before\n' > "$work/reload"
check sh -c '"$1" reload "$2" "$3" > "$4"' sh "$bin" "$work/reload" "$work/replacement" "$work/out"
check cmp -s "$work/reload" "$work/replacement"
check cmp -s "$work/out" "$work/text"

case=reload-crlf-to-lf
printf 'before\r\n' > "$work/reload"
printf 'a\rb\nc\n' > "$work/replacement"
check sh -c '"$1" reload "$2" "$3" > "$4"' sh "$bin" "$work/reload" "$work/replacement" "$work/out"
check cmp -s "$work/reload" "$work/replacement"
check cmp -s "$work/out" "$work/replacement"

case=reload-binary
printf 'before\r\n' > "$work/reload"
printf 'binary\000data\r\n' > "$work/replacement"
printf 'before\n' > "$work/text"
check sh -c '"$1" reload-binary "$2" "$3" > "$4"' sh "$bin" "$work/reload" "$work/replacement" "$work/out"
check cmp -s "$work/reload" "$work/replacement"
check cmp -s "$work/out" "$work/text"

case=load-directory
if "$bin" load "$work/directory"; then check false; fi
check "$bin" app-error "$work/directory"
check test "$("$bin" error "$work/directory" 2>&1)" = 21
case=load-missing
check test "$("$bin" error "$work/missing" 2>&1)" = 2
if [ "$(id -u)" != 0 ]; then
    case=load-unreadable
    cp "$work/original" "$work/unreadable"
    chmod 000 "$work/unreadable"
    check "$bin" app-error "$work/unreadable"
    check test "$("$bin" error "$work/unreadable" 2>&1)" = 13
    chmod 600 "$work/unreadable"
fi

case=temp-cleanup
for f in "$work"/.raftaar-*.tmp "$work/targets"/.raftaar-*.tmp; do
    if [ -e "$f" ] || [ -L "$f" ]; then check false; fi
done

[ "$fail" = 0 ] && echo 'ok   files'
exit "$fail"
