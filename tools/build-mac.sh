#!/bin/sh
# macOS on Apple silicon: tools/arm64.py translates the x86-64 sources to AArch64, src/mac holds
# the native parts (entry, Linux system calls on libSystem, the AppKit window)
# usage: tools/build-mac.sh [release|test]
set -e
cd "$(dirname "$0")/.."
mkdir -p build/obj build/a64
tools/gen-assets.sh > build/assets.s.new
cmp -s build/assets.s.new build/assets.s || { mv build/assets.s.new build/assets.s; rm -f build/obj/build_assets.o; }
MINOS=12.0
ASFLAGS="-arch arm64 -mmacosx-version-min=$MINOS"

# stale(obj, deps...): obj is missing or older than a dependency
stale() {
    [ -f "$1" ] || return 0
    o=$1; shift
    for d in "$@"; do [ "$d" -nt "$o" ] && return 0; done
    return 1
}
name() { echo "$1" | sed 's|/|_|g; s|\.s$||'; }

# translated sources: everything but the Linux entry and display servers
x86=$(find src -name '*.s' ! -path 'src/mac/*' ! -path 'src/win/*' ! -path src/start.s ! -path src/plat/wayland.s ! -path src/plat/x11.s ! -path src/plat/appearance.s | LC_ALL=C sort)
[ "$1" = test ] && x86="$x86 $(ls tests/*.s)"
todo=
objs=
for s in $x86 build/assets.s; do
    o=build/obj/$(name "$s").o
    if stale "$o" "$s" src/raftaar.inc tools/arm64.py ||
        { [ "$s" = build/assets.s ] && [ -n "$(find runtime assets/fonts -newer "$o" -print -quit)" ]; }; then
        todo="$todo $s"
    fi
    case $s in tests/*) ;; *) objs="$objs $o" ;; esac
done
if [ -n "$todo" ]; then
    printf '%s\n' $todo | xargs -P "$(sysctl -n hw.ncpu)" -n 1 sh -c '
        n=$(echo "$1" | sed "s|/|_|g; s|\.s$||")
        python3 tools/arm64.py -I src -D MACOS "$1" "build/a64/$n.s" &&
        as '"$ASFLAGS"' -o "build/obj/$n.o" "build/a64/$n.s"' sh
fi
for s in src/mac/*.s; do
    o=build/obj/$(name "$s").o
    stale "$o" "$s" src/mac/mac.inc && as $ASFLAGS -I src/mac -o "$o" "$s"
    objs="$objs $o"
done

LIBS="-framework AppKit -framework QuartzCore -framework IOSurface -framework CoreServices -framework Carbon"
link() { # out objs...
    out=$1; shift
    clang -arch arm64 -mmacosx-version-min=$MINOS -o "$out" "$@" $LIBS
}
link build/raftaar $objs
[ "$1" = release ] && strip -x build/raftaar

# build/raftaar.app, signed ad hoc for this machine (tools/package-mac.sh signs for distribution)
app=build/raftaar.app/Contents
mkdir -p $app/MacOS $app/Resources
# a new file, not rewritten in place: a running raftaar keeps its code pages
cp build/raftaar $app/MacOS/raftaar.new && mv -f $app/MacOS/raftaar.new $app/MacOS/raftaar
[ -f assets/icons/raftaar.icns ] && cp assets/icons/raftaar.icns $app/Resources/raftaar.icns
# the bundle versions are numbers only: a prerelease suffix (-rc1) is left out
sed "s/@VERSION@/$(sed "s/-.*//" VERSION)/" assets/mac/Info.plist > $app/Info.plist
codesign -s - -f build/raftaar.app 2>/dev/null
if [ "$1" = test ]; then
    lib=$(echo $objs | tr ' ' '\n' | grep -v 'src_main.o')
    for t in tests/*.s; do
        n=$(basename "$t" .s)
        link "build/$n" build/obj/tests_$n.o $lib
    done
fi
