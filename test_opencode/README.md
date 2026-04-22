# OpenCode 測試工具

這個資料夾保留給開發與驗證用，不是一般使用者安裝 `opencode-dev` 的入口。

## 內容

- `test_python_docker_hello_world.py`：驗證 Python 能呼叫 Docker 執行簡單 container。
- `test_python_docker_exec.py`：驗證 Python 能對測試 VM container 執行命令。
- `test_python_opencode_exec.py`：驗證 Python 呼叫 OpenCode VM run 流程。
- `setup_opencode_vm_runner.sh`：建立測試用 `opencode-vm`，並匯入 `.tmp/cpptest`。
- `run_cpp_opencode_vm_demo.sh`：一鍵建立或沿用測試 VM、執行 C++ 檢查、再 dump 回 `.tmp/cpptest`。
- `run_cpp_opencode_monitor.py`：透過測試用 `opencode-vm` 讓 OpenCode 檢查 C++ 檔案。
- `stop_opencode_runner.sh`：停止或移除測試 VM。

## C++ 檢查測試

這個測試會建立一台名為 `test-cpp` 的 `opencode-vm`，把 `.tmp/cpptest` 匯入 VM 的 `/workspace`，再透過 Python 呼叫 `opencode-vm run` 執行 `opencode run`。

執行前需要先安裝 image：

```bash
test_opencode/run_cpp_opencode_vm_demo.sh
```

這支 demo script 會檢查 `test-cpp` VM 是否存在；不存在就 setup，存在就沿用或啟動。OpenCode 會檢查 VM 內的 `/workspace/cpptest`，執行完成後會把這個 VM source path dump 回 `.tmp/cpptest`。它不接受參數，也不會自動停止 VM；model、iterations、dump source/dist 都寫在 script 裡。

需要調整模型或 dump path 時，直接修改 `run_cpp_opencode_vm_demo.sh` 上方的設定值。若要手動指定參數，可直接執行 Python monitor：

```bash
python3 test_opencode/run_cpp_opencode_monitor.py \
  --skip-setup \
  --workspace-dir /workspace/cpptest \
  --model ollama/qwen3.5:9b \
  --iterations 1
```

若只想先準備測試 VM：

```bash
test_opencode/setup_opencode_vm_runner.sh
```

輸出預設寫到 `test_opencode/logs/`。若要跳過 setup、只跑 Python monitor，可直接執行：

```bash
python3 test_opencode/run_cpp_opencode_monitor.py --skip-setup
```

停止或移除測試 VM 需要手動執行：

```bash
test_opencode/stop_opencode_runner.sh
test_opencode/stop_opencode_runner.sh --remove
```
