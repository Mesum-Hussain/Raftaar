#!/bin/sh
# Takes the site's screenshots on Linux: builds raftaar in a Debian container, runs the scripts in
# scripts/ headless at 2560x1600 (2x), and writes site/img/NAME.webp (1600 px wide) and
# NAME-800.webp. Needs docker and cwebp; the project shown is a clone of main.
# usage: site/shots/take.sh   (IMAGE=... picks another Debian-based image)
# THEME=elflord-dark site/shots/take.sh takes just that theme's gallery preview.
set -eu
cd "$(dirname "$0")/../.."
root=$PWD
git=$(git rev-parse --path-format=absolute --git-common-dir)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
docker run --rm --platform linux/amd64 --hostname devbox \
    -e THEME="${THEME:-}" \
    -v "$root":/src:ro -v "$git":/git:ro -v "$out":/out "${IMAGE:-debian:trixie-slim}" sh /src/site/shots/linux.sh
mkdir -p site/img
for f in "$out"/*.ppm; do
    n=$(basename "$f" .ppm)
    cwebp -quiet -q 82 -resize 1600 0 "$f" -o "site/img/$n.webp"
    cwebp -quiet -q 80 -resize 800 0 "$f" -o "site/img/$n-800.webp"
done
ls -l site/img
