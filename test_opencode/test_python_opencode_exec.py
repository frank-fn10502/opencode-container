#!/usr/bin/env python3
"""Minimal check: can Python run opencode inside the existing opencode-vm runner?"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
VM_SCRIPT = PROJECT_ROOT / ".devcontainer" / "scripts" / "runtime" / "vm" / "opencode-vm.sh"
VM_NAME = "test-cpp"


def main() -> int:
    cmd = [
        "bash",
        str(VM_SCRIPT),
        "run",
        VM_NAME,
        "--",
        "--model",
        "ollama/qwen3.5:9b",
        "請回答今天的天氣",
    ]
    print(f"command: {' '.join(cmd)}", flush=True)
    process = subprocess.Popen(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )

    assert process.stdout is not None
    last_output = time.monotonic()
    while True:
        line = process.stdout.readline()
        if line:
            last_output = time.monotonic()
            print(line, end="", flush=True)
            continue

        returncode = process.poll()
        if returncode is not None:
            print(f"\nreturncode: {returncode}", flush=True)
            return returncode

        if time.monotonic() - last_output > 5:
            print("[waiting for opencode output...]", file=sys.stderr, flush=True)
            last_output = time.monotonic()

        time.sleep(0.1)


if __name__ == "__main__":
    raise SystemExit(main())
