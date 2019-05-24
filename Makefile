.PHONY: c-build debug

c-build:
	mkdir -p build
	. .tox/py37/bin/activate \
	&& cd build \
	&& cmake .. \
		-G "Unix Makefiles" \
		-DCMAKE_MODULE_PATH=$$PWD/../.venv/lib/python3.7/site-packages/skbuild/resources/cmake \
	&& make

debug:
	.venv/bin/python -m tox -- gdb -x scripts/test.gdb
