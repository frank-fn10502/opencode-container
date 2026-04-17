# OpenCode Container Environment

這個專案把所有 container 相關檔案集中在 `.devcontainer/`，同時提供：

1. 用 `.devcontainer/Dockerfile` 建立乾淨的 `opencode` 映像
2. 用 VS Code / Dev Containers 直接打開同一套環境
3. 預設透過 Ollama 連線模型

## 需求

- Docker
- VS Code 與 Dev Containers 擴充套件（若要使用 `.devcontainer`）
- 本機已啟動 Ollama，並可從 container 透過 `http://host.docker.internal:11434` 存取

## 目錄說明

- `.devcontainer/Dockerfile`：OpenCode image 定義
- `.devcontainer/compose.yaml`：只負責從 local image 啟動 container，不負責 build
- `.devcontainer/config/opencode.json`：預設 OpenCode 設定，已改成使用 Ollama
- `.devcontainer/scripts/build-image.sh`：建 image 的 bash script
- `.devcontainer/scripts/opencode-dev.sh`：日常入口，用短生命週期 container 掛載指定專案
- `.devcontainer/scripts/init-opencode-dev.sh`：把 `opencode-dev` function 註冊到 shell profile

OpenCode 的 DB、logs、prompt history 等 runtime state 使用 Docker named volumes，不會寫入專案資料夾。

## 建立 image

```bash
bash .devcontainer/scripts/build-image.sh
```

如需自訂 tag：

```bash
bash .devcontainer/scripts/build-image.sh my-opencode:dev
```

預設 tag 為 `localhost/opencode-dev:local`。

## 初始化 opencode-dev 指令

第一次使用時先建立 image，然後執行 init script：

```bash
bash .devcontainer/scripts/build-image.sh
bash .devcontainer/scripts/init-opencode-dev.sh
```

script 會：

- 在目前 shell 對應的 profile 註冊 `opencode-dev` function
- 讓 `opencode-dev` 呼叫這個 repo 裡的 `.devcontainer/scripts/opencode-dev.sh`

註冊後請重新開啟 terminal，或依照 script 輸出 `source` 對應 profile。

OpenCode 狀態固定保存在 `opencode-home` 和 `opencode-state` 兩個 Docker external volumes，會保留 OAuth、session、logs 和其他 runtime data。

## 使用 opencode-dev

在專案目錄裡直接執行：

```bash
opencode-dev
```

這會啟動一個短生命週期 container，把目前目錄掛到 `/workspace`，並在 container 裡執行 `opencode`。`opencode` 結束後 container 會自動移除，OpenCode auth/state 會保留在 external volumes。

也可以指定任意 host 專案路徑；沒有指定路徑時才使用目前 `pwd`：

```bash
opencode-dev /path/to/project-a
opencode-dev ../project-b
opencode-dev /path/to/project-c -- --help
```

如果指定的路徑還不存在，script 會建立該目錄。每次只會把該目錄掛到 `/workspace`，安全邊界就是這次指定的專案資料夾。

script 固定使用 container name `opencode-dev`。如果同名 container 已存在，會詢問是否關閉並移除舊 container；拒絕時會保留既有 container 並結束。這讓同一時間最多只有一個 `opencode-dev` container。

常用指令：

```bash
opencode-dev                    # 掛載目前目錄並執行 opencode
opencode-dev /path/to/project   # 掛載指定目錄並執行 opencode
opencode-dev shell /path/to/project
opencode-dev stop               # 停止並移除現有 opencode-dev container
opencode-dev status             # 查看現有 opencode-dev container
```

不要手動刪除 `opencode-home` 和 `opencode-state`，否則 OAuth 與 session state 會消失。

## 用 Docker Compose 啟動 OpenCode

必須先 build image，因為 `compose` 已被設定成只使用本機 image，且禁止 pull。

```bash
docker compose -p opencode-dev -f .devcontainer/compose.yaml up -d
docker compose -p opencode-dev -f .devcontainer/compose.yaml exec opencode bash
```

這個 compose 入口主要保留給 VS Code Dev Containers 或手動除錯；日常使用建議使用 `opencode-dev`，因為它可以針對任意目錄建立短生命週期 container。

## 直接用 Docker 啟動

```bash
bash .devcontainer/scripts/build-image.sh

docker volume create opencode-home
docker volume create opencode-state

docker run --rm -it --name opencode-dev \
  -v "/path/to/project:/workspace" \
  -v "$(pwd)/.devcontainer/config/opencode.json:/home/node/.config/opencode/opencode.json:ro" \
  -v opencode-home:/home/node/.local/share/opencode \
  -v opencode-state:/home/node/.local/state \
  --add-host host.docker.internal:host-gateway \
  localhost/opencode-dev:local
```

直接使用 Docker 時，同一時間仍建議只保留一個 `opencode-dev` container。

## 用 VS Code Dev Container 開啟

1. 在 VS Code 開啟此資料夾
2. 執行 `Dev Containers: Reopen in Container`
3. 容器建立完成後，在內建終端機執行 `opencode`

如果本機還沒有 `localhost/opencode-dev:local`，VS Code / Dev Containers 也會因為 `pull_policy: never` 而停止，不會去 Docker Hub 嘗試拉取。

## 觸發 OpenCode 檢查 C++ 程式碼

這個 script 會在 container 內檢查專案中的 C++ 檔案，回報最後修改時間，並嘗試編譯/執行含有 `main()` 的 C++ source。編譯與執行都發生在 container 的 `/tmp`，不會在專案資料夾產生 build artifact。

script 會使用獨立的 `opencode-cpp-runner` service 與獨立 Docker named volumes，避免和你正在使用的主要 `opencode` container 共用 OpenCode DB/state。

每次執行都會把人類可讀的輸出寫到 `opencode-output/`：

- `*-cpp-input.json`：送給 opencode 的 C++ 檢查摘要
- `*-opencode.log`：opencode 的完整 stdout/stderr，以及等待 heartbeat

```bash
python3 .devcontainer/scripts/inspect-cpp-with-opencode.py
```

可指定模型與 timeout：

```bash
python3 .devcontainer/scripts/inspect-cpp-with-opencode.py --model ollama/qwen3:8b --timeout 180
```

可指定輸出資料夾：

```bash
python3 .devcontainer/scripts/inspect-cpp-with-opencode.py --output-dir opencode-output
```

手動驗證 `opencode run` 時，若使用 `--file`，需要在檔案參數後加上 `--`，避免後面的 prompt 被當成另一個 file：

```bash
docker compose -f .devcontainer/compose.yaml run --rm --no-deps -T opencode-cpp-runner \
  opencode --print-logs --log-level DEBUG run \
  --model ollama/qwen3.5:9b \
  --dir /workspace \
  --file /workspace/opencode-output/20260416T114604-cpp-input.json \
  -- \
  "請根據附加的 JSON 檔案，用繁體中文簡短回報 C++ 程式碼、最後修改時間、編譯與執行結果。"
```

## 預設模型設定

目前 `.devcontainer/config/opencode.json` 預設使用：

- Provider：`ollama`
- Base URL：`http://host.docker.internal:11434/v1`
- Model：`qwen3.5:9b`
- Small model：`qwen3:8b`

目前設定檔也已列出你本機現有的 Ollama models：

- `qwen3.5:9b`
- `qwen3:8b`
- `gemma4:e4b`
- `gpt-oss:20b`

如果你要改模型名稱，直接修改 `.devcontainer/config/opencode.json` 即可。
