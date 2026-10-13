#!/usr/bin/env python3
"""Headless mouse-wheel regression checks for the shared path picker. Picking a folder, its list starts
with two rows (Open, Open in a new window), so folder00 is the third: 32 px rows from y 110."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', str(ROOT/'build/raftaar'))).resolve()

class PaletteScroll(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-picker-')
        self.home = Path(self.tmp.name)
        self.project = self.home/'folders'
        self.project.mkdir()
        for i in range(40): (self.project/f'folder{i:02}').mkdir()
        self.env = dict(os.environ, HOME=self.home.as_posix(), XDG_CONFIG_HOME=(self.home/'config').as_posix(),
                        XDG_STATE_HOME=(self.home/'state').as_posix())

    def tearDown(self): self.tmp.cleanup()

    def pick(self, actions, expected, row_y=110):
        script = self.home/'scroll.rsc'
        script.write_text('\n'.join(['cmd open_folder','move 500 110',*actions,
                                     'move 501 110','wait 100',f'click 500 {row_y}','print-palette'])+'\n')
        r = subprocess.run([str(EXE),self.project.as_posix(),'--headless','1400x860',
                            '--script',script.as_posix()],env=self.env,capture_output=True,text=True,timeout=15)
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('/'+expected+'/',r.stdout,r.stdout)

    def test_scroll_survives_redraw(self):
        self.pick(['scroll 96','move 502 110','wait 100'],'folder01')

    def test_small_deltas_accumulate(self):
        self.pick(['scroll 8']*4,'folder00',row_y=142)

    def test_repeated_wheel_events(self):
        self.pick(['scroll 32']*3,'folder01')

    def test_bottom_clamp_and_reverse(self):
        self.pick(['scroll 4000']+['scroll 8']*3+['scroll -8']*4,'folder27')

    def test_top_clamp_and_reverse(self):
        self.pick(['scroll -4000']+['scroll -8']*3+['scroll 8']*4,'folder00',row_y=142)

    def test_keyboard_reveals_selection(self):
        self.pick(['scroll 320','key Down'],'folder00',row_y=142)

    def test_up_at_first_selection_reveals_top(self):
        self.pick(['scroll 320','key Up'],'folder00',row_y=174)

    def test_filter_clamps_scrolled_list(self):
        self.pick(['scroll 640','type folder39'],'folder39',row_y=174)

    def test_filter_resets_partial_scroll(self):
        self.pick(['scroll 24','type folder','scroll 8'],'folder00',row_y=174)

    def test_reopen_resets_partial_scroll(self):
        self.pick(['scroll 24','key Escape','cmd open_folder','scroll 8','scroll 24'],'folder00',row_y=142)

if __name__ == '__main__': unittest.main(verbosity=2)
