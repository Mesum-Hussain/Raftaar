#!/usr/bin/env python3
"""Extract only the four build tools from the checksum-verified LLVM archive."""
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

archive, destination, package = sys.argv[1:]
bin_dir = Path(destination) / 'bin'
bin_dir.mkdir(parents=True, exist_ok=True)
needed = {f'{package}/bin/{name}': bin_dir / name for name in
          ['llvm-mc.exe', 'llvm-dlltool.exe', 'llvm-rc.exe', 'lld-link.exe']}
decoder = None
try:
    if archive.endswith('.zst'):
        # Upstream uses a 1 GiB history window. A pipe avoids unpacking the entire tar to disk.
        decoder = subprocess.Popen(['zstd', '--long=30', '-dc', archive], stdout=subprocess.PIPE)
        source = tarfile.open(fileobj=decoder.stdout, mode='r|')
    else:
        source = tarfile.open(archive, mode='r|xz')
    with source:
        for member in source:
            target = needed.get(member.name)
            if target is None:
                continue
            if not member.isfile():
                raise RuntimeError(f'Expected a regular file: {member.name}')
            with tempfile.NamedTemporaryFile(dir=bin_dir, delete=False) as outgoing:
                partial = Path(outgoing.name)
                try:
                    with source.extractfile(member) as incoming:
                        shutil.copyfileobj(incoming, outgoing)
                except BaseException:
                    outgoing.close()
                    partial.unlink()
                    raise
            partial.replace(target)
            del needed[member.name]
            if not needed:
                break
    if needed:
        raise RuntimeError(f'LLVM archive is missing: {", ".join(needed)}')
finally:
    if decoder is not None:
        if decoder.poll() is None:
            decoder.terminate()
        decoder.wait()
        decoder.stdout.close()
