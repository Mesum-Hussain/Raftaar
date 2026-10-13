#!/bin/sh
# usage: tools/install.sh [prefix]   (default ~/.local; builds a release binary first)
set -e
cd "$(dirname "$0")/.."
prefix=${1:-$HOME/.local}
if [ "$(uname -s)" = Darwin ]; then
    # raftaar.app into /Applications (~/Applications when that is not writable), raftaar into prefix/bin
    ./build.sh release
    apps=/Applications
    [ -w "$apps" ] || apps=$HOME/Applications
    mkdir -p "$apps" "$prefix/bin"
    rm -rf "$apps/raftaar.app"
    cp -R build/raftaar.app "$apps/"
    printf '#!/bin/sh\nexec "%s/raftaar.app/Contents/MacOS/raftaar" "$@"\n' "$apps" > "$prefix/bin/raftaar"
    chmod 755 "$prefix/bin/raftaar"
    echo "installed $apps/raftaar.app and $prefix/bin/raftaar"
    exit 0
fi
./build.sh release
install -Dm755 build/raftaar "$prefix/bin/raftaar"
install -Dm644 assets/raftaar.desktop "$prefix/share/applications/raftaar.desktop"
install -Dm644 assets/icons/raftaar.svg "$prefix/share/icons/hicolor/scalable/apps/raftaar.svg"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$prefix/share/applications" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$prefix/share/icons/hicolor" 2>/dev/null || true
echo "installed to $prefix"
