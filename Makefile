.PHONY: all

all:
	mkdir -p build
	cd build && cmake .. -G "Unix Makefiles" && make
