#!/usr/bin/env python3
"""Verify portable downloads before transfer or execution; cache release digests."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import sys
import tarfile
import tempfile
from urllib.request import Request, urlopen
import zipfile

GITHUB = {
    'nvim.tar.gz': ('neovim/neovim', lambda arch: re.escape(f'nvim-linux-{"x86_64" if arch == "x86_64" else "arm64"}.tar.gz')),
    'rg.tar.gz': ('BurntSushi/ripgrep', lambda arch: rf'ripgrep-.*-{arch}-unknown-linux-musl\.tar\.gz'),
    'fd.tar.gz': ('sharkdp/fd', lambda arch: rf'fd-.*-{arch}-unknown-linux-musl\.tar\.gz'),
    'fzf.tar.gz': ('junegunn/fzf', lambda arch: rf'fzf-.*-linux_{"amd64" if arch == "x86_64" else "arm64"}\.tar\.gz'),
    'lazygit.tar.gz': ('jesseduffield/lazygit', lambda arch: rf'lazygit_.*_linux_{"x86_64" if arch == "x86_64" else "arm64"}\.tar\.gz'),
    'stylua.zip': ('JohnnyMorganz/StyLua', lambda arch: re.escape(f'stylua-linux-{arch}.zip')),
}
FILES = set(GITHUB) | {'node.tar.xz', 'zig.tar.xz'}


def fetch(url, as_json=True):
    request = Request(url, headers={'User-Agent': 'Portillo.Dots-integrity'})
    with urlopen(request, timeout=30) as response:
        data = response.read()
    return json.loads(data) if as_json else data.decode()


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as archive:
        for chunk in iter(lambda: archive.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def safe_member(name, link=None):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Unsafe path in binary archive')
    if link:
        target = posixpath.normpath(posixpath.join(str(path.parent), link))
        if link.startswith('/') or target == '..' or target.startswith('../'):
            raise ValueError('Unsafe link in binary archive')


def validate_archive(path):
    if path.suffix == '.zip':
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                safe_member(member.filename)
                # Do not allow symlinks in ZIP tools (unzip follows them later).
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Symlink in ZIP archive')
    else:
        with tarfile.open(path) as archive:
            for member in archive:
                if member.isdev() or member.isfifo():
                    raise ValueError('Special file in binary archive')
                safe_member(member.name, member.linkname if member.issym() else None)
                if member.islnk():
                    safe_member(member.linkname)


def release_digests(cache, arch):
    pins = {}
    for filename, (repo, pattern) in GITHUB.items():
        release = fetch(f'https://api.github.com/repos/{repo}/releases/latest')
        assets = [a for a in release['assets'] if re.fullmatch(pattern(arch), a['name'])]
        if len(assets) != 1:
            raise ValueError(f'No unique upstream asset for {filename}/{arch}')
        digest = assets[0].get('digest') or ''
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
            raise ValueError(f'Upstream has no SHA-256 digest for {filename}; refusing unverified execution')
        pins[filename] = {'sha256': digest[7:], 'version': release['tag_name']}
    # Node publishes SHA-256 sums per version; identify the archive's release
    # without extracting or executing any of its contents.
    with tarfile.open(cache / 'node.tar.xz', mode='r|xz') as archive:
        member = archive.next()
        match = re.match(r'^node-(v[0-9]+\.[0-9]+\.[0-9]+)-linux-(x64|arm64)(?:/|$)', member.name if member else '')
    if not match or match[2] != ('x64' if arch == 'x86_64' else 'arm64'):
        raise ValueError('Node archive has an unexpected release/platform')
    version = match[1]
    asset = f'node-{version}-linux-{match[2]}.tar.xz'
    sums = fetch(f'https://nodejs.org/dist/{version}/SHASUMS256.txt', as_json=False)
    checksums = dict((line.split()[1], line.split()[0]) for line in sums.splitlines() if len(line.split()) == 2)
    pins['node.tar.xz'] = {'sha256': checksums[asset], 'version': version}
    zig = fetch('https://ziglang.org/download/index.json')['0.14.0'][f'{arch}-linux']
    pins['zig.tar.xz'] = {'sha256': zig['shasum'], 'version': '0.14.0'}
    return pins


def verify(cache, arch):
    metadata = cache / '.integrity.json'
    if metadata.is_symlink():
        raise ValueError('Refusing symlinked integrity metadata')
    for filename in FILES:
        path = cache / filename
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Missing portable download: {filename}')
    pins = json.loads(metadata.read_text()) if metadata.exists() else release_digests(cache, arch)
    if set(pins) != FILES:
        raise ValueError('Incomplete cached release metadata')
    for filename in sorted(FILES):
        expected = pins[filename]['sha256']
        if not re.fullmatch(r'[0-9a-f]{64}', expected) or sha256(cache / filename) != expected:
            raise ValueError(f'Checksum mismatch: {filename}; retry with --refresh-bins')
        if not metadata.exists():
            validate_archive(cache / filename)
        print(f'Verified SHA-256: {filename}')
    if not metadata.exists():
        fd, name = tempfile.mkstemp(prefix='.integrity-', dir=cache)
        try:
            with os.fdopen(fd, 'w') as output:
                json.dump(pins, output, indent=2)
            os.replace(name, metadata)
        finally:
            if os.path.exists(name):
                os.unlink(name)


if __name__ == '__main__':
    try:
        if sys.argv[2] not in ('x86_64', 'aarch64'):
            raise ValueError('Unsupported platform')
        verify(Path(sys.argv[1]), sys.argv[2])
    except (OSError, ValueError, KeyError, tarfile.TarError, zipfile.BadZipFile) as error:
        sys.exit(f'Binary integrity verification failed: {error}')
