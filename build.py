from distutils.core import Extension

from Cython.Build import cythonize


extensions = [
    Extension('preload', ['track_new/_src/preload.c']),
]


def build(setup_kwargs):
    setup_kwargs.update({
        'ext_modules': extensions,
    })
