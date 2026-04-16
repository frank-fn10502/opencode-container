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
- `.devcontainer/state/opencode-home/`：bind mount 的 OpenCode 本地資料目錄

## 建立 image

```bash
bash .devcontainer/scripts/build-image.sh
```

如需自訂 tag：

```bash
bash .devcontainer/scripts/build-image.sh my-opencode:dev
```

預設 tag 為 `localhost/opencode-dev:local`。

## 用 Docker Compose 啟動 OpenCode

必須先 build image，因為 `compose` 已被設定成只使用本機 image，且禁止 pull。

```bash
docker compose -f .devcontainer/compose.yaml run --rm opencode
```

如果你只想進容器 shell：

```bash
docker compose -f .devcontainer/compose.yaml run --rm opencode bash
```

## 直接用 Docker 啟動

```bash
bash .devcontainer/scripts/build-image.sh
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -v "$(pwd)/.devcontainer/config:/home/node/.config/opencode" \
  -v "$(pwd)/.devcontainer/state/opencode-home:/home/node/.local/share/opencode" \
  --add-host host.docker.internal:host-gateway \
  localhost/opencode-dev:local
```

## 用 VS Code Dev Container 開啟

1. 在 VS Code 開啟此資料夾
2. 執行 `Dev Containers: Reopen in Container`
3. 容器建立完成後，在內建終端機執行 `opencode`

如果本機還沒有 `localhost/opencode-dev:local`，VS Code / Dev Containers 也會因為 `pull_policy: never` 而停止，不會去 Docker Hub 嘗試拉取。

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
