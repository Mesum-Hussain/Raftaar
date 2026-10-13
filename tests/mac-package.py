#!/usr/bin/env python3
"""Exercise release failure handling without a signing key or calls to Apple."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SHIM = r'''
import json, os
from pathlib import Path
import sys
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open("events.jsonl", "a") as log:
    log.write(json.dumps([tool, *args]) + "\n")
failure = os.environ.get("FAILURE", "")
if tool == "xcrun" and args[:2] == ["notarytool", "submit"]:
    if failure == "notary-exit":
        print('{"status": "Accepted"}')
        sys.exit(1)
    if failure == "notary-json":
        print("invalid JSON")
    else:
        rejected = failure == "notary-invalid" or (failure == "dmg-notary-invalid" and args[2].endswith(".dmg"))
        print(json.dumps({"status": "Invalid" if rejected else "Accepted"}))
elif tool == "xcrun" and args[:2] == ["stapler", "staple"]:
    if failure == "staple":
        sys.exit(1)
elif tool == "xcrun" and args[:2] == ["stapler", "validate"]:
    if failure == "ticket":
        sys.exit(1)
elif tool == "spctl" and (failure == "gatekeeper" or (failure == "dmg-gatekeeper" and args[-1].endswith(".dmg"))):
    sys.exit(1)
elif tool == "build-mac.sh":
    Path("build/raftaar.app").mkdir(parents=True, exist_ok=True)
elif tool == "ditto":
    Path(args[-1]).touch()
elif tool == "hdiutil":
    Path(args[-1]).touch()
'''


def run_case(name, *, failure="", notarize="1", omit="", expected=1):
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / "tools").mkdir()
        (work / "bin").mkdir()
        (work / "build").mkdir()
        (work / "VERSION").write_text("0.17.1\n")
        (work / "notary.p8").write_text("test key\n")
        # A stale Accepted log must not allow a failed submission to pass.
        (work / "build/notary.json").write_text('{"status": "Accepted"}\n')
        shutil.copyfile(ROOT / "tools/package-mac.sh", work / "tools/package-mac.sh")
        for tool in ("codesign", "xcrun", "spctl", "ditto", "hdiutil", "build-mac.sh"):
            path = work / ("tools" if tool == "build-mac.sh" else "bin") / tool
            path.write_text(f"#!{sys.executable}\n" + SHIM)
            path.chmod(0o755)
        env = dict(os.environ, PATH=str(work / "bin") + os.pathsep + os.environ["PATH"],
                   RAFTAAR_DIST="1", RAFTAAR_NOTARIZE=notarize, RAFTAAR_SIGN_ID="test identity",
                   RAFTAAR_NOTARY_KEY=str(work / "notary.p8"), RAFTAAR_NOTARY_KEY_ID="test-id",
                   RAFTAAR_NOTARY_ISSUER="test-issuer", FAILURE=failure)
        if omit:
            env.pop(omit, None)
        result = subprocess.run(["sh", "tools/package-mac.sh"], cwd=work, env=env,
                                text=True, capture_output=True)
        events_file = work / "events.jsonl"
        events = [json.loads(line) for line in events_file.read_text().splitlines()] if events_file.exists() else []
        assert (result.returncode == 0) == (expected == 0), (name, result.stdout, result.stderr)
        if notarize != "1" or omit:
            assert not events, (name, events)
        if failure and not failure.startswith("dmg-"):
            assert not (work / "build/raftaar-0.17.1-macos-arm64.zip").exists(), (name, events)
            assert not (work / "build/raftaar-0.17.1-macos-arm64.dmg").exists(), (name, events)
        if expected == 0:
            submissions = [e for e in events if e[:3] == ["xcrun", "notarytool", "submit"]]
            assert len(submissions) == 2, events
            zip_index = next(i for i, e in enumerate(events) if e[0] == "ditto" and e[-1].endswith("macos-arm64.zip"))
            ticket_index = events.index(["xcrun", "stapler", "validate", "build/raftaar.app"])
            assert ticket_index < zip_index, events
            assert ["spctl", "--assess", "--type", "execute", "--verbose=2", "build/raftaar.app"] in events[:zip_index], events
            assert (work / "build/raftaar-0.17.1-macos-arm64.zip").exists()
            assert (work / "build/raftaar-0.17.1-macos-arm64.dmg").exists()
        print(f"ok   mac-package/{name}")


run_case("distribution-requires-notarization", notarize="0")
run_case("invalid-notarization-setting", notarize="false")
run_case("missing-key-id", omit="RAFTAAR_NOTARY_KEY_ID")
run_case("missing-issuer", omit="RAFTAAR_NOTARY_ISSUER")
run_case("submission-command-failed", failure="notary-exit")
run_case("submission-rejected", failure="notary-invalid")
run_case("malformed-response", failure="notary-json")
run_case("stapling-failed", failure="staple")
run_case("invalid-ticket", failure="ticket")
run_case("gatekeeper-rejected", failure="gatekeeper")
run_case("dmg-submission-rejected", failure="dmg-notary-invalid")
run_case("dmg-gatekeeper-rejected", failure="dmg-gatekeeper")
run_case("accepted", expected=0)
