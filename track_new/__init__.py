import atexit
import os
import tempfile

from contextlib import ExitStack
from importlib.resources import path
from pathlib import Path
from typing import ContextManager, List, Tuple


__all__ = ['install', 'children']


_stack = ExitStack()
atexit.register(lambda: _stack.close())


def _replace_stack():
    global _stack
    _stack = ExitStack()


os.register_at_fork(after_in_child=_replace_stack)


def _close_atexit(c: ContextManager):
    return _stack.enter_context(c)


_pid_dir = None


def install():
    """Install hooks into main, fork, and clone for tracking children.
    """
    global _pid_dir
    if _pid_dir:
        return

    _pid_dir = _close_atexit(tempfile.TemporaryDirectory())
    os.environ['SHIM_PID_DIR'] = _pid_dir
    os.environ['LD_PRELOAD'] = _close_atexit(path('track_new.lib', 'libpreload.so'))


def children() -> List[Tuple[int, float]]:
    """Return all known child process information.

    Some children may have exited.

    Returns:
        pid and start time of all known children
    """
    result = []
    for p in Path(_pid_dir).glob('*'):
        contents = p.read_text(encoding='utf-8').strip()
        result.append((int(p.name), float(contents)))
    return result
