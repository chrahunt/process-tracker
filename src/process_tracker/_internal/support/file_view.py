import errno
import io
import os


class FileView(io.RawIOBase):
    """View over a file region.
    """
    def __init__(self, file, start, end):
        fd = os.dup(file.fileno())
        self._file = os.fdopen(fd, 'rb', buffering=0)
        self._start = start
        self._end = end
        self._length = self._end - self._start
        self._file.seek(self._start)

    # io API
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, exc_tb):
        self.close()

    def close(self):
        self._file.close()

    @property
    def closed(self):
        return self._file.closed

    def fileno(self):
        return self._file.fileno()

    def flush(self):
        pass

    def isatty(self):
        return False

    def read(self, size=-1):
        current_pos = self._file.tell()

        # Always return empty result after end of range.
        if self._end <= current_pos:
            return b''

        # If we want the whole range or past the end, then read the rest of the range.
        if size < 0 or self._end <= current_pos + size:
            remainder = self._length - (current_pos - self._start)
            return self._file.read(remainder)

        # Otherwise, just read the file.
        return self._file.read(size)

    def readable(self):
        return not self.closed

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET or whence == 0:
            offset = self._start + offset
        elif whence == io.SEEK_CUR or whence == 1:
            current_pos = self._file.tell()
            if current_pos - self._start + offset < 0:
                raise OSError(errno.EINVAL, 'Invalid Operation')
        elif whence == io.SEEK_END or whence == 2:
            # XXX: SEEK_END doesn't work for all types of files (e.g. /proc/*),
            #  that's none of our business though.
            self._file.seek(0, io.SEEK_END)
            end = self._file.tell()
            offset = min(end, self._end)
            whence = io.SEEK_SET

        self._file.seek(offset, whence)

    def seekable(self):
        return not self.closed

    def tell(self):
        return self._file.tell() - self._start

    def writable(self):
        return False
