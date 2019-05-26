#!/bin/sh
# Build sdist and wheel.
dist=dist
venv=.build-venv
venv_python=$venv/bin/python
venv_pip="$venv_python -m pip"

rm -rf $dist $venv
python -m venv $venv
$venv_pip install --upgrade pip
# Replace with pip build if/when available: pypa/pip#6041
$venv_pip install toml
$venv_pip install $($venv_python -c '
from shlex import quote
from toml import load

d = load("pyproject.toml")
print(" ".join(quote(r) for r in d["build-system"]["requires"]))
')
$venv_python setup.py sdist
$venv_pip wheel --wheel-dir dist dist/*.tar.gz
