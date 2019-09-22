FROM dockcross/manylinux1-x64

RUN /opt/python/cp37-cp37m/bin/python -m pip install toml

COPY entrypoint.py /entrypoint.py

ENTRYPOINT ["/entrypoint.py"]
