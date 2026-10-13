#!/usr/bin/env python3
"""Raftaar startup stats on Windows. Requires Python 3 and Raftaar only.

Usage: py -3 startup-stats-win.py [--runs 10] [--warmups 0] [--binary PATH]
Measures launch to a visible, non-minimized raftaarWindow belonging to the launched
PID, using built-in user32 through ctypes. No pip packages. Uses your normal
configuration and current directory. Polls every 1 ms; native API queries and OS
scheduling add detection overhead. Visibility can precede the first painted frame.
This is not input readiness or cold-boot startup. Closes only the launched process.
API reference: https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-enumwindows
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

from ctypes import wintypes

ENDPOINT = "process launch to visible Win32 editor window (1 ms polling)"


def check_platform(parser):
    if sys.platform != "win32":
        parser.error("Run this script on Windows in a desktop session.")


def find_binary(requested):
    if requested:
        return shutil.which(str(Path(requested).expanduser()))
    binary = shutil.which("raftaar.exe")
    if binary:
        return binary
    location = os.environ.get("LOCALAPPDATA")
    if location:
        path = Path(location) / "Programs/raftaar/raftaar.exe"
        if path.is_file():
            return str(path)
    return None


def launch_environment():
    return None


class WindowProbe:
    def __init__(self):
        self.user = ctypes.WinDLL("user32", use_last_error=True)
        self.callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        self.user.EnumWindows.argtypes = [self.callback_type, wintypes.LPARAM]
        self.user.EnumWindows.restype = wintypes.BOOL
        self.user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        self.user.GetWindowThreadProcessId.restype = wintypes.DWORD
        self.user.IsWindowVisible.argtypes = [wintypes.HWND]
        self.user.IsWindowVisible.restype = wintypes.BOOL
        self.user.IsIconic.argtypes = [wintypes.HWND]
        self.user.IsIconic.restype = wintypes.BOOL
        self.user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
        self.user.GetClassNameW.restype = ctypes.c_int
        self.visible(-1)

    def visible(self, pid):
        found = False

        @self.callback_type
        def inspect(window, unused):
            nonlocal found
            owner = wintypes.DWORD()
            self.user.GetWindowThreadProcessId(window, ctypes.byref(owner))
            if owner.value == pid and self.user.IsWindowVisible(window) and not self.user.IsIconic(window):
                classname = ctypes.create_unicode_buffer(80)
                self.user.GetClassNameW(window, classname, len(classname))
                if classname.value == "raftaarWindow":
                    found = True
                    return False
            return True

        ctypes.set_last_error(0)
        if not self.user.EnumWindows(inspect, 0) and not found:
            error = ctypes.get_last_error()
            if error:
                raise ctypes.WinError(error)
        return found

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
