import multiprocessing
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap

from contextlib import contextmanager
from pathlib import Path

import process_tracker


@contextmanager
def enabled_tracking():
    process_tracker.install()

    try:
        yield
    finally:
        for p in Path(process_tracker._pid_dir).glob('*'):
            p.unlink()


def noop():
    pass


def target(q, level):
    q.put(os.getpid())
    if level == 0:
        return
    p = multiprocessing.Process(target=target, args=(q, level - 1,))
    p.start()
    p.join()


def test_tests_work():
    assert True


def test_child_is_tracked():
    with enabled_tracking():
        p = multiprocessing.Process(target=noop)
        p.start()
        p.join()

        assert p.exitcode == 0

        tracked_children = process_tracker.children()

    assert len(tracked_children) == 1
    assert tracked_children[0][0] == p.pid


def test_forked_child_is_tracked():
    with enabled_tracking():
        pid = os.fork()
        if not pid:
            os._exit(0)

        tracked_children = process_tracker.children()

    assert len(tracked_children) == 1
    assert tracked_children[0][0] == pid


def test_descendants_are_tracked():
    num_procs = 5
    q = multiprocessing.Queue()

    with enabled_tracking():
        p = multiprocessing.Process(target=target, args=(q, num_procs - 1))
        p.start()
        pids = []
        for i in range(num_procs):
            pids.append(q.get())

        p.join()

        assert p.exitcode == 0

        tracked_children = process_tracker.children()

    tracked_pids = sorted(p[0] for p in tracked_children)
    assert sorted(pids) == tracked_pids


def test_immediate_child_processes_are_seen():
    with enabled_tracking():
        pids = []
        for i in range(5):
            p = multiprocessing.Process(target=noop)
            p.start()
            p.join()
            assert p.exitcode == 0, 'Process must have exited cleanly.'
            pids.append(p.pid)
        tracked_procs = process_tracker.children()

    tracked_pids = [p[0] for p in tracked_procs]
    assert sorted(pids) == sorted(tracked_pids), 'Must have tracked all children.'


def test_distinct_child_processes_are_seen():
    # Given a process run with subprocess.run
    # And tracking is turned on
    # When the list of pids is retrieved
    # Then it will include the sub process.
    with enabled_tracking():
        with tempfile.NamedTemporaryFile() as f:
            subprocess.run(
                [
                    sys.executable,
                    '-c',
                    textwrap.dedent(f'''
                    import os
                    with open('{f.name}', 'w', encoding='utf-8') as f:
                        f.write(str(os.getpid()))
                    '''),
                ]
            )
            pid = int(f.read())

        tracked_procs = process_tracker.children()

    tracked_pids = [p[0] for p in tracked_procs]
    assert len(tracked_pids) == 1
    assert tracked_pids[0] == pid


def test_forked_distinct_child_processes_are_seen():
    # Given a process run with subprocess.run
    # And tracking is turned on
    # And that process forks
    # When the list of pids is retrieved
    # Then it will include the sub processes.
    with enabled_tracking():
        with tempfile.NamedTemporaryFile() as f:
            subprocess.run(
                [
                    sys.executable,
                    '-c',
                    textwrap.dedent(f'''
                    import os
                    pid = os.fork()

                    if not pid:
                        os._exit(0)

                    with open('{f.name}', 'w', encoding='utf-8') as f:
                        f.write(str(os.getpid()) + ' ' + str(pid))
                    '''),
                ]
            )
            pids = [int(p) for p in f.read().split()]

        tracked_procs = process_tracker.children()

    assert len(pids) == 2
    tracked_pids = [p[0] for p in tracked_procs]
    assert len(tracked_pids) == 2
    assert sorted(tracked_pids) == sorted(pids)
