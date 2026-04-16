#!/usr/bin/env python3
"""Minimal check: can Python start a Docker hello-world container?"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys


def main() -> int:
    cmd = ["docker", "run", "--rm", "hello-world"]

    print(f"python: {sys.executable}", flush=True)
    print(f"docker: {shutil.which('docker')}", flush=True)
    print(f"cwd: {os.getcwd()}", flush=True)
    print(f"HOME: {os.environ.get('HOME')}", flush=True)
    print(f"DOCKER_HOST: {os.environ.get('DOCKER_HOST')}", flush=True)
    print(f"DOCKER_CONTEXT: {os.environ.get('DOCKER_CONTEXT')}", flush=True)
    print(f"command: {' '.join(cmd)}", flush=True)
    print("", flush=True)

    result = subprocess.run(
        cmd,
        text=True,
        capture_output=True,
        check=False,
    )

    print(f"returncode: {result.returncode}", flush=True)
    print("\n--- stdout ---", flush=True)
    print(result.stdout, end="", flush=True)
    print("\n--- stderr ---", flush=True)
    print(result.stderr, end="", flush=True)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
