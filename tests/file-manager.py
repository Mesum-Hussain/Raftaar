#!/usr/bin/env python3
"""The file manager tab: its grid, a folder's menu, copy and paste, cut and Paste Into Folder, rename,
compress, pinning (GTK's bookmarks) and stars."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()

# 1280x800 at scale 1: the grid's first three cells, and where a menu's items stand below a right
# click at y 140 (the menu opens at the pointer)
CELLS = [(292, 140), (404, 140), (516, 140)]
MENU_X = 80
MENU_Y = {'cut': 196, 'copy': 224, 'rename': 316, 'paste_into': 344, 'compress': 372, 'pin': 436,
          'star': 464}
FOLDER_MENU = ['Open in New Terminal Tab', '-', 'Cut', 'Copy', 'Move to…', 'Copy to…', '-',
               'Rename…', 'Paste Into Folder', 'Compress…', 'Move to Trash', '-', 'Add to Pinned',
               'Star', '-', 'Properties']


@unittest.skipIf(os.name == 'nt', 'the file manager runs cp, mv and zip')
class FileManager(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='raftaar-files-')
        self.work = Path(self.temporary.name).resolve()
        self.folder = self.work / 'proj'
        (self.folder / 'alpha dir').mkdir(parents=True)
        (self.folder / 'alpha dir/inner.txt').write_text('inner\n')
        (self.folder / 'beta').mkdir()
        (self.folder / 'notes.txt').write_text('notes\n')
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[files]\nrestore_session = false\nrestore_project = false\n'
                          'hide_dotfiles = true\n[updates]\ncheck = false\n[git]\nenabled = false\n'
                          '[ui]\nagents_panel = false\ntooltips = false\n')
        self.env = dict(os.environ, HOME=str(self.work), XDG_CONFIG_HOME=str(self.work / 'config'),
                        XDG_STATE_HOME=str(self.work / 'state'), XDG_DATA_HOME=str(self.work / 'data'))

    def tearDown(self):
        self.temporary.cleanup()

    def run_ui(self, lines):
        script = self.work / 'commands.rsc'
        script.write_text('\n'.join(['cmd file_manager', 'wait 200', *lines, 'quit']) + '\n')
        result = subprocess.run([str(EXE), str(self.folder), '--headless', '1280x800', '--scale', '1',
                                 '--script', str(script)], env=self.env, capture_output=True,
                                text=True, timeout=30, check=True)
        return result.stdout

    @staticmethod
    def menu_item(cell, name):
        return 'click %d %d' % (cell[0] + MENU_X, MENU_Y[name])

    def test_a_folders_menu(self):
        out = self.run_ui(['click %d %d right' % CELLS[0], 'print-menu'])
        self.assertEqual(out.splitlines(), FOLDER_MENU)

    def test_copy_and_paste_makes_a_copy_beside_it(self):
        self.run_ui(['click %d %d' % CELLS[0], 'key ctrl+c', 'key ctrl+v', 'wait 1000'])
        self.assertEqual((self.folder / 'alpha dir (copy)/inner.txt').read_text(), 'inner\n')
        self.assertTrue((self.folder / 'alpha dir/inner.txt').exists())

    def test_cut_and_paste_into_a_folder_moves_it(self):
        self.run_ui(['click %d %d' % CELLS[2], 'key ctrl+x', 'click %d %d right' % CELLS[1],
                     self.menu_item(CELLS[1], 'paste_into'), 'wait 1000'])
        self.assertEqual((self.folder / 'beta/notes.txt').read_text(), 'notes\n')
        self.assertFalse((self.folder / 'notes.txt').exists())

    def test_f2_renames(self):
        self.run_ui(['click %d %d' % CELLS[2], 'key F2', 'key ctrl+a',
                     'type ' + str(self.folder / 'renamed.txt'), 'key Return', 'wait 200'])
        self.assertEqual((self.folder / 'renamed.txt').read_text(), 'notes\n')

    def test_pin_and_star(self):
        self.run_ui(['click %d %d right' % CELLS[0], self.menu_item(CELLS[0], 'pin'), 'wait 100',
                     'click %d %d right' % CELLS[0], self.menu_item(CELLS[0], 'star'), 'wait 100'])
        bookmarks = (self.work / 'config/gtk-3.0/bookmarks').read_text()
        self.assertIn('file://' + str(self.folder) + '/alpha%20dir\n', bookmarks)
        starred = (self.work / 'config/raftaar/starred').read_text()
        self.assertEqual(starred, str(self.folder / 'alpha dir') + '\n')

    def test_a_double_click_goes_into_a_folder(self):
        out = self.run_ui(['click %d %d' % CELLS[1], 'click %d %d' % CELLS[1], 'wait 100',
                           'key ctrl+shift+n', 'print-palette'])
        self.assertIn('field=' + str(self.folder / 'beta') + '/\n', out)

    @unittest.skipIf(shutil.which('zip') is None, 'zip is not installed')
    def test_compress(self):
        out = self.run_ui(['click %d %d right' % CELLS[0], self.menu_item(CELLS[0], 'compress'),
                           'print-palette', 'key Return', 'wait 1500'])
        self.assertIn('field=' + str(self.folder / 'alpha dir') + '.zip\n', out)
        self.assertTrue((self.folder / 'alpha dir.zip').stat().st_size > 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
