#!/usr/bin/env python3
"""Exercise downloader failures and retries through a real local HTTP server."""
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parent.parent


class Downloads(unittest.TestCase):
    def check_download(self, downloader, transient, quiet=False):
        executable = shutil.which(downloader)
        if not executable:
            self.skipTest(f"{downloader} is not installed")
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                if transient and len(requests) == 1:
                    self.send_response(503)
                    self.send_header("Retry-After", "1")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                elif transient:
                    # Quiet updates find their installed version; other cases stop at validation.
                    body = b"1.0.0\n" if quiet else b"invalid-version\n"
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                else:
                    self.send_error(404)

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                tools = home / "bin"
                tools.mkdir()
                # Make wget selectable even on systems with curl in /usr/bin.
                for name in (downloader, "uname", "sysctl", "mktemp", "rm", "tr", "grep", "cat", "sed"):
                    path = shutil.which(name)
                    if path:
                        (tools / name).symlink_to(path)
                env = dict(os.environ, HOME=str(home), PATH=str(tools),
                           RAFTAAR_RELEASES_URL=f"http://127.0.0.1:{server.server_port}")
                options = []
                if quiet:
                    target = home / "rhun.app" if sys.platform == "darwin" else home / "raftaar"
                    binary = target / "Contents" / "MacOS" / "raftaar" if sys.platform == "darwin" else target
                    binary.parent.mkdir(parents=True, exist_ok=True)
                    binary.write_text("#!/bin/sh\nprintf 'raftaar 1.0.0\\n'\n")
                    binary.chmod(0o755)
                    options = ["--update", "--target", str(target)]
                result = subprocess.run(["/bin/sh", str(ROOT / "install.sh"), *options],
                                        env=env, capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0 if quiet and transient else 1, result.stderr)
                self.assertEqual(result.stdout, "")
                if quiet:
                    self.assertNotIn("Checking latest release", result.stderr)
                else:
                    self.assertIn("Checking latest release", result.stderr)
                if transient:
                    self.assertEqual(len(requests), 2, result.stderr)
                    if quiet:
                        self.assertEqual(result.stderr, "")
                    else:
                        self.assertIn("invalid-version is not a version", result.stderr)
                else:
                    self.assertEqual(len(requests), 1, result.stderr)
                    self.assertIn("could not find the latest release", result.stderr)
                    if downloader == "curl":
                        self.assertIn("curl: (22)", result.stderr)
                self.assertFalse((home / ".local" / "bin" / "raftaar").exists())
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_curl_recovers_from_503(self):
        self.check_download("curl", True)

    def test_curl_reports_404(self):
        self.check_download("curl", False)

    def test_wget_recovers_from_503(self):
        self.check_download("wget", True)

    def test_wget_reports_404(self):
        self.check_download("wget", False)

    def test_curl_quiet_update_recovers_from_503(self):
        self.check_download("curl", True, quiet=True)

    def test_curl_quiet_update_reports_404(self):
        self.check_download("curl", False, quiet=True)

    def test_wget_quiet_update_recovers_from_503(self):
        self.check_download("wget", True, quiet=True)

    def test_wget_quiet_update_reports_404(self):
        self.check_download("wget", False, quiet=True)


if __name__ == "__main__":
    unittest.main()
