#!/usr/bin/env python3
"""Raftaar startup stats on Hyprland. Requires Python 3 and hyprctl.

Usage: python3 startup-stats-hyprland.py [--runs 10] [--warmups 0] [--binary /path/to/raftaar]

Measures process launch to Hyprland's openwindow event for that process.
Uses your normal Raftaar configuration and the current working directory.
These are warm-cache window-map timings, not input-readiness or cold-boot timings.
The event is timestamped before querying Hyprland to verify the window's PID.
Only the benchmark's own windows and processes are closed.
IPC reference: https://wiki.hypr.land/IPC/
"""

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import time


def hyprctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True, timeout=5)


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def measure(binary, event_path, timeout):
    proc = None
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events, \
            tempfile.TemporaryFile() as log:
        events.connect(str(event_path))
        # Subscribe before launching so even very fast window-map events are seen.
        start = time.perf_counter_ns()
        try:
            proc = subprocess.Popen(
                [binary, "--wait"], stdin=subprocess.DEVNULL,
                stdout=log, stderr=log,
            )
            deadline = start / 1e9 + timeout
            pending = b""
            while True:
                remaining = deadline - time.perf_counter()
                if remaining <= 0:
                    raise RuntimeError(f"Raftaar window did not appear within {timeout:g}s")
                events.settimeout(min(remaining, 0.1))
                try:
                    chunk = events.recv(65536)
                except socket.timeout:
                    if proc.poll() is not None:
                        log.seek(0)
                        detail = log.read().decode(errors="replace").strip()
                        raise RuntimeError(f"Raftaar exited before opening a window: {detail}")
                    continue
                observed = time.perf_counter_ns()
                if not chunk:
                    raise RuntimeError("Hyprland event socket disconnected")
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    if not line.startswith(b"openwindow>>"):
                        continue
                    candidate = line.split(b">>", 1)[1].split(b",", 1)[0].decode()
                    candidate = "0x" + candidate.removeprefix("0x")
                    clients = json.loads(hyprctl("-j", "clients"))
                    if any(c.get("address") == candidate and c.get("pid") == proc.pid
                           for c in clients):
                        return (observed - start) / 1e6
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
    parser.add_argument("--binary", default="raftaar")
    parser.add_argument("--timeout", type=float, default=10, help="Seconds per launch")
    args = parser.parse_args()
    if args.runs < 1 or args.warmups < 0 or not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("runs must be positive, warmups nonnegative, and timeout finite and positive")
    binary = shutil.which(args.binary)
    if not binary:
        parser.error(f"Executable not found: {args.binary}")
    if not shutil.which("hyprctl"):
        parser.error("hyprctl not found. Run this inside your Hyprland desktop session.")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not runtime or not instance:
        parser.error("Run this inside your Hyprland desktop session.")
    event_path = Path(runtime) / "hypr" / instance / ".socket2.sock"
    version = subprocess.check_output([binary, "--version"], text=True, timeout=5).strip()
    print(version)
    print(f"Launch to window map, {args.runs} runs, {args.warmups} warmups")
    print(f"Executable: {binary}")
    print(f"Directory: {Path.cwd()}")
    samples = []
    for index in range(args.warmups + args.runs):
        value = measure(binary, event_path, args.timeout)
        if index < args.warmups:
            print(f"Warmup {index + 1}/{args.warmups}: {value:.2f} ms", flush=True)
        else:
            samples.append(value)
            print(f"Run {len(samples)}/{args.runs}: {value:.2f} ms", flush=True)
        time.sleep(0.25)
    print_stats(version, samples, "process launch to Hyprland window-open event")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nStopped.")
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as exc:
        sys.exit(f"Error: {exc}")
