#!/usr/bin/env python3
"""The editor's horizontal scrollbar (issue 49): with word wrap off, lines wider than the text area get a
bar along its bottom. Dragging or clicking it scrolls without moving the caret, a sideways wheel stops at
the widest line, and word wrap or short lines leave no bar. Like the other scrollbars it hides at rest unless
auto_hide_scrollbars is off."""
import os
from pathlib import Path
import socket
import statistics
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()


@unittest.skipIf(os.name == 'nt', 'the control socket is Unix only')
class EditorHScroll(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-hscroll-', dir='/tmp')
        self.work = Path(self.tmp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        lines = [f'line {i:02d} ' + ('short' if i % 5 else 'wide ' * 60 + f'END{i}') for i in range(30)]
        (self.project / 'wide.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        (self.project / 'narrow.txt').write_text('a\nfew\nnarrow lines\n', encoding='utf-8')
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[editor]\ncursor_blink = false\ntab_width = 4\n'
                          '[ui]\nagents_panel = false\nsidebar = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'))
        self.process = self.client = self.reader = None

    def tearDown(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=10)
            self.reader.close()
            self.client.close()
            self.process.stderr.close()
        self.tmp.cleanup()

    def start(self, name='wide.txt'):
        control = self.work / 'control'
        self.process = subprocess.Popen([str(EXE), str(self.project), str(self.project / name),
                                         '--headless', '1280x800', '--scale', '1',
                                         '--control', str(control)], env=self.env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(15)
        deadline = time.monotonic() + 10
        while True:
            try:
                self.client.connect(str(control))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.fail('editor did not start')
                time.sleep(0.01)
        self.reader = self.client.makefile('r', encoding='utf-8')
        self.command('wait 100')

    def command(self, line):
        self.client.sendall((line + '\n').encode('utf-8'))
        output = []
        while True:
            reply = self.reader.readline()
            if reply == 'ok\n':
                return ''.join(output)
            self.assertNotIn(reply, ('', 'error\n'), line)
            output.append(reply)

    def scroll(self):
        """x, max and the track (x, y, w, h), or None without the bar"""
        fields = dict(part.split('=') for part in self.command('print-scroll').split())
        track = tuple(map(int, fields['track'].split(','))) if 'track' in fields else None
        return int(fields['x']), int(fields['max']), track

    def state(self):
        return self.command('print-state').strip()

    def shot(self):
        path = self.work / 'shot.ppm'
        self.command(f'shot {path}')
        magic, size, maximum, pixels = path.read_bytes().split(b'\n', 3)
        return pixels

    def test_wide_lines_get_a_bar_that_scrolls_them(self):
        self.start()
        x, limit, track = self.scroll()
        self.assertEqual(x, 0)
        self.assertGreater(limit, 0)
        tx, ty, tw, th = track
        # scrollbars hide at rest; over the track the thumb shows along the bottom of the text area,
        # at its left end
        row = ty + th - 5
        def pixel(px):
            return pixels[(row * 1280 + px) * 3:(row * 1280 + px) * 3 + 3]
        pixels = self.shot()
        self.assertEqual(pixel(tx + 10), pixel(tx + tw - 10))
        self.command(f'move {tx + tw // 2} {ty + th - 5}')
        self.command('wait 50')
        pixels = self.shot()
        self.assertNotEqual(pixel(tx + 10), pixel(tx + tw - 10))
        before = self.state()
        # a drag of the thumb scrolls, and the caret stays where it was
        self.command(f'move {tx + 20} {ty + th - 5}')
        self.command('wait 50')
        self.command('down')
        self.command(f'move {tx + 220} {ty + th - 5}')
        self.command('wait 50')
        self.command('up')
        x, _, _ = self.scroll()
        self.assertGreater(x, 0)
        self.assertLess(x, limit)
        self.assertEqual(self.state(), before)
        # a click at the end of the track goes to the end
        self.command(f'click {tx + tw - 3} {ty + th // 2}')
        self.assertEqual(self.scroll()[0], limit)
        self.assertEqual(self.state(), before)
        # the thumb went with it
        pixels = self.shot()
        self.assertNotEqual(pixel(tx + tw - 10), pixel(tx + 10))

    def test_a_very_long_line_scrolls_in_proportion(self):
        # one line of 400,000 columns, as a minified file has: the track's pixels times the scroll in
        # pixels is past 32 bits, and a drag still goes where the thumb is taken
        (self.project / 'long.txt').write_text('x' * 400000 + '\n', encoding='utf-8')
        self.start('long.txt')
        _, limit, (tx, ty, tw, th) = self.scroll()
        self.assertGreater(limit * tw, 2**31)
        self.command(f'move {tx + 10} {ty + th - 5}')
        self.command('wait 50')
        self.command('down')
        self.command(f'move {tx + tw * 3 // 4} {ty + th - 5}')
        self.command('wait 50')
        self.command('up')
        x, _, _ = self.scroll()
        self.assertGreater(x, limit * 6 // 10)
        self.assertLess(x, limit * 9 // 10)

    def test_typing_at_the_start_of_a_long_line_does_not_scan_its_tail(self):
        # Compare typing with redrawing the same line and gap position. Both already copy the
        # visible line across the gap; width measurement must not add a full scan per edit.
        (self.project / 'minified.txt').write_text('x' * 20000000 + '\n', encoding='utf-8')
        self.start('minified.txt')
        self.command('type x')
        self.command('wait 600')  # move the gap to the start, then let its width settle

        def frame_time(typing):
            samples = []
            for index in range(12):
                started = time.perf_counter()
                self.command('type x' if typing else f'move {600 + index % 2} 400')
                self.command('wait 0')  # finish the frame for this edit
                samples.append(time.perf_counter() - started)
            return statistics.median(samples)

        redraw = frame_time(False)
        initial = self.scroll()[1]
        typing = frame_time(True)
        self.assertLess(typing, max(0.020, redraw * 2),
                        f'long-line median: redraw {redraw:.4f}s, typing {typing:.4f}s')
        self.command('wait 600')
        self.assertGreater(self.scroll()[1], initial, 'paused measurement missed the added text')

    def test_typing_at_the_end_of_a_long_line_keeps_the_caret_within_the_scroll(self):
        (self.project / 'minified.txt').write_text('x' * 2000000 + '\n', encoding='utf-8')
        self.start('minified.txt')
        initial = self.scroll()[1]
        self.command('key End')
        # The control command redraws after every character. A short burst exercises the
        # deferred extent without making hundreds of full-line caret scans in one request.
        self.command('type ' + 'w' * 16)
        self.command('wait 0')
        x, limit, _ = self.scroll()
        self.assertGreater(limit, initial)
        self.assertLessEqual(x, limit)
        self.command('wait 50')
        self.assertEqual(self.scroll()[0], x, 'an idle frame moved the caret out of view')

    def test_sideways_scrolling_stops_at_the_widest_line(self):
        self.start()
        _, limit, _ = self.scroll()
        self.command('move 600 400')    # the wheel goes to what is under the pointer
        self.command('scroll-x 100000')
        self.command('wait 50')
        self.assertEqual(self.scroll()[0], limit)
        self.command('scroll-x -100000')
        self.command('wait 50')
        self.assertEqual(self.scroll()[0], 0)

    def test_the_end_of_a_wide_line_shows_within_the_scroll(self):
        self.start()
        self.command('key End')
        self.command('wait 50')
        x, limit, _ = self.scroll()
        self.assertIn('line=1 col=', self.state())
        self.assertGreater(x, 0)
        self.assertLessEqual(x, limit)

    def test_no_bar_for_narrow_lines_or_word_wrap(self):
        self.start('narrow.txt')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command(f'open {self.project / "wide.txt"}')
        self.command('wait 50')
        self.assertIsNotNone(self.scroll()[2])
        self.command('cmd toggle_word_wrap')
        self.command('wait 50')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command('move 600 400')
        self.command('scroll-x 500')
        self.command('wait 50')
        self.assertEqual(self.scroll(), (0, 0, None))

    def test_tabs_and_wide_characters_count_as_drawn(self):
        # 300 columns three ways: ASCII, double-width characters, tabs of 4
        texts = {'ascii.txt': 'x' * 300, 'wide-chars.txt': '日' * 150, 'tabs.txt': '\t' * 75}
        for name, text in texts.items():
            (self.project / name).write_text(text + '\n', encoding='utf-8')
        self.start('ascii.txt')
        limits = []
        for name in texts:
            self.command(f'open {self.project / name}')
            self.command('wait 50')
            limits.append(self.scroll()[1])
        self.assertGreater(limits[0], 0)
        self.assertEqual(limits, [limits[0]] * 3)

    def track_colors(self):
        """the distinct colors along the bar's track: one while it is hidden"""
        _, _, (tx, ty, tw, th) = self.scroll()
        row = ty + th - 5
        pixels = self.shot()
        return {pixels[(row * 1280 + x) * 3:(row * 1280 + x) * 3 + 3] for x in range(tx + 2, tx + tw - 2)}

    def test_the_bar_flashes_on_a_sideways_scroll_and_hides_by_itself(self):
        self.start()
        self.command('move 640 300')
        self.command('wait 50')
        self.assertEqual(len(self.track_colors()), 1)
        self.command('scroll-x 300')
        self.command('wait 50')
        self.assertGreater(len(self.track_colors()), 1)
        # nothing else happens: raftaar wakes up on its own to hide the thumb, then stays idle
        self.command('print-frames')
        time.sleep(1.3)
        self.assertEqual(self.command('print-frames'), 'frames=1\n')
        time.sleep(1)
        self.assertEqual(self.command('print-frames'), 'frames=0\n')
        self.assertEqual(len(self.track_colors()), 1)

    def test_the_track_takes_the_arrow_cursor(self):
        self.start()
        _, _, (tx, ty, tw, th) = self.scroll()
        self.command(f'move {tx + tw // 2} {ty + th // 2}')
        self.command('wait 50')
        self.assertEqual(self.command('print-shape'), '7\n')

    def test_without_auto_hide_a_faint_thumb_stays(self):
        config = self.work / 'config/raftaar/config'
        config.write_text(config.read_text(encoding='utf-8') + 'auto_hide_scrollbars = false\n',
                          encoding='utf-8')
        self.start()
        self.command('move 640 300')
        self.command('wait 50')
        self.assertGreater(len(self.track_colors()), 1)

    def test_a_large_text_is_measured_again_once_editing_pauses(self):
        # past a megabyte, typing widens the bar from the lines on screen; a narrower text shows
        # once editing pauses, without a frame of its own afterwards
        big = self.project / 'big.txt'
        big.write_text(''.join(f'{i:06d} an ordinary line of text\n' for i in range(60000)),
                       encoding='utf-8')
        self.start('big.txt')
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command('key End')
        self.command('type ' + 'w' * 300)
        self.command('wait 0')
        self.assertGreater(self.scroll()[1], 0)
        for _ in range(300):
            self.command('key BackSpace')
        self.command('wait 900')        # past the measure and the scroll flash's last frame
        self.assertEqual(self.scroll(), (0, 0, None))
        self.command('print-frames')
        self.command('wait 1500')
        self.assertEqual(self.command('print-frames'), 'frames=0\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
