#!/opt/python/cp37-cp37m/bin/python
import glob
import os
import subprocess
import sys
from pathlib import Path
from shlex import quote
from typing import Dict, List, Optional

from toml import load


def latest_file(pattern) -> Optional[str]:
    files = glob.glob(pattern)
    if not files:
        return
    files.sort(key=lambda p: os.stat(p).st_mtime)
    return files[-1]


class Python:
    def __init__(self, exe):
        self._exe = exe

    def pip(self, *args, **kwargs):
        return self.run("-m", "pip", *args, **kwargs)

    def run(self, *args, **kwargs):
        allow_errors = kwargs.pop("allow_errors", False)
        result = subprocess.run([self._exe, *args], **kwargs)
        if not allow_errors:
            result.check_returncode()
        return result


def get_build_requires(data: Dict):
    return data.get("build-system", {}).get("requires", [])


def build_sdist(python):
    # XXX: Replace with `pip build` if/when available (see pypa/pip#6041)
    if os.path.exists("pyproject.toml"):
        data = load("pyproject.toml")
        build_requires = get_build_requires(data)
        if build_requires:
            python.pip("install", *build_requires)

    python.run("setup.py", "sdist")


python_locations = {
    "cp27": "cp27-cp27m",
    "cp34": "cp34-cp34m",
    "cp35": "cp35-cp35m",
    "cp36": "cp36-cp36m",
    "cp37": "cp37-cp37m",
    "cp38": "cp38-cp38m",
}


def set_output(name, value):
    print(f"::set-output name={name}::{value}")


def main(args: List[str]) -> int:
    if len(args) < 2:
        print("At least 1 argument is required", file=sys.stderr)
        return 1

    python_version = args[1]
    try:
        python_subdir = python_locations[python_version]
    except KeyError:
        print(
            f"Python version {python_version!r} not recognized",
            file=sys.stderr,
        )
        return 1

    python_path = f"/opt/python/{python_subdir}/bin/python"
    python = Python(python_path)

    python.pip("install", "--upgrade", "pip")

    sdist_path = latest_file("dist/*.tar.gz")
    if sdist_path is None:
        build_sdist(python)
        sdist_path = latest_file("dist/*.tar.gz")

    python.pip("wheel", "--wheel-dir", "dist/", sdist_path)
    wheel_path = latest_file("dist/*-linux_x86_64.whl")
    result = subprocess.run(["auditwheel", "repair", "--wheel-dir", "dist/", wheel_path])
    result.check_returncode()
    os.unlink(wheel_path)
    wheel_path = latest_file("dist/*.whl")
    set_output("wheel-path", wheel_path)
    set_output("sdist-path", sdist_path)


if __name__ == "__main__":
    os.chdir("/github/workspace")
    sys.exit(main(sys.argv))
