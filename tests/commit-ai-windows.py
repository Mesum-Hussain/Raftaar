#!/usr/bin/env python3
"""Exercise the Windows download protocol against a loopback fixture, never real models."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = shutil.which('powershell.exe') or shutil.which('pwsh')

@unittest.skipUnless(SHELL, 'PowerShell is unavailable')
class LocalModel(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-model-')
        self.root = Path(self.tmp.name)
        self.mode = ''; self.delay = 0
        owner = self
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_GET(self):
                body = b'x' * 1048576
                self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                self.wfile.write(body)
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                assert body['model'] == 'fixture:small'
                if self.path == '/api/show':
                    self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
                    self.wfile.write(b'{"model_info":{}}'); return
                assert body['stream'] is True
                self.send_response(200); self.end_headers()
                def frame(value):
                    self.wfile.write((json.dumps(value)+'\n').encode()); self.wfile.flush()
                frame({'status':'pulling layer', 'total':104857600, 'completed':52428800})
                time.sleep(owner.delay)
                if owner.mode == 'error': frame({'error':'fixture failure'})
                elif owner.mode != 'incomplete': frame({'status':'success'})
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True); self.thread.start()
        # Preserve production control flow and HTTP functions. Substitute discovery
        # and CLI operations to prevent touching the developer's Ollama or files.
        source = (ROOT/'runtime/ai/commit.ps1').read_text()
        fixture = '''function Find-Cli($name) { return 'fixture' }
function Local-Server { $env:OLLAMA_HOST = $env:TEST_HOST }
function Snapshot { return @('fixture-head','fixture diff') }
function Run($exe, $arguments, $inputText = $null) {
    if ($arguments[0] -eq 'auth') { return '{"authMethod":"claude.ai"}' }
    if ($arguments[0] -eq 'login') { return 'Logged in using ChatGPT' }
    if ($arguments[0] -eq 'show' -and -not $env:TEST_PRESENT) { throw 'missing' }
    if ($arguments[0] -eq 'run') {
        $value = 'Preserve long commit descriptions without adding terminal cursor controls to the generated message.'
        if ($arguments -notcontains '--nowordwrap') { return $value.Substring(0,73) + [char]27 + '[4D' + [char]27 + "[K`n" + $value.Substring(69) }
        return $value
    }
    if ($arguments[0] -eq 'rm') {
        if ($env:TEST_DELETE_ERROR) { throw 'fixture failure' }
        [IO.File]::WriteAllText($env:TEST_DELETED, $arguments[1])
    }
    return ''
}
if ($env:TEST_RUNTIME) { Download-Runtime ('http://' + $env:TEST_HOST) $env:TEST_RUNTIME; exit 0 }
'''
        source = source.replace("try {\n    if ($provider",fixture+"try {\n    if ($provider",1)
        self.script = self.root/'helper.ps1'; self.script.write_text(source,encoding='utf-8-sig')
        self.env = dict(os.environ, RAFTAAR_AI_PROVIDER='ollama', RAFTAAR_AI_MODEL='fixture:small',
                        RAFTAAR_AI_ACTION='setup', LOCALAPPDATA=str(self.root),
                        TEST_HOST='127.0.0.1:'+str(self.server.server_port), TEST_DELETED=str(self.root/'deleted'))

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.tmp.cleanup()

    def command(self): return [SHELL,'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(self.script)]
    def run_helper(self, **env):
        return subprocess.run(self.command(),env=dict(self.env,**env),capture_output=True,text=True,timeout=15)

    def test_live_progress(self):
        self.delay = 2
        with subprocess.Popen(self.command(),env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) as p:
            first = p.stdout.readline(); progress = p.stdout.readline()
            self.assertIn('requesting model manifest',first)
            self.assertIn('50% (50 / 100 MiB)',progress)
            self.assertIsNone(p.poll())
            rest, errors = p.communicate(timeout=10)
            self.assertEqual(p.returncode,0,errors); self.assertIn('Ready locally: fixture:small',rest)

    def test_incomplete_or_error(self):
        for mode in ('error','incomplete'):
            self.mode = mode
            r = self.run_helper(); self.assertNotEqual(r.returncode,0,r.stdout)
            self.assertNotIn('Ready locally',r.stdout)

    def test_delete(self):
        r = self.run_helper(RAFTAAR_AI_ACTION='delete',TEST_PRESENT='1')
        self.assertEqual(r.returncode,0,r.stdout); self.assertEqual((self.root/'deleted').read_text(),'fixture:small')
        self.assertIn('Runtime kept',r.stdout)

    def test_cloud_ignores_local_name(self):
        for provider in ('claude','codex'):
            r = self.run_helper(RAFTAAR_AI_PROVIDER=provider,RAFTAAR_AI_ACTION='probe',RAFTAAR_AI_MODEL='my local model')
            self.assertEqual(r.returncode,0,r.stdout)

    def test_empty_model_never_deletes_default(self):
        r = self.run_helper(RAFTAAR_AI_ACTION='delete',RAFTAAR_AI_MODEL='')
        self.assertNotEqual(r.returncode,0); self.assertFalse((self.root/'deleted').exists())

    def test_delete_error(self):
        r = self.run_helper(RAFTAAR_AI_ACTION='delete',TEST_DELETE_ERROR='1')
        self.assertNotEqual(r.returncode,0); self.assertIn('Cannot delete',r.stdout)

    def test_probe(self):
        r = self.run_helper(RAFTAAR_AI_ACTION='probe',TEST_PRESENT='1')
        self.assertEqual(r.returncode,0,r.stdout); self.assertIn('Ready locally: fixture:small',r.stdout)
        r = self.run_helper(RAFTAAR_AI_ACTION='probe')
        self.assertIn('Not downloaded: fixture:small',r.stdout)

    def test_long_local_generation(self):
        r = self.run_helper(RAFTAAR_AI_ACTION='generate',RAFTAAR_AI_REPO=str(self.root),TEST_PRESENT='1')
        self.assertEqual(r.returncode,0,r.stdout)
        self.assertEqual(r.stdout.strip(),'Preserve long commit descriptions without adding terminal cursor controls to the generated message.')

    def test_runtime_progress(self):
        target = self.root/'runtime'
        r = self.run_helper(TEST_RUNTIME=str(target))
        self.assertEqual(r.returncode,0,r.stdout); self.assertEqual(target.stat().st_size,1048576)
        self.assertIn('Runtime download: 1 MiB received',r.stdout)

if __name__ == '__main__': unittest.main(verbosity=2)
