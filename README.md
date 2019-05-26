# process-tracker

Process tracker enables tracking creation of child processes.

Usage:

```python
import process_tracker; process_tracker.install()

import os

pid1 = os.fork()
pid2 = os.fork()
pid3 = os.fork()

if pid1 and pid2 and pid3:
    print(process_tracker.children())
```

Prints a list of tuples with `(pid, create_time)` for each process.

`create_time` can be used to confirm that the current process (if any) with
the given pid is the same as the original. For example:

```python
import process_tracker
import psutil


def get_create_time(ctime):
    boot_time = psutil.boot_time()
    clock_ticks = os.sysconf("SC_CLK_TCK")
    return boot_time + (ctime / clock_ticks)


processes = []
for pid, create_time in process_tracker.children():
    try:
        p = psutil.Process(pid=pid)
    except psutil.NoSuchProcess:
        continue
    if p.create_time() == get_create_time(create_time):
        processes.append(p)

# processes now has the list of active child processes
# psutil itself does a check before sensitive operations that the
# active process create time is the same as when the Process object
# was initialized.
for p in processes:
    p.terminate()
```

# Limitations

1. Only tracks children spawned from dynamically-linked executables.
1. Relies on `LD_PRELOAD` so will not work for setuid/setgid executables.

# Development

## Basic

1. `python -m venv .venv`
1. `.venv/bin/python -m pip install tox`
1. Make changes
1. `.venv/bin/python -m tox`

## Debugging C build

Avoids overhead of making sdist

1. As above
1. `make c-build`

## Debugging issues from sub-process

gdb debugging of sub-processes.

1. As above
1. `make debug`

## Debugging tests without rebuild

1. As above
1. `.venv/bin/python -m pip install . .[dev]`

Then

* `pip install . && pytest` when rebuild is needed
* `pytest` when only tests changed
