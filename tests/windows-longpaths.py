#!/usr/bin/env python3
"""Native file operations beyond MAX_PATH without changing the system policy."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_FILE_TEST_EXE', ROOT / 'build/windows/file_test.exe'))


def extended(path):
    return Path('\\\\?\\' + str(path.resolve()))


@unittest.skipUnless(os.name == 'nt', 'native Windows paths')
class LongPaths(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix='raftaar-longpaths-')).resolve()
        self.folder = self.work / ('folder-' + 'x' * 90)
        self.folder.mkdir()

    def tearDown(self):
        shutil.rmtree(extended(self.work))

    def run_file(self, mode, path, cwd=None):
        result = subprocess.run([str(EXE), mode, str(path).replace('\\', '/')],
                                cwd=cwd, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout.decode(errors='replace'))
        return result.stdout

    def test_existing_long_unicode_file_is_replaced_and_loaded(self):
        path = self.folder / ('café-' + 'y' * 170 + '.txt')
        self.assertGreater(len(str(path)), 260)
        extended(path).write_bytes(b'original\n')
        self.run_file('write', path)
        self.assertEqual(extended(path).read_bytes(), b'saved\n')
        self.assertEqual(self.run_file('load', path), b'saved\n')

    def test_new_long_file_and_relative_dot_components(self):
        path = self.folder / ('z' * 170 + '.txt')
        child = self.folder / 'child'
        child.mkdir()
        relative = Path(self.folder.name) / 'child' / '..' / path.name
        self.run_file('write', relative, cwd=self.work)
        self.assertEqual(extended(path).read_bytes(), b'saved\n')
        self.assertEqual(self.run_file('load', relative, cwd=self.work), b'saved\n')

    def test_long_parent_directory_keeps_atomic_save_siblings(self):
        folder = self.folder / ('deep-' + 'd' * 150)
        extended(folder).mkdir()
        path = folder / 'document.txt'
        extended(path).write_bytes(b'original\n')
        self.run_file('write', path)
        self.assertEqual(extended(path).read_bytes(), b'saved\n')
        self.assertEqual(sorted(p.name for p in extended(folder).iterdir()), ['document.txt'])

    def test_path_conversion_preserves_namespaces_and_normalizes_long_paths(self):
        def convert(value, directory=None):
            arguments = [str(ROOT / 'build/windows/filepath_test.exe'), value]
            if directory:
                arguments.append(str(directory))
            result = subprocess.run(arguments,
                                    cwd=self.work, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0)
            return result.stdout.decode('utf-8')
        for value in ('C:/short.txt', '//server/share/short.txt', 'NUL',
                      r'\\?\C:\extended.txt', r'\\.\NUL'):
            self.assertEqual(convert(value), value)
        self.assertEqual(convert('//?/C:/extended.txt'), r'\\?\C:\extended.txt')
        unc = '//server/share/' + 'u' * 260
        self.assertEqual(convert(unc), '\\'.join(['', '', '?', 'UNC', 'server', 'share', 'u' * 260]))
        path = self.folder / ('café-' + 'y' * 170 + '.txt')
        value = (self.folder / 'child' / '..' / path.name).as_posix()
        self.assertEqual(convert(value), str(extended(path)))

    def test_short_relative_and_device_paths_keep_their_behavior(self):
        path = self.work / 'short.txt'
        path.write_bytes(b'original\n')
        self.run_file('write', 'short.txt', cwd=self.work)
        self.assertEqual(path.read_bytes(), b'saved\n')
        # The document loader rejects devices; detached child stdio still opens NUL.
        result = subprocess.run([str(EXE), 'load', '/dev/null'], capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
