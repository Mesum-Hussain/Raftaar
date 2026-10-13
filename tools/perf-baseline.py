#!/usr/bin/env python3
"""Headless performance baseline: times raftaar on fixed workloads, so a version can be compared with
the last. Standard library only. Every run has its own HOME and XDG folders; fixtures are made in a
temporary folder from fixed seeds.

    python3 tools/perf-baseline.py                       # build/raftaar
    python3 tools/perf-baseline.py --binary OLD --binary NEW
    python3 tools/perf-baseline.py --json results.json   # medians, for a later comparison

Times are medians of --runs rounds (default 5); each round times every build once, in turns, so
caches and the machine's load treat them alike. A time is a whole headless process, less a run of
the same setup without the measured steps where that makes sense; it includes the scripted
commands' own frames, not putting frames on a screen.
"""
import argparse
import json
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ('[ui]\nsidebar = {sidebar}\n[editor]\ncursor_blink = false\n'
          '[terminal]\nshell = /bin/sh\n[files]\nrestore_session = false\nrestore_project = false\n'
          '[updates]\ncheck = false\n[git]\nenabled = false\n')


class Bench:
    def __init__(self, exe, work, runs):
        self.exe, self.work, self.runs = exe, work, runs

    def run(self, target, actions=(), size='1280x800', scale='1', sidebar=True, home=None):
        """seconds for one run of raftaar TARGET with the script's actions, then quit"""
        home = home or self.work / 'home'
        (home / 'config/raftaar').mkdir(parents=True, exist_ok=True)
        (home / 'config/raftaar/config').write_text(
            CONFIG.format(sidebar=str(sidebar).lower()), encoding='utf-8')
        shutil.rmtree(home / 'state', ignore_errors=True)
        script = self.work / 'actions.rsc'
        script.write_text('\n'.join([*actions, 'quit']) + '\n', encoding='utf-8')
        env = dict(os.environ, HOME=home.as_posix(), XDG_CONFIG_HOME=(home / 'config').as_posix(),
                   XDG_STATE_HOME=(home / 'state').as_posix())
        start = time.perf_counter()
        result = subprocess.run([self.exe, *[t.as_posix() for t in target], '--headless', size, '--scale', scale,
                                 '--script', script.as_posix()], env=env, capture_output=True, timeout=300)
        elapsed = time.perf_counter() - start
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        self.out = result.stdout.decode('utf-8', errors='replace')
        return elapsed

    def median(self, *args, **kwargs):
        return statistics.median(self.run(*args, **kwargs) for _ in range(self.runs))

    def per_step(self, target, setup, step, n, **kwargs):
        """ms per step: (setup + n steps) less setup alone"""
        return (self.median(target, setup + step * n, **kwargs) - self.median(target, setup, **kwargs)) / n * 1000


def fixtures(work):
    rng = random.Random(7)
    empty = work / 'empty'
    empty.mkdir()
    folder = work / 'folder'
    folder.mkdir()
    for i in range(20000):
        (folder / ('f%.12f' % rng.random())).write_bytes(b'')
    big = work / 'big.txt'
    big.write_text(''.join('x' * rng.randint(0, 80) + '\n' for _ in range(250000)), encoding='utf-8')
    code = work / 'code.c'
    code.write_text(''.join('static int value_%d(int a) { return a * %d + 1; } // %s\n' % (i, i, 'x' * (i % 40))
                            for i in range(50000)), encoding='utf-8')
    line = work / 'line.json'
    line.write_text('{' + ','.join('"k%d":[%d,"v%d",true]' % (i, i, i) for i in range(90000)) + '}\n',
                    encoding='utf-8')
    lines = work / 'lines.txt'
    lines.write_text(''.join('line %d needle text\n' % i for i in range(1000000)), encoding='utf-8')
    matches = work / 'matches.txt'
    matches.write_text('needle xyz\n' * 80000, encoding='utf-8')
    output = work / 'output.txt'
    output.write_text(''.join('line %d of the output, some text to fill it\n' % i for i in range(400000)),
                      encoding='utf-8')
    return locals()


def measure(exe, work):
    """one sample of every workload"""
    f = FIXTURES
    b = Bench(exe, work, 1)
    moves = lambda n: ['move %d 600' % (500 + i % 2) for i in range(n)]
    results = {}
    # startups after one not timed, so the file cache holds what they read
    for name, target in (('startup, empty folder (ms)', f['empty']), ('startup, folder of 20,000 files (ms)',
                         f['folder']), ('open a 20 MB file (ms)', f['big'])):
        b.run([target])
        results[name] = b.median([target]) * 1000
    # each step is two moves, a frame each
    results['editor frame, 2560x1600 @2x (ms)'] = b.per_step(
        [f['code']], [], ['move 500 600', 'move 501 600'], 50, size='2560x1600', scale='2') / 2
    results['palette frame, 2560x1600 @2x (ms)'] = b.per_step(
        [f['code']], ['cmd command_palette'], ['move 500 900', 'move 501 900'], 50, size='2560x1600',
        scale='2') / 2
    results['frame, caret at the end of a 2.7 MB line (ms)'] = b.per_step(
        [f['line']], ['key End'], ['move 500 600', 'move 501 600'], 20) / 2
    results['find field keystroke, 1M lines (ms)'] = b.per_step(
        [f['lines']], ['cmd find'], ['type e', 'key BackSpace'], 5) / 2
    results['replace all, 80,000 matches (ms)'] = (
        b.median([f['matches']], ['key ctrl+h', 'key ctrl+a', 'type needle', 'key Tab', 'key ctrl+a',
                                  'type replacement', 'key ctrl+Return'])
        - b.median([f['matches']], ['key ctrl+h', 'key ctrl+a', 'type needle', 'key Tab', 'key ctrl+a',
                                    'type replacement'])) * 1000
    if os.name != 'nt':
        results['terminal: cat 18 MB (ms)'] = (
            b.median([f['empty']], ['cmd toggle_terminal', 'wait-term $', 'type cat %s; echo DO""NE'
                                    % f['output'].as_posix(), 'key Return', 'wait-term DONE'])
            - b.median([f['empty']], ['cmd toggle_terminal', 'wait-term $', 'type true; echo DO""NE',
                                      'key Return', 'wait-term DONE'])) * 1000
    return results


def main():
    global FIXTURES
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--binary', action='append', help='raftaar to time (repeat to compare)')
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--json', help='write the results here')
    args = parser.parse_args()
    binaries = args.binary or [str(ROOT / 'build/raftaar')]
    with tempfile.TemporaryDirectory(prefix='raftaar-perf-') as temporary:
        work = Path(temporary).resolve()
        print('making fixtures...', file=sys.stderr)
        FIXTURES = fixtures(work)
        names = {exe: '%s (%s)' % (subprocess.run([exe, '--version'], capture_output=True,
                                                   text=True).stdout.strip(), exe) for exe in binaries}
        samples = {exe: {} for exe in binaries}
        for round in range(args.runs):
            print('round %d of %d...' % (round + 1, args.runs), file=sys.stderr)
            order = binaries[round % len(binaries):] + binaries[:round % len(binaries)]
            for exe in order:
                for name, value in measure(exe, work).items():
                    samples[exe].setdefault(name, []).append(value)
        table = {names[exe]: {name: statistics.median(values) for name, values in samples[exe].items()}
                 for exe in binaries}
    names = list(next(iter(table.values())))
    width = max(map(len, names))
    print(' ' * width + ''.join('  %18s' % k.split(' (')[0] for k in table))
    for name in names:
        print(name.ljust(width) + ''.join('  %18.2f' % column[name] for column in table.values()))
    if args.json:
        Path(args.json).write_text(json.dumps(table, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
