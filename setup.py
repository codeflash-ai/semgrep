# type: ignore
# Used for pre-commit since it expects a setup.py in repo root
# for actual setup.py see cli/setup.py
from __future__ import annotations

from setuptools import setup

setup(
    name="semgrep_pre_commit_package",
    version="1.12.0",
    install_requires=["semgrep==1.12.0"],
    packages=[],
)
