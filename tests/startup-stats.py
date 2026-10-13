#!/usr/bin/env python3
"""Standalone startup probes: PID filtering, timing, cleanup, and report consistency."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
POPEN = subprocess.Popen


def load(platform):
    spec = importlib.util.spec_from_file_location(
        "startup_" + platform, ROOT / f"tools/startup-stats-{platform}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULES = {name: load(name) for name in ("mac", "win", "x11")}


class StartupStats(unittest.TestCase):
    def test_reports_match_hyprland_including_one_sample(self):
        hyprland = load("hyprland")
        for values in ([8.17, 13.55, 16.19], [13.55]):
            expected = io.StringIO()
            with contextlib.redirect_stdout(expected):
                hyprland.print_stats("raftaar test", values, "test endpoint")
            for name, module in MODULES.items():
                with self.subTest(platform=name, samples=values):
                    actual = io.StringIO()
                    with contextlib.redirect_stdout(actual):
                        module.print_stats("raftaar test", values, "test endpoint")
                    self.assertEqual(actual.getvalue(), expected.getvalue())

    def test_summary_discards_warmups(self):
        for name, module in MODULES.items():
            with self.subTest(platform=name):
                output = io.StringIO()
                with mock.patch.object(sys, "argv", ["stats", "--warmups", "1", "--runs", "3"]), \
                        mock.patch.object(module, "check_platform"), \
                        mock.patch.object(module, "find_binary", return_value="fake-raftaar"), \
                        mock.patch.object(module.subprocess, "check_output", return_value="raftaar test\n"), \
                        mock.patch.object(module, "WindowProbe"), \
                        mock.patch.object(module, "measure", side_effect=[100, 40, 10, 30]), \
                        mock.patch.object(module.time, "sleep"), contextlib.redirect_stdout(output):
                    module.main()
                text = output.getvalue()
                self.assertRegex(text, r"Median\s+30.00 ms")
                self.assertRegex(text, r"Average\s+26.67 ms")
                self.assertRegex(text, r"Fastest\s+10.00 ms")
                self.assertRegex(text, r"Slowest\s+40.00 ms")
                self.assertEqual(text.count("Warmup "), 1)
                self.assertEqual(text.count("Run "), 3)

    def test_timeout_and_failed_launch_stop_only_the_launched_process(self):
        for name, module in MODULES.items():
            for source, message in [("import time; time.sleep(60)", "did not appear"),
                                    ("import sys; sys.exit('test failure')", "test failure")]:
                with self.subTest(platform=name, source=source), tempfile.TemporaryDirectory() as directory:
                    fake = Path(directory) / "fake.py"
                    fake.write_text(source)
                    processes = []

                    def launch(command, **options):
                        process = POPEN([sys.executable, str(fake)], **options)
                        processes.append(process)
                        return process

                    probe = mock.Mock()
                    probe.observe.side_effect = lambda pid, wait: time.sleep(min(wait, 0.001))
                    with mock.patch.object(module.subprocess, "Popen", side_effect=launch):
                        with self.assertRaisesRegex(RuntimeError, message):
                            module.measure("fake-raftaar", probe, 0.5)
                    self.assertTrue(processes)
                    self.assertTrue(all(p.poll() is not None for p in processes))

    def test_mac_filters_pid_layer_and_alpha_and_releases_array(self):
        module = MODULES["mac"]
        probe = object.__new__(module.WindowProbe)
        probe.cg = mock.Mock()
        probe.cf = mock.Mock()
        probe.pid_key, probe.layer_key, probe.alpha_key = "pid", "layer", "alpha"
        probe.cg.CGWindowListCopyWindowInfo.return_value = 123
        windows = [{"pid": 1, "layer": 0, "alpha": 1},
                   {"pid": 42, "layer": 1, "alpha": 1},
                   {"pid": 42, "layer": 0, "alpha": 0},
                   {"pid": 42, "layer": 0, "alpha": 1}]
        probe.cf.CFArrayGetCount.return_value = len(windows)
        probe.cf.CFArrayGetValueAtIndex.side_effect = lambda array, index: windows[index]
        probe.number = lambda window, key, *unused: window[key]
        self.assertTrue(probe.visible(42))
        probe.cf.CFRelease.assert_called_once_with(123)
        self.assertFalse(probe.visible(99))

    def test_win_filters_pid_class_visibility_and_minimized_state(self):
        module = MODULES["win"]
        probe = object.__new__(module.WindowProbe)
        probe.user = mock.Mock()
        probe.callback_type = lambda function: function
        windows = {1: (1, "raftaarWindow", True, False),
                   2: (42, "ConsoleWindowClass", True, False),
                   3: (42, "raftaarWindow", False, False),
                   4: (42, "raftaarWindow", True, True),
                   5: (42, "raftaarWindow", True, False)}

        def owner(window, value):
            value._obj.value = windows[window][0]

        def classname(window, buffer, size):
            buffer.value = windows[window][1]

        def enumerate_windows(callback, unused):
            for window in windows:
                if not callback(window, 0):
                    return False
            return True

        probe.user.GetWindowThreadProcessId.side_effect = owner
        probe.user.GetClassNameW.side_effect = classname
        probe.user.IsWindowVisible.side_effect = lambda window: windows[window][2]
        probe.user.IsIconic.side_effect = lambda window: windows[window][3]
        probe.user.EnumWindows.side_effect = enumerate_windows
        with mock.patch.object(module.ctypes, "set_last_error", create=True), \
                mock.patch.object(module.ctypes, "get_last_error", return_value=0, create=True):
            self.assertTrue(probe.visible(42))
            self.assertFalse(probe.visible(99))

    def test_x11_handles_wm_frames_and_rejects_unmapped_or_unrelated_windows(self):
        module = MODULES["x11"]
        probe = object.__new__(module.WindowProbe)
        probe.display = 1
        probe.x = mock.Mock()
        states = {10: 2, 20: 2}

        def attributes(display, window, value):
            value._obj.map_state = states[window]
            return 1

        probe.x.XGetWindowAttributes.side_effect = attributes
        probe.owner_pid = lambda window: {10: 100, 20: 42}[window]
        probe.children = lambda window: [20] if window == 10 else []
        self.assertTrue(probe.owned_visible_window(10, 42))
        self.assertFalse(probe.owned_visible_window(10, 99))
        states[20] = 1
        self.assertFalse(probe.owned_visible_window(10, 42))

    def test_x11_timestamps_event_before_pid_verification(self):
        module = MODULES["x11"]
        probe = object.__new__(module.WindowProbe)
        probe.x = mock.Mock()
        probe.display = 1
        probe.x.XPending.return_value = 1

        def event(display, value):
            value._obj.type = 19
            value._obj.map.window = 10

        probe.x.XNextEvent.side_effect = event
        probe.owned_visible_window = mock.Mock(return_value=True)
        with mock.patch.object(module.time, "perf_counter_ns", return_value=1234):
            self.assertEqual(probe.observe(42, 0.1), 1234)
        probe.owned_visible_window.assert_called_once_with(10, 42)


if __name__ == "__main__":
    unittest.main()
