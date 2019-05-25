from setuptools import find_packages

from skbuild import setup


with open("README.md", "r") as f:
    long_description = f.read()


setup(
    name="process-tracker",
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
            "pytest-forked",
            "scikit-build",
            "setuptools",
            "tox",
        ],
    },
    description="Track child processes.",
    include_package_data=True,
    long_description=long_description,
    long_description_content_type="text/markdown",
    package_data={
        '': ['pyproject.toml', '*.pxd'],
    },
    package_dir={'': 'src'},
    packages=find_packages("src"),
    url="https://github.com/chrahunt/process-tracker",
)
