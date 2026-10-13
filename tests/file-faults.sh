#!/bin/sh
# Failed saves must retain the old file, and EINTR must retry.
# Linux needs working strace injection; macOS uses a small interposition library.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf 'original\n' > "$work/original"
printf 'saved\n' > "$work/saved"
if [ "$(uname -s)" = Darwin ]; then
    cc -Wall -Wextra -Werror -dynamiclib tests/file_faults.c -o "$work/faults.dylib"
    inject() {
        call=$1; error=$2; shift 2
        case $error in ENOSPC) code=28;; EIO) code=5;; EACCES) code=13;; EPERM) code=1;; EINTR) code=4;; esac
        RAFTAAR_TEST_FAULT=$call RAFTAAR_TEST_ERRNO=$code RAFTAAR_TEST_PATH=$3 DYLD_INSERT_LIBRARIES=$work/faults.dylib "$@"
    }
else
    command -v strace >/dev/null
    strace -qq -o "$work/trace" -e trace=read build/file_test load "$work/original" > /dev/null
    if ! grep -q 'read(' "$work/trace"; then
        echo 'SKIP file-faults: strace cannot observe syscalls (for example under Rosetta)'
        exit 77
    fi
    inject() {
        call=$1; error=$2; shift 2
        strace -qq -o "$work/trace" -e "inject=$call:error=$error:when=1" "$@"
    }
fi
for fault in write:ENOSPC fsync:ENOSPC close:EIO rename:EACCES fchmod:EPERM; do
    cp "$work/original" "$work/file"
    status=0
    inject "${fault%:*}" "${fault#*:}" build/file_test write "$work/file" || status=$?
    if [ "$status" != 1 ]; then
        echo "FAIL file-faults/$fault: expected exit 1, got $status"; exit 1
    fi
    cmp "$work/file" "$work/original"
    for f in "$work"/.raftaar-*.tmp; do
        if [ -e "$f" ]; then echo "FAIL file-faults/$fault: temporary file remains"; exit 1; fi
    done
done
for call in write fsync; do
    inject "$call" EINTR build/file_test write "$work/file"
    cmp "$work/file" "$work/saved"
done
for call in read fstat; do
    inject "$call" EIO build/file_test error "$work/file" > "$work/out" 2>&1
    [ "$(cat "$work/out")" = 5 ]
done
if [ "$(uname -s)" = Darwin ]; then
    inject short-write EIO build/file_test write "$work/file"
    cmp "$work/file" "$work/saved"
fi
echo 'ok   file-faults'
