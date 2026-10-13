#!/usr/bin/env python3
"""Raftaar startup stats on macOS. Requires Python 3 and Raftaar only.

Usage: python3 startup-stats-mac.py [--runs 10] [--warmups 0] [--binary PATH]
Measures launch to an onscreen layer-zero window belonging to the launched PID,
using built-in CoreGraphics/CoreFoundation through ctypes. No pip packages.
Uses your normal configuration and current directory. Polls every 1 ms; native
API queries and OS scheduling add detection overhead. This measures window
appearance, not input readiness or cold-boot startup. Closes only the launched process.
API reference: https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)
"""

import argparse
import ctypes
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ENDPOINT = "process launch to onscreen macOS window (1 ms polling)"


def check_platform(parser):
    if sys.platform != "darwin":
        parser.error("Run this script on macOS in a desktop session.")


def find_binary(requested):
    if requested:
        path = Path(requested).expanduser()
        if path.is_dir() and path.suffix == ".app":
            path /= "Contents/MacOS/raftaar"
            return str(path) if path.is_file() else None
        return shutil.which(str(path))
    binary = shutil.which("raftaar")
    if binary:
        return binary
    for path in [Path("/Applications/rhun.app/Contents/MacOS/raftaar"),
                 Path.home() / "Applications/rhun.app/Contents/MacOS/raftaar"]:
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return None


def launch_environment():
    return None


class WindowProbe:
    def __init__(self):
        self.cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        self.cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        pointer = ctypes.c_void_p
        self.cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
        self.cg.CGWindowListCopyWindowInfo.restype = pointer
        self.cf.CFArrayGetCount.argtypes = [pointer]
        self.cf.CFArrayGetCount.restype = ctypes.c_long
        self.cf.CFArrayGetValueAtIndex.argtypes = [pointer, ctypes.c_long]
        self.cf.CFArrayGetValueAtIndex.restype = pointer
        self.cf.CFDictionaryGetValue.argtypes = [pointer, pointer]
        self.cf.CFDictionaryGetValue.restype = pointer
        self.cf.CFNumberGetValue.argtypes = [pointer, ctypes.c_int, pointer]
        self.cf.CFNumberGetValue.restype = ctypes.c_bool
        self.cf.CFRelease.argtypes = [pointer]
        self.cf.CFRelease.restype = None
        self.pid_key = pointer.in_dll(self.cg, "kCGWindowOwnerPID").value
        self.layer_key = pointer.in_dll(self.cg, "kCGWindowLayer").value
        self.alpha_key = pointer.in_dll(self.cg, "kCGWindowAlpha").value
        # Warm up the native API outside the launch timer.
        self.visible(-1)

    def number(self, window, key, kind, number_type):
        value = self.cf.CFDictionaryGetValue(window, key)
        number = number_type()
        if value and self.cf.CFNumberGetValue(value, kind, ctypes.byref(number)):
            return number.value
        return None

    def visible(self, pid):
        # OnscreenOnly (1) | ExcludeDesktopElements (16). No image capture or window titles.
        windows = self.cg.CGWindowListCopyWindowInfo(17, 0)
        if not windows:
            raise RuntimeError("Cannot list macOS windows. Run inside a desktop session.")
        try:
            for index in range(self.cf.CFArrayGetCount(windows)):
                window = self.cf.CFArrayGetValueAtIndex(windows, index)
                owner = self.number(window, self.pid_key, 3, ctypes.c_int32)
                if owner != pid:
                    continue
                layer = self.number(window, self.layer_key, 3, ctypes.c_int32)
                alpha = self.number(window, self.alpha_key, 6, ctypes.c_double)
                if layer == 0 and alpha is not None and alpha > 0:
                    return True
            return False
        finally:
            self.cf.CFRelease(windows)

    def prepare(self):
        pass

    def observe(self, pid, wait):
        if self.visible(pid):
            return time.perf_counter_ns()
        time.sleep(min(wait, 0.001))
        return None

    def close(self):
        pass


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def measure(binary, probe, timeout):
    probe.prepare()
    with tempfile.TemporaryFile() as log:
        proc = None
        start = time.perf_counter_ns()
        try:
            proc = subprocess.Popen([binary, "--wait"], stdin=subprocess.DEVNULL,
                                    stdout=log, stderr=log, env=launch_environment())
            deadline = start / 1e9 + timeout
            while True:
                remaining = deadline - time.perf_counter()
                if remaining <= 0:
                    raise RuntimeError(f"Raftaar window did not appear within {timeout:g}s")
                observed = probe.observe(proc.pid, min(remaining, 0.1))
                if observed is not None:
                    return (observed - start) / 1e6
                if proc.poll() is not None:
                    log.seek(0)
                    detail = log.read().decode(errors="replace").strip()
                    raise RuntimeError(f"Raftaar exited before opening a window: {detail}")
        finally:
            if proc is not None:
                stop_process(proc)


def print_stats(editor, samples, endpoint):
    """Print a readable report; all durations are milliseconds."""
    rows = [
        ("Runs", str(len(samples))),
        ("Median", f"{statistics.median(samples):,.2f} ms"),
        ("Average", f"{statistics.mean(samples):,.2f} ms"),
        ("Fastest", f"{min(samples):,.2f} ms"),
        ("Slowest", f"{max(samples):,.2f} ms"),
        ("Std deviation", f"{statistics.stdev(samples) if len(samples) > 1 else 0:,.2f} ms"),
        ("First launch", f"{samples[0]:,.2f} ms"),
    ]
    if len(samples) > 1:
        rows.append(("Median, runs 2+", f"{statistics.median(samples[1:]):,.2f} ms"))
    width = 48
    print("\n" + "=" * width)
    print(f"{editor} startup")
    print("-" * width)
    for label, value in rows:
        print(f"  {label:<20} {value:>20}")
    print("-" * width)
    print(f"Measured: {endpoint}")
    print("Warm-cache launches; first launch is not a cold-boot test.")
    print("=" * width, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--warmups", type=int, default=0)
    parser.add_argument("--binary", help="Raftaar executable path or command name")
    parser.add_argument("--timeout", type=float, default=10, help="Seconds per launch")
    args = parser.parse_args()
    if args.runs < 1 or args.warmups < 0 or not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("runs must be positive, warmups nonnegative, and timeout finite and positive")
    check_platform(parser)
    binary = find_binary(args.binary)
    if not binary:
        parser.error("Raftaar executable not found. Use --binary PATH.")
    version = subprocess.check_output([binary, "--version"], text=True, timeout=5).strip()
    probe = WindowProbe()
    try:
        print(version)
        print(f"Executable: {binary}")
        print(f"Directory: {Path.cwd()}")
        print(f"{args.runs} runs, {args.warmups} warmups; {ENDPOINT}", flush=True)
        samples = []
        for index in range(args.warmups + args.runs):
            value = measure(binary, probe, args.timeout)
            if index < args.warmups:
                print(f"Warmup {index + 1}/{args.warmups}: {value:.2f} ms", flush=True)
            else:
                samples.append(value)
                print(f"Run {len(samples)}/{args.runs}: {value:.2f} ms", flush=True)
            time.sleep(0.25)
        print_stats(version, samples, ENDPOINT)
    finally:
        probe.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nStopped.")
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as exc:
        sys.exit(f"Error: {exc}")
