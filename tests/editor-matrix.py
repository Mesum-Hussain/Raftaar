#!/usr/bin/env python3
"""Editor controls, palette inventory, theme rendering and narrow-window safety."""
import os
import http.server
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(os.environ.get('RAFTAAR_TEST_EXE', ROOT / 'build/raftaar')).resolve()
COMMANDS = re.findall(r'^\s+COMMAND (\w+), "([^"]+)"',
                      (ROOT / 'src/app/keys.s').read_text(encoding='utf-8'), re.M)


class EditorMatrix(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-editor-matrix-')
        self.work = Path(self.tmp.name).resolve()
        self.file = self.work / 'words.txt'
        self.file.write_text('cat Cat cat\nβeta beta\n', encoding='utf-8')
        config = self.work / 'config/raftaar/config'
        config.parent.mkdir(parents=True)
        config.write_text('[ui]\nsidebar = false\nagents_panel = false\n'
                          '[editor]\ncursor_blink = false\n'
                          '[files]\nrestore_session = false\nrestore_project = false\n'
                          '[updates]\ncheck = false\n[git]\nenabled = false\n', encoding='utf-8')
        self.env = dict(os.environ, HOME=self.work.as_posix(),
                        XDG_CONFIG_HOME=(self.work / 'config').as_posix(),
                        XDG_STATE_HOME=(self.work / 'state').as_posix())

    def tearDown(self):
        # Windows releases the folder only once the terminal's shell has exited.
        for _ in range(50):
            try:
                self.tmp.cleanup()
                return
            except OSError:
                time.sleep(0.2)
        self.tmp.cleanup()

    def run_editor(self, actions, path=None, size='1000x700', scale='1', project=None):
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), (project or self.work).as_posix(), (path or self.file).as_posix(),
                                 '--headless', size, '--scale', scale, '--script', script.as_posix()],
                                env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.assertNotIn(b'unknown\n', result.stdout)
        return result.stdout.decode('utf-8')

    def shot_path(self, name):
        base = Path(os.environ.get('RAFTAAR_TEST_ARTIFACTS', self.work)) / 'visual'
        base.mkdir(parents=True, exist_ok=True)
        return base / (name + '.ppm')

    def test_palette_contains_every_registered_command(self):
        self.assertEqual(len(COMMANDS), len(set(name for name, _ in COMMANDS)))
        actions = []
        for name, title in COMMANDS:
            actions += ['echo command=' + name, 'cmd command_palette', 'type ' + title,
                        'print-palette', 'key Escape']
        sections = self.run_editor(actions).split('command=')[1:]
        self.assertEqual(len(sections), len(COMMANDS))
        for section, (name, title) in zip(sections, COMMANDS):
            titles = [line[2:] for line in section.splitlines() if line[:2] in ('  ', '> ')]
            self.assertIn(title, titles, name)

    def test_large_match_count_does_not_paint_into_find_buttons(self):
        images = []
        for count in (1, 100000):
            file = self.work / f'count-{count}.txt'
            file.write_text('a' * count + '\n', encoding='utf-8')
            shot = self.work / f'count-{count}.ppm'
            self.run_editor(['cmd find', 'type a', 'key Up', 'move 500 400',
                             'shot ' + shot.as_posix()], path=file)
            pixels = shot.read_bytes().split(b'\n', 3)[3]
            images.append(b''.join(pixels[(y * 1000 + 848) * 3:(y * 1000 + 976) * 3]
                                   for y in range(56, 88)))
        self.assertEqual(*images, 'Match count paints over Find controls')

    def test_narrow_find_close_does_not_move_hidden_scrollbar(self):
        file = self.work / 'scroll.txt'
        file.write_text(''.join(f'line {index}\n' for index in range(1, 101)), encoding='utf-8')
        for x in (570, 610):
            with self.subTest(close_x=x):
                output = self.run_editor(['cmd find', f'click {x} 222',
                                         'click 200 192', 'print-state'], path=file,
                                         size='640x480', scale='3')
                self.assertIn('line=2 ', output)
                self.assertIn('focus=0 ', output)

    def test_find_blocks_fractional_scrollbar_writeback_while_held(self):
        config = self.work / 'config/raftaar/config'
        config.write_text(config.read_text(encoding='utf-8').replace('[editor]\n',
                          '[editor]\nfont_size = 14\n'), encoding='utf-8')
        file = self.work / 'scroll-held.txt'
        file.write_text(''.join(f'line {index}\n' for index in range(1, 101)), encoding='utf-8')
        states = []
        for frames in (0, 100):
            output = self.run_editor(['cmd find', 'move 990 311', 'down',
                'move 960 72', *(['move 960 72'] * frames), 'up', 'key Escape',
                'click 200 264', 'print-state'], path=file)
            states.append(output.strip())
        self.assertEqual(*states, 'Blocked redraws change the document scroll offset')

    def test_narrow_zoomed_find_field_accepts_mouse_focus(self):
        output = self.run_editor(['cmd find', 'type cat', 'click 500 300',
            'print-state', 'click 60 212', 'print-state', 'print-doc'], size='640x480', scale='3')
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        self.assertIn('focus=0 ', states[0])
        self.assertIn('focus=2 ', states[1])
        self.assertIn('cat Cat cat\nβeta beta\n', output)

    def test_narrow_zoomed_picker_reveals_selected_row(self):
        for index in range(8):
            (self.work / f'item{index}.txt').write_text('fixture\n', encoding='utf-8')
        output = self.run_editor(['cmd quick_open', 'type item', *(['key Down'] * 5),
                                 'print-palette', 'click 320 336', 'print-state'], size='640x480', scale='3')
        selected = next(line[2:] for line in output.splitlines() if line.startswith('> '))
        self.assertIn('active=' + selected + ' ', output)

    def test_narrow_zoomed_settings_fields_stay_inside_column(self):
        shot = self.shot_path('settings-narrow-field')
        self.run_editor(['cmd settings', 'move 320 320', 'scroll 1200',
                         'shot ' + shot.as_posix()], size='640x480', scale='3')
        header, dimensions, maximum, pixels = shot.read_bytes().split(b"\n", 3)
        width, height = map(int, dimensions.split())
        self.assertEqual((width, height), (640, 480))
        at = lambda x, y: pixels[(y * width + x) * 3:(y * width + x) * 3 + 3]
        self.assertEqual(at(20, 324), bytes.fromhex('1c1e24'), 'a field paints outside its column')
        self.run_editor(['cmd settings', 'move 320 320', 'scroll 2520',
                         'click 320 265', 'type narrow-font', 'key Return'], size='640x480', scale='3')
        import configparser
        config = configparser.ConfigParser(interpolation=None)
        config.read(self.work / 'config/raftaar/config', encoding='utf-8')
        self.assertEqual(config.get('ui', 'font', fallback=''), 'narrow-font')

    def test_narrow_zoomed_titlebar_buttons_do_not_overlap(self):
        self.run_editor(['click 60 60'], size='640x480', scale='3')
        import configparser
        config = configparser.ConfigParser(interpolation=None)
        config.read(self.work / 'config/raftaar/config', encoding='utf-8')
        self.assertTrue(config.getboolean('ui', 'sidebar'))

    def test_find_buttons_case_previous_next_and_close(self):
        output = self.run_editor(['cmd find', 'type cat', 'print-state',
                                  'click 928 72', 'print-state',
                                  'click 896 72', 'print-state',
                                  'click 864 72', 'click 928 72', 'print-state',
                                  'click 960 72', 'print-state', 'print-doc'])
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        for line, column in zip(states[:4], (4, 8, 4, 12)):
            self.assertIn('col=' + str(column) + ' ', line)
            self.assertIn('sel=3 ', line)
        self.assertIn('focus=0', states[-1])
        self.assertIn('cat Cat cat\nβeta beta\n', output)

    def test_closing_settings_restores_document_input(self):
        for close in ('cmd close_tab', 'key ctrl+w', 'click 200 20 middle'):
            with self.subTest(close=close):
                output = self.run_editor(['cmd settings', close, 'print-state',
                    'type resumed_', 'print-doc'])
                self.assertIn('active=words.txt ', output)
                self.assertIn('focus=0 ', output)
                self.assertIn('resumed_cat Cat cat\nβeta beta\n', output)

        output = self.run_editor(['cmd close_tab', 'cmd settings', 'cmd close_tab',
            'print-state', 'cmd new_file', 'type resumed', 'print-doc'])
        self.assertIn('tabs=0 focus=0 ', output)
        self.assertIn('resumed\n<eod>', output)

    def test_closing_a_tab_puts_the_strip_back(self):
        # at this zoom the settings tab scrolls the strip; once it closes, the strip's own end
        # clamps the scroll as it is drawn, and the frame that shows it must follow by itself
        output = self.run_editor(['cmd settings', 'wait 100', 'cmd close_tab', 'print-frames',
                                  'wait 100', 'print-frames', 'print-state'], size='640x480', scale='3')
        frames = [int(line[7:]) for line in output.splitlines() if line.startswith('frames=')]
        self.assertIn('active=words.txt ', output)
        self.assertGreaterEqual(frames[1], 1, output)

    def test_a_translucent_theme_color_does_not_build_up(self):
        # a user theme may give a panel an alpha: drawn over the window's background each frame,
        # not over the frame before, the explorer looks the same after any number of frames
        themes = self.work / 'config/raftaar/themes'
        themes.mkdir(parents=True)
        (themes / 'glass.theme').write_text('name = Glass\nkind = dark\nbg = #202020\nfg = #d0d0d0\n'
                                            'accent = #8aa4ff\npanel = #f0303080\n', encoding='utf-8')
        config = self.work / 'config/raftaar/config'
        config.write_text(config.read_text(encoding='utf-8').replace(
            '[ui]\nsidebar = false\n', '[ui]\nsidebar = true\nfollow_system = false\ntheme = glass\n'),
            encoding='utf-8')
        shots = [self.shot_path('glass-%d' % i) for i in range(2)]
        self.run_editor(['move 100 300', 'shot ' + shots[0].as_posix(),
                         *(['move 101 300', 'move 100 300'] * 8), 'shot ' + shots[1].as_posix()])
        first, last = (path.read_bytes() for path in shots)
        self.assertEqual(first, last, 'the translucent panel blended with the frames before it')

    def test_close_all_tabs(self):
        output = self.run_editor(['cmd settings', 'cmd close_all_tabs', 'print-state'])
        self.assertIn('tabs=0', output)

        output = self.run_editor(['type x', 'cmd settings', 'cmd close_all_tabs',
            'print-state', 'key Escape', 'print-state',
            'cmd close_all_tabs', 'key Return', 'print-state'])
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        self.assertIn('tabs=2 ', states[0])
        self.assertIn('focus=5 ', states[0])
        self.assertIn('tabs=2 ', states[1])
        self.assertIn('dirty=1 ', states[1])
        self.assertIn('tabs=0 ', states[2])

    def test_close_all_tabs_asks_for_each_modified_file(self):
        # Don't Save on the first modified file, then the next one asks; Save writes it and every
        # tab closes
        other = self.work / 'other.txt'
        other.write_text('other\n', encoding='utf-8')
        output = self.run_editor(['type a', 'open ' + other.as_posix(), 'type b', 'cmd settings',
            'cmd close_all_tabs', 'print-state', 'click 566 345', 'print-state', 'key Return',
            'print-state'])
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        self.assertIn('tabs=3 active=words.txt ', states[0])
        self.assertIn('focus=5 ', states[0])
        self.assertIn('tabs=2 active=other.txt ', states[1])
        self.assertIn('focus=5 ', states[1])
        self.assertIn('tabs=0 ', states[2])
        self.assertEqual(self.file.read_text(encoding='utf-8'), 'cat Cat cat\nβeta beta\n')
        self.assertEqual(other.read_text(encoding='utf-8'), 'bother\n')

        # an untitled file's Save opens Save As, and closing stops there
        output = self.run_editor(['cmd new_file', 'type u', 'cmd close_all_tabs', 'key Return',
            'print-state'])
        self.assertIn('tabs=2 active=untitled ', output)
        self.assertIn('focus=7 ', output)

    @unittest.skipIf(os.name == 'nt' or (hasattr(os, 'geteuid') and os.geteuid() == 0),
                     'a read-only folder does not stop Windows or root from writing')
    def test_close_all_tabs_stops_where_a_save_fails(self):
        locked = self.work / 'locked'
        locked.mkdir()
        (locked / 'note.txt').write_text('note\n', encoding='utf-8')
        locked.chmod(0o555)
        try:
            output = self.run_editor(['open ' + (locked / 'note.txt').as_posix(), 'type x',
                'cmd close_all_tabs', 'key Return', 'print-state', 'print-toast'])
        finally:
            locked.chmod(0o755)
        self.assertIn('tabs=2 ', output)
        self.assertIn('dirty=1 ', output)
        self.assertIn('toast=Could not save the file\n', output)
        self.assertEqual((locked / 'note.txt').read_text(encoding='utf-8'), 'note\n')

    def test_close_all_tabs_keys_stay_in_the_terminal(self):
        # Ctrl+Shift+W closes a tab in other terminals; in raftaar's it goes to the program, so the
        # editor keeps its tabs. The palette still closes them from there, all but the terminal's.
        if os.name != 'nt':
            self.env['SHELL'] = '/bin/sh'
        output = self.run_editor(['cmd settings', 'cmd toggle_terminal', 'key ctrl+shift+w',
            'key super+shift+w', 'print-state', 'cmd command_palette', 'type Close All Tabs',
            'key Return', 'print-state'])
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        self.assertIn('tabs=3 ', states[0])
        self.assertIn('focus=8 ', states[0])
        self.assertIn('tabs=1 ', states[1])
        self.assertIn('focus=8 ', states[1])

    def test_closing_inactive_tabs_preserves_focus(self):
        output = self.run_editor(['cmd settings', 'cmd prev_tab', 'cmd find',
            'type cat', 'click 200 20 middle', 'print-state', 'key Escape',
            'type resumed_', 'print-doc'])
        self.assertIn('tabs=1 active=words.txt ', output)
        self.assertIn('focus=2 ', output)
        self.assertIn('resumed_ Cat cat\nβeta beta\n', output)

        output = self.run_editor(['cmd settings', 'click 100 20 middle', 'print-state'])
        self.assertIn('tabs=1 focus=4 ', output)

    def test_replace_one_and_all_buttons_and_undo(self):
        output = self.run_editor(['cmd replace', 'type cat', 'key Tab', 'type dog',
                                  'click 810 112', 'print-doc',
                                  'click 880 112', 'print-doc',
                                  'key Escape', 'cmd undo', 'print-doc',
                                  'cmd undo', 'print-doc'])
        docs = output.split('\n<eod>\n')[:-1]
        self.assertEqual(docs, ['dog Cat cat\nβeta beta\n', 'dog dog dog\nβeta beta\n',
                                'dog Cat cat\nβeta beta\n', 'cat Cat cat\nβeta beta\n'])

    def test_image_edit_commands_keep_image_and_file_intact(self):
        image = ROOT / 'tests/data/images/rgba.png'
        before = image.read_bytes()
        actions = []
        for command in ('undo redo cut copy paste select_all select_line select_next '
                        'duplicate_line delete_line move_line_up move_line_down indent outdent '
                        'toggle_comment newline_below newline_above find replace find_next '
                        'find_prev goto_line select_language reload_file save').split():
            actions += ['cmd ' + command, 'key Escape', 'print-state']
        output = self.run_editor(actions, path=image)
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        self.assertEqual(len(states), len(actions) // 3)
        self.assertTrue(all('tabs=1 active=rgba.png image=24x16' in line for line in states), output)
        self.assertEqual(image.read_bytes(), before)

    def test_all_builtin_themes_render_and_preserve_document(self):
        actions, expected = [], []
        for theme in sorted((ROOT / 'runtime/themes').glob('*.theme')):
            name = re.search(r'^name\s*=\s*(.+)$', theme.read_text(encoding='utf-8'), re.M)[1]
            expected.append(theme.stem)
            shot = self.shot_path('theme-' + theme.stem)
            actions += ['cmd select_theme', 'type ' + name, 'key Return', 'print-state',
                        'move 500 500', 'shot ' + shot.as_posix()]
        actions += ['print-doc']
        output = self.run_editor(actions)
        states = [line for line in output.splitlines() if line.startswith('tabs=')]
        self.assertEqual(len(states), len(expected))
        for state, theme in zip(states, expected):
            self.assertIn('theme=' + theme, state)
            data = self.shot_path('theme-' + theme).read_bytes()
            self.assertTrue(data.startswith(b'P6\n1000 700\n255\n'))
            self.assertEqual(len(data.split(b'\n', 3)[3]), 1000 * 700 * 3)
        self.assertIn('cat Cat cat\nβeta beta\n\n<eod>', output)

    def test_overlays_survive_sizes_and_fractional_scales(self):
        for size in ('200x160', '640x480', '1400x860'):
            for scale in ('0.5', '1', '1.25', '1.5', '2', '3'):
                with self.subTest(size=size, scale=scale):
                    shot = self.shot_path('layout-' + size + '-' + scale)
                    overlays = {name: self.shot_path(name + '-' + size + '-' + scale)
                                for name in ('find', 'quick-open', 'commands', 'settings')}
                    output = self.run_editor(['cmd find', 'type cat',
                        'shot ' + overlays['find'].as_posix(), 'key Escape',
                        'cmd quick_open', 'type words',
                        'shot ' + overlays['quick-open'].as_posix(), 'key Escape',
                        'cmd command_palette', 'shot ' + overlays['commands'].as_posix(), 'key Escape',
                        'cmd settings', 'shot ' + overlays['settings'].as_posix(), 'cmd close_tab',
                        'print-state', 'print-doc', 'shot ' + shot.as_posix()], size=size, scale=scale)
                    self.assertIn('active=words.txt ', output)
                    self.assertIn('cat Cat cat\nβeta beta\n', output)
                    width, height = map(int, size.split('x'))
                    for image in (shot, *overlays.values()):
                        self.assertEqual(len(image.read_bytes().split(b'\n', 3)[3]), width * height * 3)

    def test_project_names_do_not_paint_over_toolbar_buttons(self):
        def render(project, scale):
            shot = self.work / (project.name + '-' + str(scale) + '.ppm')
            script = self.work / 'title.rsc'
            script.write_text(f'move 500 300\nshot {shot.as_posix()}\n'
                              f'click {640 - 124 * scale} {20 * scale}\n'
                              'print-state\nprint-menu\nquit\n', encoding='utf-8')
            result = subprocess.run([str(EXE), project.as_posix(), '--headless', '640x480',
                                     '--scale', str(scale), '--script', script.as_posix()],
                                    env=self.env, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
            self.assertEqual(result.stdout.decode('utf-8'), 'tabs=1 focus=4 theme=raftaar-dark\nnone\n')
            return shot.read_bytes().split(b'\n', 3)[3]
        short, long = self.work / 'a', self.work / ('project-' + 'long-name-' * 15)
        short.mkdir()
        long.mkdir()
        for scale in (1, 2):
            with self.subTest(scale=scale):
                a, b = render(short, scale), render(long, scale)
                start = 640 - 220 * scale
                for y in range(40 * scale):
                    span = slice((640 * y + start) * 3, (640 * y + 640) * 3)
                    self.assertEqual(a[span], b[span], 'Project name paints into toolbar')

    def test_narrow_status_preserves_cursor_label(self):
        for scale in (2, 3):
            images = []
            for width in (640, 1400):
                shot = self.work / f'status-{width}-{scale}.ppm'
                actions = ['cmd find', 'type cat', 'key Escape', 'move 500 200',
                           'shot ' + shot.as_posix()]
                if width == 640:
                    actions += [f'click {100 * scale} {480 - 15 * scale}', 'print-state']
                output = self.run_editor(actions, size=f'{width}x480', scale=str(scale))
                if width == 640:
                    self.assertIn('focus=0 ', output, 'Hidden language label retains a hitbox')
                pixels = shot.read_bytes().split(b'\n', 3)[3]
                images.append(b''.join(pixels[(width * y) * 3:(width * y + 44 * scale) * 3]
                                       for y in range(480 - 30 * scale, 480)))
            self.assertEqual(*images, 'Status details paint over cursor label')

    def test_long_worktree_branch_does_not_take_updater_click(self):
        repository = self.work / 'repository'
        repository.mkdir()
        (repository / 'words.txt').write_text('tracked\n', encoding='utf-8')
        def git(*args):
            subprocess.run(['git', '-C', repository.as_posix(), *args], check=True,
                           env=self.env, capture_output=True, timeout=30)
        git('init', '-q')
        git('add', 'words.txt')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')
        worktree = self.work / ('w' * 63)
        git('worktree', 'add', '-q', '-b', 'c' * 60, worktree.as_posix())
        config = self.work / 'config/raftaar/config'
        config.write_text(config.read_text(encoding='utf-8').replace('enabled = false', 'enabled = true'),
                          encoding='utf-8')
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = b'99.0.0\n'
                self.send_response(200 if self.path == '/latest/download/VERSION' else 404)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def log_message(self, *args):
                pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.env['RAFTAAR_RELEASES_URL'] = f'http://127.0.0.1:{server.server_port}'
        target = self.work / 'owned-update-target'
        target.write_bytes(b'owned fixture\n')
        self.env['RAFTAAR_UPDATE_TARGET'] = target.as_posix()
        try:
            output = self.run_editor(['wait-git', 'cmd check_for_updates', 'wait-update',
                                      'print-update', 'print-git', 'print-state',
                                      'click 750 587', 'wait-update', 'print-state'],
                                     path=worktree / 'words.txt', project=worktree, size='800x600')
            self.assertIn('state=available ', output)
            self.assertIn(' latest=99.0.0 ', output)
            self.assertIn('c' * 60, output)
            states = [line for line in output.splitlines() if line.startswith('tabs=')]
            self.assertEqual(len(states), 2)
            self.assertTrue(all('tabs=1 active=words.txt ' in state for state in states), output)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main(verbosity=2)
