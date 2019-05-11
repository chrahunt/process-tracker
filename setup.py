from setuptools import find_packages

from skbuild import setup


with open("README.md", "r") as f:
    long_description = f.read()


setup(
    name="track-new",
    version="0.1.0",

    author="Chris Hunt",
    author_email="chrahunt@gmail.com",
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: C",
    ],
    extras_require={
        "dev": [
            "cmake",
            "Cython",
            "ninja",
            "pytest",
            "scikit-build",
            "setuptools",
            "tox",
        ],
    },
    description="Track child processes.",
    long_description=long_description,
    long_description_content_type="text/markdown",
    package_data={
        '': ['pyproject.toml'],
    },
    packages=find_packages(),
    url="https://github.com/chrahunt/track-new",
)
