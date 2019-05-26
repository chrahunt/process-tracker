import atexit
import logging
import os
import shutil
import tempfile

from contextlib import contextmanager, ExitStack
from importlib.resources import path
from pathlib import Path
from typing import ContextManager, List, Tuple

from ._internal import _process_tracker


__all__ = ['install', 'children']


logger = logging.getLogger(__name__)


_stack = ExitStack()
atexit.register(lambda: _stack.close())


def _replace_stack():
    global _stack
    _stack = ExitStack()


# Avoid executing exit methods of contexts in children.
os.register_at_fork(after_in_child=_replace_stack)


def _close_atexit(c: ContextManager):
    return _stack.enter_context(c)


def temporary_directory(*args, **kwargs):
    """Temporary directory only deleted by context manager exit.
    """
    d = None

    class TemporaryDirectory:
        def __enter__(self):
            nonlocal d
            d = tempfile.mkdtemp(*args, **kwargs)
            return d

        def __exit__(self, exc_type, exc_info, tb):
            shutil.rmtree(d)

    return TemporaryDirectory()


_pid_dir: str = None


def install():
    """Install hooks into main, fork, and clone for tracking children.

    Must be called before any 
    """
    global _pid_dir

    if _pid_dir:
        return

    _pid_dir = _close_atexit(temporary_directory())

    logger.debug('Directory for pid files: %s', _pid_dir)

    os.environ['SHIM_PID_DIR'] = _pid_dir
    os.environ['LD_PRELOAD'] = str(
        _close_atexit(path('process_tracker._internal', 'libpreload.so'))
    )

    logger.debug('LD_PRELOAD path: %s', os.environ['LD_PRELOAD'])

    _process_tracker.install()


def children() -> List[Tuple[int, float]]:
    """Return all known child process information.

    Some children may have exited.

    Returns:
        (pid, start time) for all known children
    """
    assert _pid_dir, 'process_tracker.install() must be called before children()'

    result = []
    for p in Path(_pid_dir).glob('*'):
        if p.name.startswith('.'):
            continue
        contents = p.read_text(encoding='utf-8').strip()
        result.append((int(p.name), float(contents)))
    return result
