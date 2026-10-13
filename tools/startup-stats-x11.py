#!/usr/bin/env python3
"""Raftaar startup stats on Linux X11. Python 3 standard library, native libX11/libXRes.

Usage: python3 startup-stats-x11.py [--runs 10] [--warmups 0] [--binary PATH]
Measures launch to an X11 map event, verifies a viewable window and its owner PID
with X-Resource 1.2, and handles reparenting window managers. Forces Raftaar's X11
backend, including on XWayland. Local X server required for PID attribution.
No pip packages or xdotool/xprop commands. Uses your normal configuration and
current directory. This is window mapping, not first-frame or input-readiness
or cold-boot timing. Closes only the launched process.
API reference: https://www.x.org/releases/current/doc/man/man3/XRes.3.xhtml
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
import select

ENDPOINT = "process launch to X11 map event for a viewable window"


def check_platform(parser):
    if not sys.platform.startswith("linux") or not os.environ.get("DISPLAY"):
        parser.error("Run this script on Linux with an X11 DISPLAY (Xorg or XWayland).")


def find_binary(requested):
    return shutil.which(str(Path(requested).expanduser()) if requested else "raftaar")


def launch_environment():
    return dict(os.environ, RAFTAAR_BACKEND="x11")


class XMapEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong),
                ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
                ("event", ctypes.c_ulong), ("window", ctypes.c_ulong),
                ("override_redirect", ctypes.c_int)]


class XEvent(ctypes.Union):
    _fields_ = [("type", ctypes.c_int), ("map", XMapEvent), ("pad", ctypes.c_long * 24)]


class XWindowAttributes(ctypes.Structure):
    _fields_ = [("x", ctypes.c_int), ("y", ctypes.c_int), ("width", ctypes.c_int),
                ("height", ctypes.c_int), ("border_width", ctypes.c_int),
                ("depth", ctypes.c_int), ("visual", ctypes.c_void_p),
                ("root", ctypes.c_ulong), ("window_class", ctypes.c_int),
                ("bit_gravity", ctypes.c_int), ("win_gravity", ctypes.c_int),
                ("backing_store", ctypes.c_int), ("backing_planes", ctypes.c_ulong),
                ("backing_pixel", ctypes.c_ulong), ("save_under", ctypes.c_int),
                ("colormap", ctypes.c_ulong), ("map_installed", ctypes.c_int),
                ("map_state", ctypes.c_int), ("all_event_masks", ctypes.c_long),
                ("your_event_mask", ctypes.c_long), ("do_not_propagate_mask", ctypes.c_long),
                ("override_redirect", ctypes.c_int), ("screen", ctypes.c_void_p)]


class ClientIdSpec(ctypes.Structure):
    _fields_ = [("client", ctypes.c_ulong), ("mask", ctypes.c_uint)]


class ClientIdValue(ctypes.Structure):
    _fields_ = [("spec", ClientIdSpec), ("length", ctypes.c_long), ("value", ctypes.c_void_p)]


class WindowProbe:
    def __init__(self):
        self.display = None
        try:
            self.x = ctypes.CDLL("libX11.so.6")
            self.res = ctypes.CDLL("libXRes.so.1")
        except OSError as exc:
            raise RuntimeError("Native libX11 and libXRes are required (Debian/Ubuntu: libx11-6 libxres1; Arch: libx11 libxres). No pip packages.") from exc
        pointer = ctypes.c_void_p
        window = ctypes.c_ulong
        window_pointer = ctypes.POINTER(window)
        self.bind(self.x, "XOpenDisplay", [ctypes.c_char_p], pointer)
        self.bind(self.x, "XCloseDisplay", [pointer], ctypes.c_int)
        self.bind(self.x, "XDefaultRootWindow", [pointer], window)
        self.bind(self.x, "XConnectionNumber", [pointer], ctypes.c_int)
        self.bind(self.x, "XSelectInput", [pointer, window, ctypes.c_long], ctypes.c_int)
        self.bind(self.x, "XSync", [pointer, ctypes.c_int], ctypes.c_int)
        self.bind(self.x, "XPending", [pointer], ctypes.c_int)
        self.bind(self.x, "XNextEvent", [pointer, ctypes.POINTER(XEvent)], ctypes.c_int)
        self.bind(self.x, "XQueryTree", [pointer, window, window_pointer, window_pointer,
                                        ctypes.POINTER(window_pointer), ctypes.POINTER(ctypes.c_uint)], ctypes.c_int)
        self.bind(self.x, "XGetWindowAttributes", [pointer, window, ctypes.POINTER(XWindowAttributes)], ctypes.c_int)
        self.bind(self.x, "XFree", [pointer], ctypes.c_int)
        self.bind(self.x, "XSetErrorHandler", [pointer], pointer)
        self.bind(self.res, "XResQueryExtension", [pointer, ctypes.POINTER(ctypes.c_int),
                                                 ctypes.POINTER(ctypes.c_int)], ctypes.c_int)
        self.bind(self.res, "XResQueryVersion", [pointer, ctypes.POINTER(ctypes.c_int),
                                               ctypes.POINTER(ctypes.c_int)], ctypes.c_int)
        self.bind(self.res, "XResQueryClientIds", [pointer, ctypes.c_long, ctypes.POINTER(ClientIdSpec),
                                                 ctypes.POINTER(ctypes.c_long),
                                                 ctypes.POINTER(ctypes.POINTER(ClientIdValue))], ctypes.c_int)
        self.bind(self.res, "XResGetClientPid", [ctypes.POINTER(ClientIdValue)], ctypes.c_int)
        self.bind(self.res, "XResClientIdsDestroy", [ctypes.c_long, ctypes.POINTER(ClientIdValue)], None)
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("Cannot open X11 DISPLAY. Check DISPLAY and Xauthority.")
        try:
            event_base, error_base = ctypes.c_int(), ctypes.c_int()
            major, minor = ctypes.c_int(), ctypes.c_int()
            if not self.res.XResQueryExtension(self.display, ctypes.byref(event_base), ctypes.byref(error_base)):
                raise RuntimeError("The X server does not provide the X-Resource extension.")
            if not self.res.XResQueryVersion(self.display, ctypes.byref(major), ctypes.byref(minor)) or (major.value, minor.value) < (1, 2):
                raise RuntimeError("X-Resource 1.2 or newer is required for window-owner PID checks.")
            # Window trees can change between event receipt and verification.
            self.error_callback = ctypes.CFUNCTYPE(ctypes.c_int, pointer, pointer)(lambda display, error: 0)
            self.old_error_handler = self.x.XSetErrorHandler(self.error_callback)
            root = self.x.XDefaultRootWindow(self.display)
            self.x.XSelectInput(self.display, root, 1 << 19)  # SubstructureNotifyMask, not Redirect.
            self.fd = self.x.XConnectionNumber(self.display)
            self.x.XSync(self.display, 0)
        except BaseException:
            self.close()
            raise

    @staticmethod
    def bind(library, name, arguments, result):
        function = getattr(library, name)
        function.argtypes = arguments
        function.restype = result

    def owner_pid(self, window):
        # XRes can resolve a client from any resource it owns, including its window.
        spec = ClientIdSpec(window, 2)  # XRES_CLIENT_ID_PID_MASK
        count = ctypes.c_long()
        values = ctypes.POINTER(ClientIdValue)()
        status = self.res.XResQueryClientIds(self.display, 1, ctypes.byref(spec),
                                             ctypes.byref(count), ctypes.byref(values))
        try:
            if status == 0:  # Success; this function differs from the Boolean query APIs.
                for index in range(count.value):
                    pid = self.res.XResGetClientPid(ctypes.byref(values[index]))
                    if pid > 0:
                        return pid
            return None
        finally:
            if values:
                self.res.XResClientIdsDestroy(count, values)

    def children(self, window):
        root, parent = ctypes.c_ulong(), ctypes.c_ulong()
        values = ctypes.POINTER(ctypes.c_ulong)()
        count = ctypes.c_uint()
        try:
            if self.x.XQueryTree(self.display, window, ctypes.byref(root), ctypes.byref(parent),
                                 ctypes.byref(values), ctypes.byref(count)):
                return [values[index] for index in range(count.value)]
            return []
        finally:
            if values:
                self.x.XFree(values)

    def owned_visible_window(self, window, pid):
        # A WM may reparent the editor, then map its own outer frame. Check descendants.
        todo = [window]
        visited = set()
        while todo:
            candidate = todo.pop()
            if candidate in visited:
                continue
            visited.add(candidate)
            attributes = XWindowAttributes()
            if not self.x.XGetWindowAttributes(self.display, candidate, ctypes.byref(attributes)):
                continue
            if attributes.map_state == 2 and self.owner_pid(candidate) == pid:  # IsViewable
                return True
            todo.extend(self.children(candidate))
        return False

    def prepare(self):
        self.x.XSync(self.display, 0)
        while self.x.XPending(self.display):
            self.x.XNextEvent(self.display, ctypes.byref(XEvent()))

    def observe(self, pid, wait):
        if not self.x.XPending(self.display):
            if not select.select([self.fd], [], [], wait)[0]:
                return None
        while self.x.XPending(self.display):
            event = XEvent()
            self.x.XNextEvent(self.display, ctypes.byref(event))
            observed = time.perf_counter_ns()
            if event.type == 19 and self.owned_visible_window(event.map.window, pid):  # MapNotify
                return observed
        return None

    def close(self):
        if self.display:
            self.x.XCloseDisplay(self.display)
            self.display = None
            if hasattr(self, "old_error_handler"):
                self.x.XSetErrorHandler(self.old_error_handler)


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
