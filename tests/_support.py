"""Shared test support: portable temporary directories and platform gates.

Kept tiny on purpose so the suite does not depend on pytest plugins or on any
tooling that exists only on the author's machine.
"""
import os
import shutil
import tempfile

# The author's sandbox pre-creates /tmp/opencode; CI runners and macOS do not.
# Use it when it exists and is writable, otherwise fall back to the system temp.
_PREFERRED = '/tmp/opencode'


def tempdir():
    """A TemporaryDirectory that works on any host."""
    if os.path.isdir(_PREFERRED) and os.access(_PREFERRED, os.W_OK):
        return tempfile.TemporaryDirectory(dir=_PREFERRED)
    return tempfile.TemporaryDirectory()


def have(name):
    return shutil.which(name)


def require(name, reason):
    """Return True when the tool exists, otherwise skip the test."""
    return shutil.which(name) is not None or reason
