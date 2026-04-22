#!/usr/bin/env python3
"""Periodically ask opencode, running in opencode-vm, to inspect C++ files."""

from __future__ import annotations

import argparse
import datetime as dt
import signal
import subprocess
import sys
import time
from pathlib import Path
from zoneinfo import ZoneInfo


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
VM_SCRIPT = PROJECT_ROOT / ".devcontainer" / "scripts" / "runtime" / "vm" / "opencode-vm.sh"
SETUP_VM_SCRIPT = SCRIPT_DIR / "setup_opencode_vm_runner.sh"
DEFAULT_VM_NAME = "test-cpp"
LOG_DIR = SCRIPT_DIR / "logs"
TAIWAN_TZ = ZoneInfo("Asia/Taipei")

PROMPT = """請檢查 {workspace_dir} 這個專案中的 C++ 檔案。

請自行在 {workspace_dir} 中搜尋 .cpp/.cc/.cxx/.hpp/.hh/.hxx/.h 檔案，不要依賴外部提供的 inventory。
請用繁體中文回答，內容包含：
1. 專案中有哪些 .cpp/.cc/.cxx/.hpp/.hh/.hxx/.h 檔案。
2. 每個檔案的主要功能是什麼。
3. 每個檔案最後更新時間。

所有最後更新時間都必須使用 UTC+8，也就是台灣時間（Asia/Taipei）。
若需要查詢檔案時間，請在容器內用 Asia/Taipei 時區取得，不要使用其他時區。
輸出請用 Markdown 表格，欄位至少包含：檔案、最後更新時間、功能。

完成後請把最終 Markdown 內容寫入 VM 內：
{vm_result_path}

不要寫入或讀取 /tmp、/var/tmp、host 路徑或 {workspace_dir} 以外的任何路徑。
請在標準輸出中簡短回報已完成，並附上輸出檔案路徑。
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Every N seconds, run opencode inside an opencode-vm runner "
            "and append the C++ inspection response to test_opencode/logs."
        )
    )
    parser.add_argument(
        "--vm-name",
        default=DEFAULT_VM_NAME,
        help=f"opencode-vm name to use. Default: {DEFAULT_VM_NAME}.",
    )
    parser.add_argument(
        "--port-base",
        type=int,
        default=2600,
        help="Port base for the test VM. Default: 2600.",
    )
    parser.add_argument(
        "--skip-setup",
        action="store_true",
        help="Do not recreate/import/start the test VM before running opencode.",
    )
    parser.add_argument(
        "--workspace-dir",
        default="/workspace",
        help="VM project directory to inspect. Default: /workspace.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=30.0,
        help="Seconds to wait between opencode calls. Default: 30.",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=1,
        help="Number of times to call opencode. Default: 1. Use 0 to run until interrupted.",
    )
    parser.add_argument(
        "--model",
        default="ollama/qwen3.5:9b",
        help="opencode model, in provider/model format. Default: ollama/qwen3.5:9b.",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=None,
        help=(
            "Optional explicit Markdown output path. "
            "If omitted, the script writes to test_opencode/logs/result_<time>.md."
        ),
    )
    return parser.parse_args()


def write_report(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")


def now_in_taiwan() -> dt.datetime:
    return dt.datetime.now(TAIWAN_TZ)


def make_result_file(run_started_at: dt.datetime, override: Path | None) -> Path:
    if override is not None:
        return override if override.is_absolute() else (PROJECT_ROOT / override)
    filename = f"result_{run_started_at.strftime('%Y%m%dT%H%M%S%z')}.md"
    return LOG_DIR / filename


def vm_result_path_for(local_path: Path, workspace_dir: str) -> str:
    return f"{workspace_dir.rstrip('/')}/.opencode-test-results/{local_path.name}"


def run_command(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=PROJECT_ROOT,
        text=True,
        capture_output=True,
        stdin=subprocess.DEVNULL,
        check=False,
    )


def run_command_streaming(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    process = subprocess.Popen(
        cmd,
        cwd=PROJECT_ROOT,
        text=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )

    stdout_parts: list[str] = []

    assert process.stdout is not None
    for line in process.stdout:
        stdout_parts.append(line)
        print(line, end="", flush=True)

    return_code = process.wait()
    return subprocess.CompletedProcess(
        cmd,
        return_code,
        stdout="".join(stdout_parts),
        stderr="",
    )


def build_prompt(workspace_dir: str, vm_result_path: str) -> str:
    return PROMPT.format(workspace_dir=workspace_dir, vm_result_path=vm_result_path)


def ensure_runner(vm_name: str, port_base: int, skip_setup: bool) -> str:
    if skip_setup:
        print(f"using existing opencode-vm runner: {vm_name}", flush=True)
        status = run_command(["bash", str(VM_SCRIPT), "exec", vm_name, "--", "true"])
    else:
        print(f"preparing opencode-vm runner: {vm_name}", flush=True)
        status = run_command_streaming(
            [
                "bash",
                str(SETUP_VM_SCRIPT),
                "--name",
                vm_name,
                "--port-base",
                str(port_base),
            ],
        )

    if status.returncode != 0:
        raise RuntimeError(
            "Unable to prepare the opencode-vm runner.\n"
            f"Command: {' '.join(status.args)}\n"
            f"stderr:\n{status.stderr.strip()}"
        )

    return f"opencode-vm-yuta-{vm_name}"


def read_vm_file(vm_name: str, vm_path: str) -> str:
    result = run_command(["bash", str(VM_SCRIPT), "exec", vm_name, "--", "cat", vm_path])
    if result.returncode != 0:
        raise RuntimeError(
            "Unable to read the result file from opencode-vm.\n"
            f"Path: {vm_path}\n"
            f"stderr:\n{result.stderr.strip()}"
        )
    return result.stdout


def cleanup_opencode_run(vm_name: str) -> None:
    run_command(
        [
            "bash",
            str(VM_SCRIPT),
            "exec",
            vm_name,
            "--",
            "sh",
            "-lc",
            (
                "pids=$(ps -eo pid=,cmd= | awk '/[o]pencode run/ {print $1}'); "
                "if [ -n \"$pids\" ]; then kill -TERM $pids 2>/dev/null || true; fi; "
                "sleep 1; "
                "pids=$(ps -eo pid=,cmd= | awk '/[o]pencode run/ {print $1}'); "
                "if [ -n \"$pids\" ]; then kill -KILL $pids 2>/dev/null || true; fi"
            ),
        ],
    )


def run_opencode(
    vm_name: str,
    model: str,
    result_path: Path,
    workspace_dir: str,
) -> subprocess.CompletedProcess[str]:
    vm_result_path = vm_result_path_for(result_path, workspace_dir)
    prompt = build_prompt(workspace_dir, vm_result_path)
    cmd = [
        "bash",
        str(VM_SCRIPT),
        "run",
        vm_name,
        "--",
        "--model",
        model,
        "--agent",
        "build",
        prompt,
    ]
    print("running opencode inside opencode-vm; streaming output below...", flush=True)
    return run_command_streaming(cmd)


def main() -> int:
    args = parse_args()
    stop_requested = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    if not VM_SCRIPT.exists():
        print(f"opencode-vm script not found: {VM_SCRIPT}", file=sys.stderr)
        return 2
    if not args.skip_setup and not SETUP_VM_SCRIPT.exists():
        print(f"VM setup script not found: {SETUP_VM_SCRIPT}", file=sys.stderr)
        return 2

    try:
        runner_id = ensure_runner(args.vm_name, args.port_base, args.skip_setup)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    cleanup_opencode_run(args.vm_name)

    run_count = 0
    while not stop_requested:
        run_count += 1
        started_at = now_in_taiwan()
        result_path = make_result_file(started_at, args.log_file)
        header = (
            f"\n\n## Run {run_count} - "
            f"{started_at.isoformat(timespec='seconds')}\n\n"
        )
        print(f"[{started_at.isoformat(timespec='seconds')}] calling opencode...", flush=True)

        try:
            print(
                f"result file: {result_path.relative_to(PROJECT_ROOT)}",
                flush=True,
            )
            vm_result_path = vm_result_path_for(result_path, args.workspace_dir)
            print(f"VM result file: {vm_result_path}", flush=True)
            result = run_opencode(
                args.vm_name,
                args.model,
                result_path,
                args.workspace_dir,
            )
            finished_at = now_in_taiwan()
            body = result.stdout.strip()
            try:
                vm_report = read_vm_file(args.vm_name, vm_result_path)
            except RuntimeError:
                vm_report = ""

            if vm_report.strip():
                write_report(result_path, vm_report)
            elif not result_path.exists():
                fallback_lines = [
                    header,
                    f"- Runner: `{runner_id}`\n",
                    f"- Exit code: `{result.returncode}`\n",
                    f"- Finished: `{finished_at.isoformat(timespec='seconds')}`\n\n",
                    (body or "(opencode did not write anything to stdout)"),
                    "\n",
                ]
                if result.returncode != 0 and result.stderr.strip():
                    fallback_lines.extend(
                        [
                            "\n### stderr\n\n```text\n",
                            result.stderr.strip(),
                            "\n```\n",
                        ]
                    )
                write_report(result_path, "".join(fallback_lines))
            print(f"wrote opencode response to {result_path}", flush=True)
        except RuntimeError as exc:
            write_report(result_path, header + f"- Exit code: `runner-error`\n\n{exc}\n")
            print(str(exc), file=sys.stderr)
            return 1

        if args.iterations and run_count >= args.iterations:
            break

        deadline = time.monotonic() + args.interval
        while not stop_requested and time.monotonic() < deadline:
            time.sleep(min(0.5, deadline - time.monotonic()))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
