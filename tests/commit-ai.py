#!/usr/bin/env python3
"""Hermetic provider and headless UI checks. Never contacts a provider or downloads models."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import tarfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
STUB = r'''
import json, os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
a = sys.argv[1:]
w = pathlib.Path(os.environ['FIXTURE'])
with (w/'calls').open('a') as f: f.write(json.dumps([name,a])+'\n')
if name == 'curl' and os.environ.get('ARCHIVE') and any(x.startswith('https://') for x in a):
    import shutil
    url = next(x for x in a if x.startswith('https://'))
    out = a[a.index('-o')+1]
    shutil.copyfile(os.environ['CHECKSUMS'] if url.endswith('sha256sum.txt') else os.environ['ARCHIVE'], out)
    sys.exit()
if name == 'curl' and any(x.endswith('/api/pull') for x in a):
    print(json.dumps({'status':'pulling manifest'}), flush=True)
    print(json.dumps({'status':'pulling layer', 'total':104857600, 'completed':52428800}), flush=True)
    if os.environ.get('PULL_GATE'):
        gate = pathlib.Path(os.environ['PULL_GATE'])
        deadline = time.monotonic() + 20
        while not gate.exists() and time.monotonic() < deadline: time.sleep(.02)
        if not gate.exists(): sys.exit(9)
    time.sleep(float(os.environ.get('PULL_DELAY', '0')))
    if os.environ.get('PULL_ERROR'): print('{"error":"fixture failure"}', flush=True); sys.exit()
    if os.environ.get('PULL_INCOMPLETE'): sys.exit()
    print('{"status":"verifying sha256 digest"}', flush=True)
    print('{"status":"success"}', flush=True)
    if os.environ.get('PULL_TRANSPORT'): sys.exit(7)
    (w/'deleted').unlink(missing_ok=True); (w/'pulled').touch(); sys.exit()
if name == 'curl':
    out = a[a.index('-o')+1] if '-o' in a else None
    value = '{"remote_model":"secret-remote"}' if os.environ.get('REMOTE') else '{"model_info":{}}'
    if out: pathlib.Path(out).write_text(value)
    else: print(value)
    sys.exit()
if a[:2] == ['auth','status']:
    time.sleep(float(os.environ.get('AUTH_DELAY','0')))
    print(json.dumps({'authMethod': 'api_key' if os.environ.get('API_AUTH') else 'claude.ai'})); sys.exit()
if a[:2] == ['login','status']:
    print('Logged in using API key' if os.environ.get('API_AUTH') else 'Logged in using ChatGPT',file=sys.stderr); sys.exit()
if name == 'ollama':
    if a == ['serve']:
        print('Listening on '+os.environ['OLLAMA_HOST'], file=sys.stderr, flush=True)
        time.sleep(60); sys.exit()
    if a == ['list']: print('NAME ID SIZE'); sys.exit()
    if a[0] == 'show': sys.exit(1 if (w/'deleted').exists() or (os.environ.get('MISSING_MODEL') and not (w/'pulled').exists()) else 0)
    if a[0] == 'rm':
        if os.environ.get('DELETE_ERROR'): sys.exit(1)
        (w/'pulled').unlink(missing_ok=True); (w/'deleted').write_text(a[1]); sys.exit()
    assert os.environ.get('OLLAMA_NO_CLOUD') == '1'
    assert os.environ.get('OLLAMA_REMOTES') == 'raftaar-local.invalid'
    assert os.environ['OLLAMA_HOST'].startswith('127.0.0.1:')
for key in ['ANTHROPIC_API_KEY','CODEX_API_KEY','OPENAI_API_KEY','ANTHROPIC_AUTH_TOKEN']:
    assert key not in os.environ, key
prompt = sys.stdin.read()
(w/'prompt').write_text(prompt)
(w/'running').touch()
time.sleep(float(os.environ.get('DELAY','0')))
if os.environ.get('MUTATE'):
    pathlib.Path(os.environ['MUTATE']).write_text('changed during generation\n')
if os.environ.get('FAIL'): sys.exit(3)
if os.environ.get('WRAP_OUTPUT') and name == 'ollama':
    value = 'Preserve long commit descriptions without adding terminal cursor controls to the generated message.'
    if '--nowordwrap' not in a: value = value[:73] + '\x1b[4D\x1b[K\n' + value[69:]
    print(value); sys.exit()
if os.environ.get('CONTROL'): print('\x1b[31mBad'); sys.exit()
if os.environ.get('BIG'): print('x'*20000); sys.exit()
print('Describe the selected changes\n\nKeep the scope precise.')
'''

class CommitAI(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='raftaar-ai-test-')
        self.w = Path(self.tmp.name)
        self.repo = self.w / "repo 'quoted $; name"
        self.repo.mkdir()
        self.bin = self.w/'bin'; self.bin.mkdir()
        for name in ('claude','codex','ollama','curl'):
            p = self.bin/name
            p.write_text('#!'+sys.executable+'\n'+STUB)
            p.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.w), PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        XDG_CONFIG_HOME=str(self.w/'config'), XDG_STATE_HOME=str(self.w/'state'),
                        XDG_DATA_HOME=str(self.w/'data'), FIXTURE=str(self.w),
                        RAFTAAR_AI_ACTION='generate', RAFTAAR_AI_PROVIDER='claude',
                        RAFTAAR_AI_MODEL='qwen2.5-coder:1.5b', RAFTAAR_AI_REPO=str(self.repo),
                        ANTHROPIC_API_KEY='must-not-be-used', OPENAI_API_KEY='must-not-be-used',
                        CODEX_API_KEY='must-not-be-used', ANTHROPIC_AUTH_TOKEN='must-not-be-used')
        self.git('init','-q')
        self.git('config','user.email','test@example.invalid'); self.git('config','user.name','Test')
        (self.repo/'a.txt').write_text('original\n')
        self.git('add','.'); self.git('commit','-qm','Initial')
        (self.repo/'a.txt').write_text('new content\n')

    def tearDown(self): self.tmp.cleanup()
    def git(self,*args):
        return subprocess.check_output(['git','-C',str(self.repo),*args],env=self.env,stderr=subprocess.DEVNULL)
    def helper(self, **env):
        return subprocess.run(['/bin/sh',str(ROOT/'runtime/ai/commit.sh')],env=dict(self.env,**env),
                              capture_output=True,text=True,timeout=15)
    def calls(self):
        return [json.loads(x) for x in (self.w/'calls').read_text().splitlines()] if (self.w/'calls').exists() else []
    def native(self, lines, provider='claude', model='qwen2.5-coder:1.5b', **env):
        config = self.w/'config/raftaar'; config.mkdir(parents=True,exist_ok=True)
        (config/'config').write_text('[git]\ncommit_ai = '+provider+'\ncommit_model = '+model+'\n[ui]\nagents_panel = false\nsidebar_width = 240\n')
        script = self.w/'test.rsc'; script.write_text('\n'.join(lines)+'\n')
        return subprocess.run([str(ROOT/'build/raftaar'),str(self.repo),'--headless','1400x860','--script',str(script)],
                              env=dict(self.env,**env),capture_output=True,text=True,timeout=35)

    def test_off(self):
        r = self.helper(RAFTAAR_AI_PROVIDER='off'); self.assertEqual(r.returncode,0); self.assertEqual(self.calls(),[])
    def test_staged_only_and_credentials(self):
        self.git('add','a.txt'); (self.repo/'a.txt').write_text('unstaged private\n')
        (self.repo/'untracked').write_text('untracked private\n')
        r = self.helper(); self.assertEqual(r.returncode,0,r.stdout)
        prompt=(self.w/'prompt').read_text(); self.assertIn('new content',prompt)
        self.assertNotIn('unstaged private',prompt); self.assertNotIn('untracked private',prompt)
        args=self.calls()[-1][1]; self.assertIn('--tools',args); self.assertEqual(args[args.index('--tools')+1],'')
    def test_commit_all_preserves_index(self):
        (self.repo/'untracked').write_text('include new file\n')
        before=(self.repo/'.git/index').read_bytes()
        r=self.helper(); self.assertEqual(r.returncode,0,r.stdout)
        self.assertIn('include new file',(self.w/'prompt').read_text())
        self.assertEqual(before,(self.repo/'.git/index').read_bytes())
    def test_unborn(self):
        self.git('checkout','--orphan','new'); self.git('read-tree','--empty')
        r=self.helper(); self.assertEqual(r.returncode,0,r.stdout)
    def test_codex(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='codex'); self.assertEqual(r.returncode,0,r.stdout)
        self.assertIn('forced_login_method="chatgpt"',self.calls()[-1][1])
    def test_api_auth_rejected(self):
        for provider in ('claude','codex'):
            r=self.helper(RAFTAAR_AI_PROVIDER=provider,API_AUTH='1'); self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.w/'prompt').exists())
    def test_stale_diff(self):
        r=self.helper(MUTATE=str(self.repo/'a.txt')); self.assertNotEqual(r.returncode,0); self.assertIn('Changes moved',r.stdout)
    def test_bad_output(self):
        for setting in ('FAIL','CONTROL','BIG'):
            r=self.helper(**{setting:'1'}); self.assertNotEqual(r.returncode,0,(setting,r.stdout))
    def test_cloud_ignores_local_model_name(self):
        for provider in ('claude','codex'):
            for action in ('probe','generate'):
                r=self.helper(RAFTAAR_AI_PROVIDER=provider,RAFTAAR_AI_ACTION=action,RAFTAAR_AI_MODEL='my local model')
                self.assertEqual(r.returncode,0,r.stdout)

    def test_model_injection(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_MODEL='x; touch INJECTED'); self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.calls(),[])
    def test_local(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama'); self.assertEqual(r.returncode,0,r.stdout)
        self.assertFalse(any(a[0]=='pull' for n,a in self.calls() if n=='ollama'))
    def test_local_long_output(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',WRAP_OUTPUT='1')
        self.assertEqual(r.returncode,0,r.stdout)
        self.assertEqual(r.stdout.strip(),'Preserve long commit descriptions without adding terminal cursor controls to the generated message.')
        r=self.native(['wait-git','wait-ai','cmd git_history','wait-git','cmd git_generate_message',
                       'wait-ai','print-scm'],provider='ollama',WRAP_OUTPUT='1')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('message=Preserve long commit descriptions without adding terminal cursor controls to the generated message.',r.stdout)

    def test_remote_model(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',REMOTE='1'); self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.w/'prompt').exists())
    def test_local_setup(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='setup',MISSING_MODEL='1')
        self.assertEqual(r.returncode,0,r.stdout); self.assertTrue((self.w/'pulled').exists())
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='setup',MISSING_MODEL='1')
        self.assertEqual(r.returncode,0,r.stdout)
        self.assertEqual(sum(any(x.endswith('/api/pull') for x in a) for n,a in self.calls() if n=='curl'),1)
        self.assertIn('qwen2.5-coder:1.5b',r.stdout)
    def test_download_progress(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='setup',MISSING_MODEL='1')
        self.assertEqual(r.returncode,0,r.stdout)
        self.assertIn('@Model file: 50% (50 / 100 MiB)',r.stdout)
        self.assertIn('@Verifying model files',r.stdout)

    def test_download_failure_is_not_ready(self):
        for mode in ('PULL_ERROR','PULL_INCOMPLETE','PULL_TRANSPORT'):
            r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='setup',MISSING_MODEL='1',**{mode:'1'})
            self.assertNotEqual(r.returncode,0,(mode,r.stdout))
            self.assertNotIn('Ready locally',r.stdout)

    def test_probe_identifies_model(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='probe')
        self.assertEqual(r.returncode,0,r.stdout); self.assertIn('Ready locally: qwen2.5-coder:1.5b',r.stdout)
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='probe',MISSING_MODEL='1')
        self.assertIn('Not downloaded',r.stdout)
        self.assertFalse(any('/api/pull' in ' '.join(a) for n,a in self.calls()))

    def test_delete_selected_model(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='delete',RAFTAAR_AI_MODEL='custom:small')
        self.assertEqual(r.returncode,0,r.stdout); self.assertEqual((self.w/'deleted').read_text(),'custom:small')
        self.assertIn('Deleted: custom:small. Runtime kept.',r.stdout)
        self.assertFalse(any('/api/pull' in ' '.join(a) for n,a in self.calls()))

    def test_delete_failure(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='delete',DELETE_ERROR='1')
        self.assertNotEqual(r.returncode,0); self.assertIn('Cannot delete',r.stdout)

    def test_native_live_download(self):
        r=self.native(['wait-git','wait-ai','cmd ai_setup','wait 1000','print-ai','print-state',
                       'wait-ai','print-ai'],provider='ollama',MISSING_MODEL='1',PULL_DELAY='2')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('Model file: 50% (50 / 100 MiB)',r.stdout)
        self.assertIn('Ready locally: qwen2.5-coder:1.5b',r.stdout)

    def test_live_progress_before_download_completes(self):
        gate = self.w / 'continue-download'
        progress = threading.Event()
        output = []
        process = subprocess.Popen(['/bin/sh', str(ROOT / 'runtime/ai/commit.sh')],
            env=dict(self.env, RAFTAAR_AI_PROVIDER='ollama', RAFTAAR_AI_ACTION='setup',
                     MISSING_MODEL='1', PULL_GATE=str(gate)),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def read():
            for line in process.stdout:
                output.append(line)
                if line == '@Model file: 50% (50 / 100 MiB)\n': progress.set()
        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        try:
            self.assertTrue(progress.wait(10), 'Progress was buffered while the download remained open: ' + ''.join(output))
            self.assertIsNone(process.poll(), 'Download finished before the gate was released')
            self.assertFalse((self.w / 'pulled').exists())
        finally:
            gate.touch()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            reader.join(timeout=5)
            process.stdout.close()
            process.stderr.close()
        self.assertEqual(process.returncode, 0, ''.join(output))
        self.assertIn('Ready locally: qwen2.5-coder:1.5b\n', output)

    def test_native_download_cancel(self):
        r=self.native(['wait-git','wait-ai','cmd ai_setup','wait 1000','cmd ai_setup','wait-ai','print-ai'],
                      provider='ollama',MISSING_MODEL='1',PULL_DELAY='5')
        self.assertEqual(r.returncode,0,r.stderr); self.assertIn('Cancelled',r.stdout)
        self.assertFalse((self.w/'pulled').exists())

    def test_native_delete_confirmation(self):
        r=self.native(['wait-git','wait-ai','cmd ai_delete','key Escape','wait-ai'],provider='ollama')
        self.assertEqual(r.returncode,0,r.stderr); self.assertFalse((self.w/'deleted').exists())
        r=self.native(['wait-git','wait-ai','cmd ai_delete','key Return','wait-ai','print-ai'],provider='ollama')
        self.assertEqual(r.returncode,0,r.stderr); self.assertTrue((self.w/'deleted').exists(),r.stdout)
        self.assertIn('Deleted: qwen2.5-coder:1.5b',r.stdout)

    def test_empty_model_never_deletes_default(self):
        r=self.helper(RAFTAAR_AI_PROVIDER='ollama',RAFTAAR_AI_ACTION='delete',RAFTAAR_AI_MODEL='')
        self.assertNotEqual(r.returncode,0); self.assertFalse((self.w/'deleted').exists())
        r=self.native(['wait-ai','cmd ai_delete','key Return','wait-ai','print-ai'],provider='ollama',model='')
        self.assertEqual(r.returncode,0,r.stderr); self.assertFalse((self.w/'deleted').exists())

    def test_settings_model_action_lifecycle(self):
        r=self.native(['wait-ai','cmd settings','wait-ai','move 1000 500','scroll 4000',
                       'click 1120 586','wait-ai','print-ai',
                       'click 1120 586','key Escape','wait-ai',
                       'click 1120 586','key Return','wait-ai','print-ai',
                       'click 1120 586','wait-ai','print-ai'],provider='ollama',MISSING_MODEL='1')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(r.stdout.count('Ready locally: qwen2.5-coder:1.5b'),2,r.stdout)
        self.assertIn('Deleted: qwen2.5-coder:1.5b',r.stdout)
        self.assertEqual(sum(a[0]=='rm' for n,a in self.calls() if n=='ollama'),1)
        self.assertTrue((self.w/'pulled').exists())

    def test_settings_existing_model_action_deletes(self):
        r=self.native(['wait-ai','cmd settings','wait-ai','move 1000 500','scroll 4000',
                       'click 1120 586','key Return','wait-ai','print-ai'],provider='ollama')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('Deleted: qwen2.5-coder:1.5b',r.stdout)
        self.assertFalse(any('/api/pull' in ' '.join(a) for n,a in self.calls()))

    def test_native_delete_selection_changed(self):
        shot = self.w/'confirmation.ppm'
        def change():
            deadline = time.monotonic()+10
            while not shot.exists() and time.monotonic()<deadline: time.sleep(0.01)
            if shot.exists():
                (self.w/'config/raftaar/config').write_text('[git]\ncommit_ai = ollama\ncommit_model = other:model\n')
        thread=threading.Thread(target=change); thread.start()
        try:
            r=self.native(['wait-git','wait-ai','cmd ai_delete','shot '+str(shot),'wait 1500',
                           'key Return','wait-ai'],provider='ollama')
        finally: thread.join()
        self.assertEqual(r.returncode,0,r.stderr); self.assertTrue(shot.exists())
        self.assertFalse((self.w/'deleted').exists())

    def test_download_does_not_cancel_generation(self):
        r=self.native(['wait-git','wait-ai','cmd git_generate_message','wait 500','cmd ai_setup',
                       'wait-ai','print-scm'],provider='ollama',DELAY='1')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('Describe the selected changes',r.stdout)

    def install_fixture(self, bad_checksum=False, darwin_layout=False):
        archive = self.w/'ollama-darwin.tgz'
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(self.bin/'ollama', arcname='ollama' if darwin_layout else 'bin/ollama')
            if darwin_layout:
                for name in ('libggml.so', 'libggml-metal.dylib'):
                    library = self.w/name; library.write_bytes(b'fixture library')
                    tar.add(library, arcname=name)
        digest = '0'*64 if bad_checksum else hashlib.sha256(archive.read_bytes()).hexdigest()
        sums = self.w/'checksums'
        sums.write_text(digest+'  ollama-darwin.tgz\n'+digest+'  ollama-linux-amd64.tgz\n')
        # Isolate discovery so this fixture never reuses a developer's real Ollama.
        source = (ROOT/'runtime/ai/commit.sh').read_text()
        source = source.replace('case "$provider" in\n', 'find_cli() { cli=; }\ncase "$provider" in\n',1)
        script = self.w/'install-test.sh'; script.write_text(source)
        return subprocess.run(['/bin/sh',str(script)],env=dict(self.env, RAFTAAR_AI_PROVIDER='ollama',
            RAFTAAR_AI_ACTION='setup',ARCHIVE=str(archive),CHECKSUMS=str(sums)), capture_output=True,text=True,timeout=15)

    def test_install_and_recover_dead_lock(self):
        lock = self.w/'data/raftaar/ai/setup.lock'; lock.mkdir(parents=True)
        (lock/'pid').write_text('99999999\n')
        r = self.install_fixture(); self.assertEqual(r.returncode,0,r.stdout)
        self.assertTrue((self.w/'data/raftaar/ai/ollama/ready').exists())
        self.assertTrue((self.w/'data/raftaar/ai/ollama').is_symlink())

    def test_cancel_at_publication_preserves_runtime(self):
        link = self.bin/'ln'
        link.write_text('#!/bin/sh\n/bin/ln "$@" || exit $?\nkill -TERM "$PPID"\n')
        link.chmod(0o755)
        r = self.install_fixture(); self.assertEqual(r.returncode,130,r.stdout)
        published = self.w/'data/raftaar/ai/ollama'
        self.assertTrue((published/'ready').exists())
        link.unlink()
        r = self.install_fixture(); self.assertEqual(r.returncode,0,r.stdout)

    def test_install_checksum_failure(self):
        r = self.install_fixture(bad_checksum=True)
        self.assertNotEqual(r.returncode,0); self.assertIn('checksum mismatch',r.stdout)
        self.assertFalse((self.w/'data/raftaar/ai/ollama/ready').exists())

    def test_concurrent_installs_publish_complete_runtime(self):
        # Prepare fixture files once before starting both copies of the real helper.
        r = self.install_fixture()
        self.assertEqual(r.returncode,0,r.stdout)
        published = self.w/'data/raftaar/ai/ollama'
        published.unlink()
        env = dict(self.env, RAFTAAR_AI_PROVIDER='ollama', RAFTAAR_AI_ACTION='setup',
                   ARCHIVE=str(self.w/'ollama-darwin.tgz'), CHECKSUMS=str(self.w/'checksums'))
        def run():
            return subprocess.run(['/bin/sh',str(self.w/'install-test.sh')],env=env,capture_output=True,text=True,timeout=15)
        with concurrent.futures.ThreadPoolExecutor() as pool:
            results = list(pool.map(lambda _: run(), range(2)))
        for r in results: self.assertEqual(r.returncode,0,r.stdout)
        self.assertTrue(published.is_symlink())
        self.assertTrue((published/'ready').exists())
        self.assertTrue((published/'bin/ollama').exists())

    def test_native_repository_switch(self):
        other=self.w/'other'; other.mkdir()
        r=self.native(['wait-git','wait-ai','cmd git_generate_message','wait 100',
                       'open '+str(other),'wait-ai','print-scm'],DELAY='0.5')
        self.assertEqual(r.returncode,0,r.stderr); self.assertNotIn('Describe the selected changes',r.stdout)

    def test_darwin_runtime_library_layout(self):
        r=self.install_fixture(darwin_layout=True); self.assertEqual(r.returncode,0,r.stdout)
        runtime=self.w/'data/raftaar/ai/ollama/bin'
        self.assertTrue((runtime/'libggml.so').exists())
        self.assertTrue((runtime/'libggml-metal.dylib').exists())

    def test_linux_runtime_archive(self):
        uname = self.bin/'uname'
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n')
        uname.chmod(0o755)
        r = self.install_fixture(); self.assertEqual(r.returncode,0,r.stdout)
        self.assertTrue((self.w/'data/raftaar/ai/ollama/ready').exists())

    def test_settings_do_not_wait_for_detection(self):
        start=time.monotonic()
        r=self.native(['wait-git','cmd settings','print-state'],AUTH_DELAY='5')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertLess(time.monotonic()-start,2)

    def test_settings_provider_persists(self):
        r=self.native(['wait-git','wait-ai','cmd settings','move 1000 500','scroll 4000',
                       'click 874 442','wait-ai','print-ai'])
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('AI commit messages are off.',r.stdout)
        self.assertIn('commit_ai = off',(self.w/'config/raftaar/config').read_text())

    def test_external_config_change_cancels_generation(self):
        config=self.w/'config/raftaar/config'
        r=self.native(['wait-git','wait-ai','cmd git_generate_message','wait 100',
                       'open '+str(config),'key ctrl+a','type [git]','key Return',
                       'type commit_ai = off','key Return','cmd save','wait 300',
                       'wait-ai','print-scm','print-ai'],DELAY='1')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertNotIn('Describe the selected changes',r.stdout)
        self.assertIn('AI commit messages are off.',r.stdout)

    def test_native_generate(self):
        r=self.native(['wait-git','wait-ai','cmd git_history','wait-git','cmd git_generate_message','wait-ai','print-scm','print-ai'])
        self.assertEqual(r.returncode,0,r.stderr); self.assertIn('Describe the selected changes',r.stdout,r.stdout)
    def test_native_off(self):
        r=self.native(['wait-git','cmd git_generate_message','wait-ai','print-scm'],provider='off')
        self.assertEqual(r.returncode,0,r.stderr); self.assertNotIn('Describe the selected changes',r.stdout); self.assertEqual(self.calls(),[])
    def test_native_cancel(self):
        r=self.native(['wait-git','wait-ai','cmd git_generate_message','wait 150','cmd ai_cancel','wait-ai','print-scm','print-ai'],DELAY='5')
        self.assertEqual(r.returncode,0,r.stderr); self.assertIn('Cancelled',r.stdout); self.assertNotIn('Describe the selected changes',r.stdout)
    def test_native_edit_preserved(self):
        r=self.native(['wait-git','wait-ai','cmd git_history','wait-git','cmd git_generate_message','wait 100','key Return','type My draft','wait-ai','print-scm'],DELAY='0.4')
        self.assertEqual(r.returncode,0,r.stderr); self.assertIn('My draft',r.stdout); self.assertNotIn('Describe the selected changes',r.stdout)

if __name__ == '__main__': unittest.main(verbosity=2)
