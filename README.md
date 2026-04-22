# opencode-dev

`opencode-dev` 讓使用者不用在主機直接安裝 OpenCode。它會用本機 Docker image 啟動 container，並把目前資料夾或指定專案資料夾掛到 container 的 `/workspace`。

## 需求

- Docker
- 已取得公司提供的 Docker image tar

image tar 預設放在專案根目錄：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

tar 只能放在 `.docker_imgs/` 這一層，不支援其他位置。

如果本機 Docker 已經有 `.devcontainer/image.profile` 指定的 image（通常是 exact `localhost/opencode-dev-yuta:${IMAGE_TAG}`），可以不放 tar；init 會直接使用既有 image。

## 安裝

在專案根目錄執行：

```bash
./init.sh
```

`init.sh` 會執行以下流程：

1. 讀取 `.devcontainer/image.profile` 取得指定的 image 版本。
2. 檢查本機 Docker 是否已有該 image；如果沒有，從 `.docker_imgs/` 載入對應 tar。
3. 安裝 `opencode-dev` runtime 到 `~/.local/bin/opencode-dev-yuta/`。
4. 在 shell profile 加入 `opencode-dev` function。

完成後請開新 terminal，或依照 init 輸出的提示 source 對應 profile。

## 使用

在目前資料夾開啟 OpenCode：

```bash
opencode-dev
```

第一次在某個資料夾執行時，`opencode-dev` 會建立：

```text
.opencode-dev-yuta/
```

這個資料夾用來放該專案自己的 profile，例如 `Dockerfile.python`。
launcher 也會自動放入一份很薄的 `README.md`，指出完整 profile Dockerfile 規則的位置。

指定專案資料夾：

```bash
opencode-dev /path/to/project
opencode-dev ../other-project
```

如果指定的資料夾不存在，script 會建立它。每次啟動只會把該資料夾掛到 container 的 `/workspace`。

opencode-dev 會提供一份 OpenCode global `AGENTS.md`，讓模型預設使用繁體中文回答並保留英文專有名詞。專案自己的 `AGENTS.md` 仍可放在專案根目錄，作為 project rules。

profile Dockerfile 是 build-time 環境配方，一般 profile 不需要、也不應設定 `USER`。實際啟動 container 時，opencode-dev 會先用 root 執行 entrypoint，檢查 `/workspace` 的擁有者 UID/GID，整理 `/home/opencode` 權限，然後再切回 `opencode` 執行 OpenCode。

## Profile

`opencode-dev` 支援 user 與 project 兩層 profile：

```text
~/.opencode-dev-yuta/Dockerfile.<profile>
<project>/.opencode-dev-yuta/Dockerfile.<profile>
<project>/.opencode-dev-yuta/config.env
<project>/.opencode-dev-yuta/README.md
```

user profile 在所有專案都能使用；project profile 只在該專案資料夾下使用。完整 Dockerfile 規則放在 `~/.opencode-dev-yuta/README.md`；進入 container 後可從 `/opencode-dev/user/README.md` 讀取同一份 user guide。查看目前設定與可用 profile：

```bash
opencode-dev profile status
```

在 opencode-dev 裡可以直接呼叫 OpenCode slash command 讓模型建立 project profile：

```text
/project-profile <profile-name> <需要的工具或環境描述>
```

這個 command 會要求模型只修改目前專案的 `.opencode-dev-yuta/`，建立 `Dockerfile.<profile-name>` 並寫入 `config.env`。完成後離開目前 container，再執行一次 `opencode-dev`，launcher 會 build 並使用新的 project profile。

預設 profile 名稱是 `default`，它會直接使用 `localhost/opencode-dev-yuta:base`，不會另外 build profile image。`Dockerfile.default` 會保留作為可見模板，但啟動 default 時不會用它 build。

launcher 會同步幾個內建 user profile template 到 user profile 目錄，並在工具更新後覆蓋同名內建檔案。除了保留名稱 `default` 之外，內建 profile 都使用 `opencode-` 前綴，避免和使用者自訂名稱撞名：

```text
Dockerfile.default
Dockerfile.opencode-python
Dockerfile.opencode-dotnet
Dockerfile.opencode-npm
```

設定 profile：

```bash
opencode-dev profile set opencode-python
```

切回預設 profile：

```bash
opencode-dev profile set default
```

選擇會寫入目前專案的 `.opencode-dev-yuta/config.env`，下次直接執行 `opencode-dev` 會沿用。若目前路徑是使用者 home，選擇會寫入 `~/.opencode-dev-yuta/config.env`。

如果 user 與 project 同時存在同名 profile，`opencode-dev` 會優先採用 project profile，並在第一次遇到時提示。

如果 base image 更新，下一次執行客製化 profile 時會詢問 Yes/No，確認是否現在重建對應的 profile image；如果任務緊急，可以先回答 No 並沿用既有 profile image。內建且未修改的 profile 會直接重建。profile image 不存在或 profile Dockerfile 本身變更時，launcher 會直接準備需要的 profile image。

profile Dockerfile 可以固定使用穩定 base alias：

```dockerfile
FROM localhost/opencode-dev-yuta:base

RUN apt-get update \
    && apt-get install -y --no-install-recommends graphviz \
    && rm -rf /var/lib/apt/lists/*
```

更新 image 後，`localhost/opencode-dev-yuta:base` 會指向新版 base；下次啟動需要重建的 profile 時，工具會依情況提示並準備新的 profile image。

## 常用指令

```bash
opencode-dev --help
```

查看日常操作。

```bash
opencode-dev --admin-help
```

查看 container、Compose 與 debug 相關細節。

```bash
opencode-dev image list
```

列出本機的 `localhost/opencode-dev-yuta:<tag>` image，包含目前設定使用的 base image、`base` alias、兩者的對應關係，以及是否仍有 container 使用。

```bash
opencode-dev image rm localhost/opencode-dev-yuta:<tag>
```

刪除指定的環境 image 以節省空間。這個指令只接受完整的 `name:tag`，例如：

```bash
opencode-dev image rm localhost/opencode-dev-yuta:1.4.7
```

目前 opencode 虛擬環境使用中的基礎 image，以及 `localhost/opencode-dev-yuta:base` alias 會在 `image list` 中標注為 `protected`，且 `image rm` 會拒絕刪除並說明原因。若要節省空間，請刪除舊版 image 或 profile 產生出的 image。

```bash
opencode-dev --uninstall
```

移除 shell profile 中的 `opencode-dev` 區塊，並刪除 `~/.local/bin/opencode-dev-yuta/` 中由本工具安裝的 runtime。

解除安裝不會刪除 Docker image，也不會刪除 OpenCode 的 Docker volumes，避免誤刪登入狀態與 session data。

## 測試用 Web UI Container

專案另外提供一個長時間執行的 Compose service：

```text
opencode-web-test
```

它會在 container 內執行：

```bash
opencode serve --hostname 0.0.0.0 --port 8001
```

並把 host 的 `8001` 映射到 container 的 `8001`。啟動前請先執行過 `./init.sh`，讓本機有指定的 image 與 `~/.opencode-dev-yuta/` 設定目錄。

在專案根目錄啟動：

```bash
OPENCODE_DEV_IMAGE="$(sed -n 's/^OPENCODE_DEV_IMAGE=//p' .devcontainer/image.profile)" \
OPENCODE_DEV_WORKSPACE="$(pwd)" \
OPENCODE_DEV_USER_CONFIG="${HOME}/.opencode-dev-yuta" \
docker compose -f .devcontainer/docker-compose.yml up -d opencode-web-test
```

開啟：

```text
http://localhost:8001
```

若需要設定 server password，可在啟動時加上：

```bash
OPENCODE_SERVER_PASSWORD="<password>"
```

停止測試 container：

```bash
docker compose -f .devcontainer/docker-compose.yml stop opencode-web-test
```

## OpenCode VM

`opencode-vm` 是另一套常駐工作機模型，和 `opencode-dev` 的短生命開發 container 分開。

```text
opencode-dev  把 host 專案資料夾 bind mount 到 /workspace，適合開乾淨環境。
opencode-vm   建立常駐 container，/workspace 是 Docker named volume。
```

安裝或更新後會同時註冊 `opencode-dev` 與 `opencode-vm` shell function。
`opencode-vm` 使用獨立的 VM image，建置在 opencode-dev base image 之上，並額外包含常駐工作機常用工具，例如 ssh client/server、tmux、rsync、process/network utilities。

最簡使用預設 VM：

```bash
opencode-vm create
opencode-vm import ./project
opencode-vm start
opencode-vm run -- "請檢查 /workspace"
opencode-vm dump ./opencode-vm-output
opencode-vm stop
```

開啟 Web UI：

```text
http://localhost:8001
```

`opencode-vm` 支援多台具名 VM；不指定名稱時使用 `default`。
VM 內的 Linux 使用者會命名為 `opencode-vm-<name>`，例如 `opencode-vm-main`，方便在 shell prompt 或 `whoami` 中辨識目前所在環境。VM 名稱需使用小寫英數、dot、underscore、hyphen，且長度不超過 20 字元。

```bash
opencode-vm create main
opencode-vm import main ./project
opencode-vm start main --port 8002
opencode-vm shell main
opencode-vm run main -- "請執行測試"
opencode-vm dump main ./main-output
```

常用管理指令：

```bash
opencode-vm list
opencode-vm status [name]
opencode-vm logs [name]
opencode-vm url [name]
opencode-vm restart [name] [--port N]
opencode-vm rm [--yes] [name]
```

`opencode-vm rm` 會刪除該 VM 的 container 與 named volumes，包含 `/workspace` 內容。需要保留檔案時，請先執行 `opencode-vm dump`。自動化情境可使用 `--yes` 略過確認。

## 更新 Image

更新時使用和初次安裝相同的入口：

```bash
./init.sh
```

使用者只要把對應 tar 放到：

```text
.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar
```

然後重新執行 `./init.sh`。

`./init.sh` 會：

- 檢查本機是否已有 `.devcontainer/image.profile` 指定的 exact image。
- 如果沒有，從 `.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar` 載入。
- 更新 `localhost/opencode-dev-yuta:base` alias，讓 profile Dockerfile 不需要跟著版本修改 `FROM`。
- 重新部署 `~/.local/bin/opencode-dev-yuta/` 裡的 runtime scripts。
- 保留使用者既有的 Docker volumes 與登入狀態。

## 維護者

維護者用的 build/update/push/pull script 與操作說明集中在 [admin/README.md](admin/README.md)。

非必要不要更新 OpenCode version。若只是調整 default/base 環境，通常只需要增加 `.devcontainer/image.profile` 的 `ENV_REVISION`，再執行 `./admin/build-image.sh`。這個 build 會同時產生 opencode-dev base image 與 opencode-vm image。

更完整的設計細節在 [.devcontainer/docs/README.md](.devcontainer/docs/README.md)。
