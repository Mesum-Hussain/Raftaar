#!/usr/bin/env python3
"""Run the installer's JXA with isolated Launch Services stubs, never changing user defaults."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
if sys.platform != 'darwin':
    print('skip mac-defaults: macOS JXA only')
    raise SystemExit(0)

source = (ROOT / 'install.sh').read_text().split("<<'JXA'\n", 1)[1].split('\nJXA\n', 1)[0]
harness = r'''
function run() {
    ObjC.import('Foundation');
    ObjC.import('CoreServices');
    var nativeObjC = ObjC, nativeBridge = $;
    var source = SOURCE;
    var types = {
        txt: 'public.plain-text', text: 'public.plain-text', md: 'net.daringfireball.markdown',
        js: 'com.netscape.javascript-source', conf: 'dyn.config',
        html: 'public.html', htm: 'public.html', xhtml: 'public.xhtml',
        shtml: 'test.html-subtype', svg: 'public.svg-image', url: 'public.url'
    };
    var parents = {
        'public.html': ['public.text'], 'public.xhtml': ['public.text'],
        'test.html-subtype': ['public.html', 'public.text'],
        'public.svg-image': ['public.image', 'public.text']
    };
    var scenarios = [
        {name: 'text-and-browser-types', extensions: 'txt text md html htm xhtml shtml svg url js conf'},
        {name: 'only-browser-and-images', extensions: 'html htm xhtml shtml svg url'},
        {name: 'native-types', extensions: 'txt md html htm xhtml svg js conf', native: true},
        {name: 'failure', extensions: 'txt', fail: true},
        {name: 'wrong-bundle', extensions: 'txt', bundle: 'other.app'}
    ];
    return JSON.stringify(scenarios.map(function(test) {
        var calls = [], handlers = {}, error = null;
        var ObjC = {import: function() {},
            unwrap: function(value) {return test.native && typeof value !== 'string' ? nativeObjC.unwrap(value) : value;},
            castRefToObject: function(value) {return test.native && typeof value !== 'string' ? nativeObjC.castRefToObject(value) : value;}};
        var $ = function(value) {return test.native ? nativeBridge(value) : value;};
        $.NSBundle = {bundleWithPath: function() {return {bundleIdentifier: test.bundle || 'com.r13.raftaar'};}};
        $.kLSRolesAll = 0xffffffff;
        $.kLSRolesEditor = 4;
        $.UTTypeCreatePreferredIdentifierForTag = test.native ? nativeBridge.UTTypeCreatePreferredIdentifierForTag :
            function(tag, extension) {return types[extension];};
        $.UTTypeConformsTo = test.native ? nativeBridge.UTTypeConformsTo : function(type, parent) {
            return type === parent || (parents[type] || []).indexOf(parent) !== -1;
        };
        $.LSSetDefaultRoleHandlerForContentType = function(type, role, bundle) {
            var name = test.native ? nativeObjC.unwrap(nativeObjC.castRefToObject(type)) : type;
            calls.push({type: name, role: role, bundle: bundle});
            if (test.fail) return -50;
            handlers[name] = bundle;
            return 0;
        };
        $.LSCopyDefaultRoleHandlerForContentType = function(type) {
            var name = test.native ? nativeObjC.unwrap(nativeObjC.castRefToObject(type)) : type;
            return handlers[name];
        };
        var argumentsForScript = ['/test/rhun.app', test.extensions];
        var execute = Function('ObjC', '$', 'argumentsForScript', source + '\nreturn run(argumentsForScript);');
        try {execute(ObjC, $, argumentsForScript);}
        catch (failure) {error = String(failure);}
        return {name: test.name, calls: calls, error: error};
    }));
}
'''.replace('SOURCE', json.dumps(source))

with tempfile.TemporaryDirectory(prefix='raftaar-mac-defaults-') as directory:
    path = Path(directory) / 'check.js'
    path.write_text(harness)
    result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', str(path)],
                            text=True, capture_output=True, check=True, timeout=15)
    cases = {case['name']: case for case in json.loads(result.stdout)}

case = cases['text-and-browser-types']
assert case['error'] is None, case
assert [call['type'] for call in case['calls']] == [
    'public.plain-text', 'net.daringfireball.markdown',
    'com.netscape.javascript-source', 'dyn.config'], case
assert all(call['bundle'] == 'com.r13.raftaar' for call in case['calls']), case
case = cases['only-browser-and-images']
assert not case['calls'] and case['error'] is None, case
case = cases['native-types']
assert case['error'] is None and len(case['calls']) == 4, case
assert not {'public.html', 'public.xhtml', 'public.svg-image'} & {call['type'] for call in case['calls']}, case
case = cases['failure']
assert len(case['calls']) == 1 and 'Could not change defaults for: txt' in case['error'], case
case = cases['wrong-bundle']
assert not case['calls'] and 'The installed raftaar app was not found' in case['error'], case
print('ok   associations/mac-text-defaults-preserve-browser-and-image-handlers')
