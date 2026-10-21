#!/usr/bin/env python3
"""Install a verified upstream CLI without replacing the user's own binaries."""
import gzip
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request

VERSION = '0.25.10'
# Published GitHub release digests, not checksums downloaded alongside the asset.
ASSETS = {
    ('linux', 'x86_64'): ('linux-x64', '8283ddba69253c698f6e987ba0e2f9285e079c8db4d36ebe1394b5bb3a0ebdfd'),
    ('linux', 'aarch64'): ('linux-arm64', '07fbff8ae0eeb0d3e496e14fc1a30dcc730cc2c97d70e601e5357f2e51958af5'),
    ('mac', 'x86_64'): ('macos-x64', 'c7a962bdc850dccb184afdb73853754767304d725b545362352d1838c9a18d7e'),
    ('mac', 'aarch64'): ('macos-arm64', 'a6295d469669f6e901b6029ae6c129bd094df582d278c237fada413505cb9c42'),
}


def verified_binary(data, digest):
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError('Tree-sitter release checksum mismatch')
    return gzip.decompress(data)


def install(platform, arch, destination):
    asset, digest = ASSETS[(platform, arch)]
    url = f'https://github.com/tree-sitter/tree-sitter/releases/download/v{VERSION}/tree-sitter-{asset}.gz'
    request = urllib.request.Request(url, headers={'User-Agent': 'Portillo.Dots'})
    with urllib.request.urlopen(request, timeout=60) as response:
        binary = verified_binary(response.read(32 * 1024 * 1024), digest)
    destination = Path(destination)
    if destination.is_symlink():
        raise ValueError(f'Refusing to replace symlink: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(binary)
        temporary.chmod(0o755)
        version = subprocess.check_output([str(temporary), '--version'], text=True, timeout=15)
        if not version.startswith(f'tree-sitter {VERSION}'):
            raise ValueError('Unexpected Tree-sitter release version')
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        install(*sys.argv[1:])
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        sys.exit(f'Tree-sitter provisioning failed: {error}')
