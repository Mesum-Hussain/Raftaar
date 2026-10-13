#!/bin/sh
# The updater against a fake release folder (file://) with a stub install.sh and a stub target to
# restart into; prints ok/FAIL for each case.
set -u
cd "$(dirname "$0")/.."
w=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$w"' EXIT HUP INT TERM
cur=$(cat VERSION)
fail=0
mkdir -p "$w/proj" "$w/rel/latest/download" "$w/rel/download/v99.0.0"
# the release's installer: records its arguments; fails when the case asks
cat > "$w/rel/download/v99.0.0/install.sh" <<'EOF'
printf '%s\n' "$@" > "$STUB_LOG"
# a newer release appears while this one installs
if [ -n "${STUB_BUMP:-}" ]; then printf '99.0.1\n' > "$STUB_BUMP"; fi
if [ -n "${STUB_FAIL:-}" ]; then echo "downloading"; echo "raftaar install: stub failure"; exit 3; fi
EOF
# the installation: restarting runs it
cat > "$w/target" <<EOF
#!/bin/sh
printf 'restarted %s\n' "\$*" > "$w/restart.log"
EOF
chmod +x "$w/target"

# run CASE REPLY SEED TARGET FAIL LINES...: raftaar headless with the script LINES, the release's VERSION
# REPLY (none when empty), the state file SEED; output in $w/CASE.out
run() {
    c=$1 reply=$2 seed=$3 target=$4 stubfail=$5
    shift 5
    rm -rf "$w/home" "$w/state" "$w/config" "$w/stub.log" "$w/restart.log"
    mkdir -p "$w/home" "$w/state/raftaar" "$w/config/raftaar"
    # the check at startup is off by default
    printf '[updates]\ncheck = true\n' > "$w/config/raftaar/config"
    if [ -n "$reply" ]; then printf '%s\n' "$reply" > "$w/rel/latest/download/VERSION"; else rm -f "$w/rel/latest/download/VERSION"; fi
    [ -n "$seed" ] && printf '%s\n' "$seed" > "$w/state/raftaar/update"
    printf '%s\n' "$@" > "$w/$c.rsc"
    env HOME="$w/home" XDG_CONFIG_HOME="$w/config" XDG_STATE_HOME="$w/state" \
        RAFTAAR_RELEASES_URL="file://$w/rel" RAFTAAR_UPDATE_TARGET="$target" STUB_LOG="$w/stub.log" STUB_FAIL="$stubfail" STUB_BUMP="${bump:-}" \
        build/raftaar "${launch:-$w/proj}" --headless 800x600 --script "$w/$c.rsc" > "$w/$c.out" 2>&1
}
expect() { # CASE LINE
    if grep -qxF "$2" "$w/$1.out"; then echo "ok   update/$1"; else echo "FAIL update/$1"; cat "$w/$1.out"; fail=1; fi
}
check='cmd check_for_updates'
now=$(date +%s)

run newer 99.0.0 '' "$w/target" '' "$check" wait-update print-update
expect newer "state=available current=$cur latest=99.0.0 error="
run same "$cur" '' "$w/target" '' "$check" wait-update print-update
expect same "state=idle current=$cur latest=$cur error="
run garbage '<html>' '' "$w/target" '' "$check" wait-update print-update
expect garbage "state=idle current=$cur latest= error=unexpected reply"
run missing '' '' "$w/target" '' "$check" wait-update print-update
expect missing "state=idle current=$cur latest= error=download failed"
# every start asks again, however recent the saved answer: a release may have come out since
run fresh 99.0.0 "checked=$now
latest=$cur" "$w/target" '' 'wait 5500' wait-update print-update
expect fresh "state=available current=$cur latest=99.0.0 error="
run stale 99.0.0 "checked=1
latest=98.0.0" "$w/target" '' 'wait 5500' wait-update print-update
expect stale "state=available current=$cur latest=99.0.0 error="
if grep -qx 'latest=99.0.0' "$w/state/raftaar/update"; then echo "ok   update/saved"; else echo "FAIL update/saved"; fail=1; fi
# a build from source reports what it finds, never checks by itself, never installs
run source 99.0.0 '' '' '' "$check" wait-update 'cmd install_update' wait-update print-update
expect source "state=idle current=$cur latest=99.0.0 error="
run source-auto 99.0.0 '' '' '' 'wait 5500' wait-update print-update
expect source-auto "state=idle current=$cur latest= error="

run install 99.0.0 '' "$w/target" '' "$check" wait-update 'cmd install_update' wait-update print-update
expect install "state=ready current=$cur latest=99.0.0 error="
if [ "$(tr '\n' ' ' < "$w/stub.log")" = "--update --target $w/target --version 99.0.0 " ]; then
    echo "ok   update/install-args"
else
    echo "FAIL update/install-args"; cat "$w/stub.log"; fail=1
fi
expect install "desc=99.0.0 is installed; restart to use it"
# a later check finds a newer release; what was installed, and what a restart runs, is still 99.0.0
bump=$w/rel/latest/download/VERSION
run install-newer 99.0.0 '' "$w/target" '' "$check" wait-update 'cmd install_update' wait-update \
    "$check" wait-update print-update
bump=
expect install-newer "state=ready current=$cur latest=99.0.1 error="
expect install-newer "desc=99.0.0 is installed; restart to use it"
run install-fail 99.0.0 '' "$w/target" 1 "$check" wait-update 'cmd install_update' wait-update print-update
expect install-fail "state=available current=$cur latest=99.0.0 error=raftaar install: stub failure"
run restart 99.0.0 '' "$w/target" '' "$check" wait-update 'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $w/proj" ]; then
    echo "ok   update/restart"
else
    echo "FAIL update/restart"; cat "$w/restart.out"; fail=1
fi
printf 'first\n' > "$w/first café.rb"
printf 'second\n' > "$w/second file.rb"
launch=$w/first\ café.rb
run restart-files 99.0.0 '' "$w/target" '' "open $w/second file.rb" "$check" wait-update \
    'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $w/first café.rb $w/second file.rb" ]; then
    echo "ok   update/restart-standalone-tabs"
else
    echo "FAIL update/restart-standalone-tabs"; cat "$w/restart-files.out"; fail=1
fi
run restart-edited-files 99.0.0 '' "$w/target" '' "open $w/second file.rb" 'cmd prev_tab' 'type edited' \
    "$check" wait-update 'cmd install_update' wait-update 'cmd restart_to_update' 'key Escape' \
    'cmd restart_to_update' 'key Return'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $w/first café.rb $w/second file.rb" ] && \
   [ "$(cat "$w/first café.rb")" = editedfirst ]; then
    echo "ok   update/restart-edited-standalone-tabs-after-cancel"
else
    echo "FAIL update/restart-edited-standalone-tabs-after-cancel"; cat "$w/restart-edited-files.out"; fail=1
fi
run restart-empty 99.0.0 '' "$w/target" '' 'cmd close_tab' "$check" wait-update \
    'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = 'restarted --empty' ]; then
    echo "ok   update/restart-empty-standalone-window"
else
    echo "FAIL update/restart-empty-standalone-window"; cat "$w/restart-empty.out"; fail=1
fi
image=$(pwd -P)/assets/icons/raftaar-256.png
launch=$image
run restart-image 99.0.0 '' "$w/target" '' "$check" wait-update 'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $image" ]; then
    echo "ok   update/restart-image-tab"
else
    echo "FAIL update/restart-image-tab"; cat "$w/restart-image.out"; fail=1
fi
launch=$w/first\ café.rb
run restart-mixed 99.0.0 '' "$w/target" '' "open $image" "$check" wait-update \
    'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $w/first café.rb $image" ]; then
    echo "ok   update/restart-text-and-image-tabs"
else
    echo "FAIL update/restart-text-and-image-tabs"; cat "$w/restart-mixed.out"; fail=1
fi
exit $fail
