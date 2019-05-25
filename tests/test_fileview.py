import errno
import io

import pytest

from process_tracker._lib._process_tracker import FileView


def _raises_on_sub_zero_seek(f):
    f.seek(0)
    with pytest.raises(OSError) as e:
        f.seek(-1, io.SEEK_CUR)

    assert e.value.errno == errno.EINVAL


def test_file_raises_on_sub_zero_seek(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        _raises_on_sub_zero_seek(f)
        view = FileView(f, 1, 3)

    _raises_on_sub_zero_seek(view)


def _file_read_after_end_returns_empty(f, start):
    f.seek(start)
    result = f.read()
    assert result == b''


def test_file_read_after_end_returns_empty(tmp_path):
    contents = b'abcdefg'
    path = tmp_path / 'hello.txt'
    path.write_bytes(contents)

    with open(path, 'rb') as f:
        _file_read_after_end_returns_empty(f, len(contents))
        view = FileView(f, 1, 3)

    _file_read_after_end_returns_empty(view, 2)


def test_file_read_reads_from_start(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        view = FileView(f, 1, 3)

    data = view.read(1)
    assert data == b'b'


def test_file_read_reads_only_byte_range(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        view = FileView(f, 1, 3)

    data = view.read()
    assert data == b'bc'


def test_file_seek_seeks_to_beginning_of_range(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        view = FileView(f, 1, 3)

    view.seek(0)
    data = view.read(1)
    view.seek(0)
    data2 = view.read(1)
    assert data == b'b'
    assert data2 == b'b'


def test_file_seek_set(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        view = FileView(f, 1, 3)

    view.seek(1)
    data = view.read(1)
    assert data == b'c'


def test_file_seek_cur(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        view = FileView(f, 1, 3)

    view.seek(1, io.SEEK_CUR)
    data = view.read(1)
    assert data == b'c'


def test_file_seek_end(tmp_path):
    path = tmp_path / 'hello.txt'
    path.write_bytes(b'abcdefg')

    with open(path, 'rb') as f:
        view = FileView(f, 1, 3)

    view.seek(0, io.SEEK_END)
    size = view.tell()
    assert size == 2
