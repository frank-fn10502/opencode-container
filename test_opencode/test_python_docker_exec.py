#!/usr/bin/env python3
"""Minimal check: can Python run docker exec against the opencode-vm test runner?"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys


CONTAINER_NAME = "opencode-vm-yuta-test-cpp"


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    print(f"command: {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, text=True, capture_output=True, check=False)
    print(f"returncode: {result.returncode}", flush=True)
    print("--- stdout ---", flush=True)
    print(result.stdout, end="", flush=True)
    print("--- stderr ---", flush=True)
    print(result.stderr, end="", flush=True)
    print("", flush=True)
    return result


def main() -> int:
    print(f"python: {sys.executable}", flush=True)
    print(f"docker: {shutil.which('docker')}", flush=True)
    print(f"cwd: {os.getcwd()}", flush=True)
    print(f"HOME: {os.environ.get('HOME')}", flush=True)
    print(f"DOCKER_HOST: {os.environ.get('DOCKER_HOST')}", flush=True)
    print(f"DOCKER_CONTEXT: {os.environ.get('DOCKER_CONTEXT')}", flush=True)
    print("", flush=True)

    ps = run(["docker", "ps", "--format", "{{.Names}}"])
    if ps.returncode != 0:
        return ps.returncode
    if CONTAINER_NAME not in ps.stdout.splitlines():
        print(f"missing container: {CONTAINER_NAME}", file=sys.stderr, flush=True)
        return 2

    pwd = run(["docker", "exec", CONTAINER_NAME, "pwd"])
    if pwd.returncode != 0:
        return pwd.returncode

    version = run(["docker", "exec", CONTAINER_NAME, "opencode", "--version"])
    return version.returncode


if __name__ == "__main__":
    raise SystemExit(main())
