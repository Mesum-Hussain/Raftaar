#!/bin/sh
# usage: ./build.sh [release|test]: build/raftaar, and a copy of it as ./raftaar
set -e
cd "$(dirname "$0")"
[ "$(uname -s)" = Darwin ] && exec tools/build-mac.sh "$@"
mkdir -p build/obj
ASFLAGS="--64 -I src -I build"
[ "$1" = release ] || ASFLAGS="$ASFLAGS -g"
tools/gen-assets.sh > build/assets.s.new
cmp -s build/assets.s.new build/assets.s || { mv build/assets.s.new build/assets.s; rm -f build/obj/build_assets.o; }
objs=""
for s in $(find src -name "*.s" ! -path "src/mac/*" ! -path "src/win/*" | LC_ALL=C sort) build/assets.s; do
    o=build/obj/$(echo "$s" | sed 's|/|_|g; s|\.s$|.o|')
    stale=
    # assets.s and desktop.s only name the embedded files; their contents count too
    [ "$s" = build/assets.s ] && [ -f "$o" ] && [ -n "$(find runtime assets/fonts -newer "$o" -print -quit)" ] && stale=1
    [ "$s" = src/plat/desktop.s ] && [ -f "$o" ] && [ -n "$(find assets/raftaar.desktop assets/icons -newer "$o" -print -quit)" ] && stale=1
    if [ -n "$stale" ] || [ ! -f "$o" ] || [ "$s" -nt "$o" ] || [ src/raftaar.inc -nt "$o" ]; then
        as $ASFLAGS -o "$o" "$s"
    fi
    objs="$objs $o"
done
LDFLAGS="-static -nostdlib --no-dynamic-linker -z noexecstack"
[ "$1" = release ] && LDFLAGS="$LDFLAGS -s"
ld $LDFLAGS -o build/raftaar $objs
# a copy beside the sources, to run while developing: ./raftaar
# (renamed into place: a copy over a running ./raftaar fails with "Text file busy")
cp build/raftaar raftaar.new && mv -f raftaar.new raftaar
if [ "$1" = test ]; then
    lib=$(echo $objs | tr ' ' '\n' | grep -v 'src_main.o')
    for t in tests/*.s; do
        n=$(basename "$t" .s)
        as $ASFLAGS -o "build/obj/test_$n.o" "$t"
        ld $LDFLAGS -o "build/$n" "build/obj/test_$n.o" $lib
    done
fi
