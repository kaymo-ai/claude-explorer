#!/usr/bin/env python3
"""Setup script for claude-explorer."""

from setuptools import setup
from pathlib import Path

# Read README for long description
readme = Path(__file__).parent / "README.md"
long_description = readme.read_text() if readme.exists() else ""

setup(
    name="claude-explorer",
    version="1.1.0",
    author="Marcus Foster",
    author_email="marcus@kaymo.ai",
    description="Interactive viewer for Claude Code session data",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/kaymo-ai/claude-explorer",
    license="MIT",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Documentation",
        "Topic :: Utilities",
    ],
    python_requires=">=3.8",
    py_modules=[],
    scripts=["claude-explorer"],
    entry_points={
        "console_scripts": [
            "claude-explorer=claude_explorer:main",
        ],
    },
    keywords="claude, anthropic, cli, history, explorer, dashboard",
    project_urls={
        "Bug Reports": "https://github.com/kaymo-ai/claude-explorer/issues",
        "Source": "https://github.com/kaymo-ai/claude-explorer",
    },
)
