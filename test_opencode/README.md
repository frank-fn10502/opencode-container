# OpenCode 測試工具

這個資料夾保留給開發與驗證用，不是一般使用者安裝 `opencode-dev` 的入口。

## 內容

- `test_python_docker_hello_world.py`：驗證 Python 能呼叫 Docker 執行簡單 container。
- `test_python_docker_exec.py`：驗證 Python 能對既有 container 執行命令。
- `test_python_opencode_exec.py`：驗證 Python 呼叫 OpenCode 相關流程。
- `run_cpp_opencode_monitor.py`：透過 Compose runner 讓 OpenCode 檢查 C++ 檔案。
- `stop_opencode_runner.sh`：停止測試 runner。

## C++ 檢查測試

這個測試會使用 `.devcontainer/docker-compose.yml` 的 `opencode-cpp-runner` service。執行前需要先安裝 image，並提供目前專案路徑：

```bash
OPENCODE_DEV_IMAGE=localhost/opencode-dev-yuta:<opencode-version> \
OPENCODE_DEV_WORKSPACE="$(pwd)" \
python3 test_opencode/run_cpp_opencode_monitor.py
```

可指定模型、timeout 與執行次數：

```bash
OPENCODE_DEV_IMAGE=localhost/opencode-dev-yuta:<opencode-version> \
OPENCODE_DEV_WORKSPACE="$(pwd)" \
python3 test_opencode/run_cpp_opencode_monitor.py \
  --model ollama/qwen3.5:9b \
  --timeout 240 \
  --iterations 1
```

輸出預設寫到 `test_opencode/logs/`。
