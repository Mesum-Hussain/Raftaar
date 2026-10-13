#!/bin/sh
# macOS: checks the translation against the Linux build. The same random sessions (tests/fuzz.py)
# run in the x86-64 Linux binary, in Docker, and in a translated one built from the same sources
# for Linux (no .ifdef MACOS); their states, documents and screenshots must be identical.
# usage: tests/compare-linux.sh [SESSIONS]   (default 20; needs Docker that runs linux/amd64)
#   KEEP=1 keeps the work directory with both outputs
set -e
cd "$(dirname "$0")/.."
n=${1:-20}
tools/build-mac.sh >/dev/null
work=$(cd "$(mktemp -d)" && pwd -P)
if [ -n "$KEEP" ]; then echo "work: $work"; else trap 'rm -rf "$work"' EXIT; fi

# translated, as for Linux
mkdir -p "$work/obj"
find src -name '*.s' ! -path 'src/mac/*' ! -path 'src/win/*' ! -path src/start.s | xargs -P "$(sysctl -n hw.ncpu)" -n 1 sh -c '
    n=$(echo "$1" | sed "s|/|_|g; s|\.s$||")
    python3 tools/arm64.py -I src "$1" "'"$work"'/obj/$n.s" && as -arch arm64 -o "'"$work"'/obj/$n.o" "'"$work"'/obj/$n.s"' sh
for s in build/obj/build_assets.o build/obj/src_mac_rt.o build/obj/src_mac_linux.o build/obj/src_mac_watch.o; do
    cp "$s" "$work/obj/"
done
clang -arch arm64 -o "$work/raftaar-arm64" "$work"/obj/*.o -framework CoreServices

# the Linux build
printf 'FROM debian:stable-slim\nRUN apt-get update && apt-get install -y --no-install-recommends binutils && rm -rf /var/lib/apt/lists/*\n' |
    docker build -q --platform linux/amd64 -t raftaar-linux-ref - >/dev/null
mkdir -p "$work/src"
rsync -a --exclude build --exclude .git ./ "$work/src/"
docker run --rm --platform linux/amd64 -v "$work/src:/src" -w /src raftaar-linux-ref ./build.sh >/dev/null
cp "$work/src/build/raftaar" "$work/raftaar-x86_64"
rm -rf "$work/src/build"

# the sessions, each in a fresh copy of the tree at the same path
python3 tests/fuzz.py "$work/scripts" 0 "$n"
cat > "$work/run.sh" <<'EOF'
#!/bin/sh
# run.sh WORK BINARY OUT
work=$1; bin=$2; out=$3
export TZ=UTC
mkdir -p "$out"
for s in "$work"/scripts/*.rsc; do
    n=$(basename "$s" .rsc)
    rm -rf "$work/tree" "$work/home"
    cp -R "$work/src" "$work/tree"
    mkdir -p "$work/home"
    sed "s|OUTDIR|$out|g" "$s" > "$work/home/s.rsc"
    cd "$work/tree"
    # no shell: its output would arrive at different times (the terminal has tests of its own)
    HOME=$work/home XDG_CONFIG_HOME=$work/home/config XDG_STATE_HOME=$work/home/state SHELL=/nonexistent \
        "$bin" "$work/tree" --headless 1400x860 --script "$work/home/s.rsc" > "$out/$n.out" 2>&1 || echo "exit $?" >> "$out/$n.out"
done
EOF
docker run --rm --platform linux/amd64 -v "$work:$work" raftaar-linux-ref sh "$work/run.sh" "$work" "$work/raftaar-x86_64" "$work/out-x86_64"
sh "$work/run.sh" "$work" "$work/raftaar-arm64" "$work/out-arm64"

fail=0
total=0
for f in "$work"/out-x86_64/*; do
    total=$((total + 1))
    if ! cmp -s "$f" "$work/out-arm64/$(basename "$f")"; then
        echo "DIFF $(basename "$f")"
        fail=1
    fi
done
[ $fail = 0 ] && echo "ok   $n sessions, $total outputs identical"
exit $fail
