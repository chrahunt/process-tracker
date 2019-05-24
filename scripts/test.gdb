file python
b main
commands
  silent
  b __libc_fork
  c&
end
set detach-on-fork off
set non-stop on
set mi-async on
set pagination off
r -m pytest tests -s
