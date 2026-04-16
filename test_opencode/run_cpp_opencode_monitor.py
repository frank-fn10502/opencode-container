#!/usr/bin/env python3
"""Periodically ask opencode, running in Docker, to inspect C++ files."""

from __future__ import annotations

import argparse
import datetime as dt
import queue
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from zoneinfo import ZoneInfo


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
COMPOSE_FILE = PROJECT_ROOT / ".devcontainer" / "compose.yaml"
RUNNER_SERVICE = "opencode-cpp-runner"
RUNNER_CONTAINER = "devcontainer-opencode-cpp-runner-1"
LOG_DIR = SCRIPT_DIR / "logs"
TAIWAN_TZ = ZoneInfo("Asia/Taipei")

PROMPT = """請檢查 /workspace 這個專案中的 C++ 檔案。

請自行在 /workspace 中搜尋 .cpp/.cc/.cxx/.hpp/.hh/.hxx/.h 檔案，不要依賴外部提供的 inventory。
請用繁體中文回答，內容包含：
1. 專案中有哪些 .cpp/.cc/.cxx/.hpp/.hh/.hxx/.h 檔案。
2. 每個檔案的主要功能是什麼。
3. 每個檔案最後更新時間。

所有最後更新時間都必須使用 UTC+8，也就是台灣時間（Asia/Taipei）。
若需要查詢檔案時間，請在容器內用 Asia/Taipei 時區取得，不要使用其他時區。
輸出請用 Markdown 表格，欄位至少包含：檔案、最後更新時間、功能。

完成後請把最終 Markdown 內容寫入：
{result_path}

請在標準輸出中簡短回報已完成，並附上輸出檔案路徑。
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Every N seconds, run opencode inside the Docker compose runner "
            "and append the C++ inspection response to test_opencode/logs."
        )
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
        "--timeout",
        type=float,
        default=240.0,
        help="Seconds to wait for each opencode call before timing out. Default: 240.",
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


def docker_compose_base() -> list[str]:
    return ["docker", "compose", "-f", str(COMPOSE_FILE)]


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


def container_path_for(local_path: Path) -> str:
    return f"/workspace/{local_path.relative_to(PROJECT_ROOT)}"


def run_command(cmd: list[str], timeout: float | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=PROJECT_ROOT,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def run_command_streaming(
    cmd: list[str], timeout: float | None = None
) -> subprocess.CompletedProcess[str]:
    process = subprocess.Popen(
        cmd,
        cwd=PROJECT_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output_queue: queue.Queue[tuple[str, str | None]] = queue.Queue()

    def pump(name: str, stream: object) -> None:
        try:
            for line in stream:  # type: ignore[union-attr]
                output_queue.put((name, line))
        finally:
            output_queue.put((name, None))

    stdout_thread = threading.Thread(
        target=pump, args=("stdout", process.stdout), daemon=True
    )
    stderr_thread = threading.Thread(
        target=pump, args=("stderr", process.stderr), daemon=True
    )
    stdout_thread.start()
    stderr_thread.start()

    stdout_parts: list[str] = []
    stderr_parts: list[str] = []
    closed_streams: set[str] = set()
    deadline = time.monotonic() + timeout if timeout is not None else None

    while len(closed_streams) < 2:
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                process.kill()
                stdout_thread.join(timeout=1)
                stderr_thread.join(timeout=1)
                raise subprocess.TimeoutExpired(
                    cmd, timeout, output="".join(stdout_parts), stderr="".join(stderr_parts)
                )
            queue_timeout = min(0.2, remaining)
        else:
            queue_timeout = 0.2

        try:
            stream_name, line = output_queue.get(timeout=queue_timeout)
        except queue.Empty:
            continue

        if line is None:
            closed_streams.add(stream_name)
            continue

        if stream_name == "stdout":
            stdout_parts.append(line)
            print(line, end="", flush=True)
        else:
            stderr_parts.append(line)
            print(line, end="", file=sys.stderr, flush=True)

    return_code = process.wait()
    return subprocess.CompletedProcess(
        cmd,
        return_code,
        stdout="".join(stdout_parts),
        stderr="".join(stderr_parts),
    )


def build_prompt(result_path: Path) -> str:
    return PROMPT.format(result_path=container_path_for(result_path))


def compose_ps_runner(all_containers: bool) -> str:
    cmd = [*docker_compose_base(), "ps", "-q"]
    if all_containers:
        cmd.append("-a")
    cmd.append(RUNNER_SERVICE)
    result = run_command(cmd)
    if result.returncode != 0:
        raise RuntimeError(
            "Unable to inspect the opencode runner container.\n"
            f"Command: {' '.join(cmd)}\n"
            f"stderr:\n{result.stderr.strip()}"
        )
    return result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""


def is_container_running(container_id: str) -> bool:
    result = run_command(["docker", "inspect", "-f", "{{.State.Running}}", container_id])
    if result.returncode != 0:
        raise RuntimeError(
            "Unable to inspect the existing opencode runner.\n"
            f"Container: {container_id}\n"
            f"stderr:\n{result.stderr.strip()}"
        )
    return result.stdout.strip() == "true"


def ensure_runner() -> str:
    print("checking opencode runner...", flush=True)
    existing = run_command(["docker", "inspect", "-f", "{{.State.Running}}", RUNNER_CONTAINER])
    if existing.returncode == 0:
        if existing.stdout.strip() == "true":
            print(f"restarting existing opencode runner: {RUNNER_CONTAINER}", flush=True)
            restart = run_command(["docker", "restart", "--timeout", "3", RUNNER_CONTAINER])
            if restart.returncode != 0:
                raise RuntimeError(
                    "Found the opencode runner container, but could not restart it.\n"
                    f"Container: {RUNNER_CONTAINER}\n"
                    f"stderr:\n{restart.stderr.strip()}"
                )
            return RUNNER_CONTAINER

        print(f"starting existing opencode runner: {RUNNER_CONTAINER}", flush=True)
        start = run_command(["docker", "start", RUNNER_CONTAINER])
        if start.returncode != 0:
            raise RuntimeError(
                "Found the opencode runner container, but could not start it.\n"
                f"Container: {RUNNER_CONTAINER}\n"
                f"stderr:\n{start.stderr.strip()}"
            )
        return RUNNER_CONTAINER

    runner_id = compose_ps_runner(all_containers=True)
    if runner_id:
        if not is_container_running(runner_id):
            print(f"starting existing opencode runner: {runner_id}", flush=True)
            start = run_command(["docker", "start", runner_id])
            if start.returncode != 0:
                raise RuntimeError(
                    "Found an existing opencode runner, but could not start it.\n"
                    f"Container: {runner_id}\n"
                    f"stderr:\n{start.stderr.strip()}"
                )
        else:
            print(f"using existing opencode runner: {runner_id}", flush=True)
        return runner_id

    print("no opencode runner found; creating a persistent runner...", flush=True)
    create = run_command(
        [*docker_compose_base(), "up", "-d", "--no-deps", RUNNER_SERVICE]
    )
    if create.returncode != 0:
        raise RuntimeError(
            "No opencode runner exists, and creating one failed.\n"
            f"Command: {' '.join(create.args)}\n"
            f"stderr:\n{create.stderr.strip()}"
        )

    runner_id = compose_ps_runner(all_containers=False)
    if not runner_id:
        raise RuntimeError("Created the opencode runner, but Docker did not return its container id.")
    return runner_id


def run_opencode(
    model: str, timeout: float, result_path: Path
) -> tuple[subprocess.CompletedProcess[str], str]:
    runner_id = ensure_runner()
    prompt = build_prompt(result_path)
    cmd = [
        "docker",
        "exec",
        "-e",
        "TZ=Asia/Taipei",
        "-it",
        runner_id,
        "opencode",
        "run",
        "--model",
        model,
        "--agent",
        "build",
        prompt,
    ]
    print("running opencode inside runner; streaming output below...", flush=True)
    return run_command_streaming(cmd, timeout=timeout), runner_id


def main() -> int:
    args = parse_args()
    stop_requested = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    if not COMPOSE_FILE.exists():
        print(f"Compose file not found: {COMPOSE_FILE}", file=sys.stderr)
        return 2

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
            result, runner_id = run_opencode(args.model, args.timeout, result_path)
            finished_at = now_in_taiwan()
            body = result.stdout.strip()
            if not result_path.exists():
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
        except subprocess.TimeoutExpired as exc:
            finished_at = now_in_taiwan()
            section = (
                header
                + f"- Exit code: `timeout`\n"
                + f"- Finished: `{finished_at.isoformat(timespec='seconds')}`\n\n"
                + f"opencode timed out after {args.timeout} seconds.\n"
            )
            if exc.stdout:
                section += "\n### stdout\n\n```text\n" + exc.stdout.strip() + "\n```\n"
            if exc.stderr:
                section += "\n### stderr\n\n```text\n" + exc.stderr.strip() + "\n```\n"
            write_report(result_path, section)
            print(f"opencode timed out; wrote details to {result_path}", file=sys.stderr)
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
