# OpenCode Dev Container Design

這份文件記錄目前定型的 `opencode-dev` Docker 使用模型。目標是讓使用者不用在 macOS、Windows、WSL 或 Linux 本機安裝 OpenCode，只要能執行 Docker，就能用同一個 image 操作自己的專案。

## 設計目標

- 使用本機 Docker image `localhost/opencode-dev-yuta:<opencode-version>` 提供 OpenCode 與基本開發工具。
- init script 使用使用者權限安裝，不需要 sudo。
- init script 把 runtime 安裝到 `~/.local/bin/opencode-dev-yuta/`，並在 shell profile 加入可移除的 `opencode-dev` function 區塊。
- 安裝必須可逆；解除安裝只移除 init script 自己加入的 profile 標記區塊與自己管理的 install 目錄。
- 使用者不需要修改 Compose 或 `.env` 設定。
- 每次啟動時，把目標專案目錄 bind mount 到 container 的 `/workspace`。
- 如果沒有指定目標目錄，就使用執行 `opencode-dev` 時的目前 `pwd`。
- OpenCode 的 OAuth、session、logs 和 runtime state 放在 Docker named volumes，不寫入專案目錄。
- 同一時間只允許一個名為 `opencode-dev-yuta` 的 container。

## Host 安裝策略

init script 使用使用者權限安裝，不需要 sudo。預設執行：

```bash
./init.sh
```

`init.sh` 是根目錄的使用者入口，內部會呼叫 `.devcontainer/scripts/init-opencode-dev.sh`。

init 的第一步會先確認 Docker image 是否已安裝。它會讀取 `.devcontainer/image.profile` 的 `IMAGE_REPOSITORY` 與 `IMAGE_TAG`；如果 `IMAGE_TAG` 已設定，必須本機 Docker 已存在 exact `IMAGE_REPOSITORY:IMAGE_TAG` 才會跳過載入。若 image 不存在，init 會要求先載入對應 image tar，成功後才繼續安裝或更新 `opencode-dev` launcher。

安裝完成後，使用者開新 shell 就能直接執行：

```bash
opencode-dev
```

安裝只會持久修改兩個 host 位置：

```text
~/.local/bin/opencode-dev-yuta/
偵測到的 shell profile，例如 ~/.zshrc、~/.bash_profile、~/.bashrc
```

`~/.local/bin/opencode-dev-yuta/` 是本工具專用的 install 目錄。init 會把執行 `opencode-dev` 需要的 runtime payload 複製到這裡：

```text
~/.local/bin/opencode-dev-yuta/.opencode-dev-managed
~/.local/bin/opencode-dev-yuta/.profile
~/.local/bin/opencode-dev-yuta/bin/opencode-dev
~/.local/bin/opencode-dev-yuta/compose.env
~/.local/bin/opencode-dev-yuta/docker-compose.yml
~/.local/bin/opencode-dev-yuta/image.profile
~/.local/bin/opencode-dev-yuta/scripts/init-opencode-dev.sh
~/.local/bin/opencode-dev-yuta/scripts/install-image.sh
~/.local/bin/opencode-dev-yuta/scripts/opencode-dev.sh
~/.local/bin/opencode-dev-yuta/config/opencode.json
```

`image.profile` 是 image 設定來源，保存 image repository 與 tag：

```bash
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
IMAGE_TAG=""
```

`IMAGE_REPOSITORY` 與 `IMAGE_TAG` 是目前 release 的 image 基準。`IMAGE_TAG` 已設定時，init 只接受 exact `IMAGE_REPOSITORY:IMAGE_TAG`；`IMAGE_TAG` 未設定時，才退回使用本機任一個 `IMAGE_REPOSITORY:*` 或讓使用者從 `.docker_imgs/` 選擇 tar。

`compose.env` 是 Compose 實際讀取 image 的固定來源。`build-image.sh` 成功後會寫入：

```bash
OPENCODE_DEV_IMAGE=localhost/opencode-dev-yuta:<opencode-version>
```

`docker-compose.yml` 只讀這個 `OPENCODE_DEV_IMAGE`，不在啟動時重新猜測 image。

`.profile` 會記錄 init 實際寫入的 shell profile 路徑，讓 `opencode-dev --uninstall` 可以移除同一個 profile block，不需要使用者記得當初寫到哪個檔案。

`bin/opencode-dev` 是 dispatcher，負責檢查安裝目錄，然後把所有參數原樣轉給 `scripts/opencode-dev.sh`。`opencode-dev --uninstall` 是 `scripts/opencode-dev.sh` 的正式命令，因此也會出現在 `opencode-dev --help`。

shell profile 只會被加入以下完整區塊。這個 block 不寫檔、不重建檔案、不改 PATH；它只把 `opencode-dev` 轉交給固定安裝位置的 dispatcher：

```bash
# >>> opencode-dev >>>
opencode-dev() {
  "${HOME}/.local/bin/opencode-dev-yuta/bin/opencode-dev" "$@"
}
# <<< opencode-dev <<<
```

這個區塊的作用很窄：

- 執行 `~/.local/bin/opencode-dev-yuta/bin/opencode-dev`。
- 原樣轉發使用者傳給 `opencode-dev` 的參數。
- 不修改 `PATH`、不寫 `/usr/local/bin`、不建立 symlink、不改 repo 內腳本權限。

如果 `~/.local/bin/opencode-dev-yuta/` 已存在但沒有 `.opencode-dev-managed`，init script 會拒絕接管，避免覆蓋或刪除使用者自己的資料。

解除安裝使用：

```bash
opencode-dev --uninstall
```

解除安裝只做兩件事：

- 移除 shell profile 中 `# >>> opencode-dev >>>` 到 `# <<< opencode-dev <<<` 的區塊。
- 如果 `~/.local/bin/opencode-dev-yuta/.opencode-dev-managed` 存在，刪除 `~/.local/bin/opencode-dev-yuta/`。

解除安裝會優先使用 `~/.local/bin/opencode-dev-yuta/.profile` 記錄的 profile 路徑；如果紀錄不存在，才使用自動偵測規則。如果 profile 不存在、沒有該區塊，或 install 目錄不是本工具管理，解除安裝會回報 no-op 或 skipped，不會刪除不屬於自己的內容。

repo 內的 init script 也保留 `--uninstall`，主要給測試或尚未 source profile 的情境使用：

```bash
bash .devcontainer/scripts/init-opencode-dev.sh --uninstall
```

`--profile` 只用來指定要修改哪個 shell profile。一般使用者不需要指定；測試或特殊 shell 設定才需要：

```bash
bash .devcontainer/scripts/init-opencode-dev.sh --profile ~/.zshrc
bash .devcontainer/scripts/init-opencode-dev.sh --uninstall --profile ~/.zshrc
```

自動偵測規則是：

```text
zsh            -> ~/.zshrc
bash on macOS  -> ~/.bash_profile
bash on Linux  -> ~/.bashrc
其他           -> ~/.profile
```

## Image 來源與封裝

公司環境不假設每台電腦都能穩定連外 build image。維護者在可 build 的電腦上從 Dockerfile 建立 image，script 會讀取 image 內的 OpenCode 版號，然後用固定名稱與版號 tag：

```text
localhost/opencode-dev-yuta:<opencode-version>
```

建立並打包 tar：

```bash
bash .devcontainer/scripts/build-image.sh
```

`build-image.sh` 除了輸出 tar，也會自動更新 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`。這些檔案應一併 commit 到 repo，讓使用者拉取新版後可以直接執行 `./init.sh` 安裝。

預設輸出：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>.tar
```

使用者拿到 tar 後，在自己的電腦載入 image：

```bash
bash .devcontainer/scripts/install-image.sh .docker_imgs/opencode-dev-yuta-<opencode-version>.tar
```

`install-image.sh` 只接受直接放在 `.docker_imgs/` 下、檔名符合 `opencode-dev-yuta-*.tar` 的 tar。它不接受 URL、不接受其他資料夾，也不遞迴搜尋子資料夾。tar 內必須含有 `localhost/opencode-dev-yuta:<opencode-version>` 的 image。載入成功後，如果 host launcher 已經安裝，它會同步更新 `~/.local/bin/opencode-dev-yuta/image.profile` 與 `~/.local/bin/opencode-dev-yuta/compose.env`。`install-image.sh` 不會修改 repo 內的 `.devcontainer/image.profile` 或 `.devcontainer/compose.env`，這些檔案由 `build-image.sh` 維護並 commit 到 repo。

如果 `.devcontainer/image.profile` 已指定 `IMAGE_TAG`，`install-image.sh` 只會接受 exact image：

```text
IMAGE_REPOSITORY:IMAGE_TAG
```

也只會搜尋：

```text
.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar
```

不帶參數執行時，`install-image.sh` 會先檢查本機 Docker 是否已有 `image.profile` 指定的 repository：

```bash
bash .devcontainer/scripts/install-image.sh
```

檢查順序是：

- 如果 `IMAGE_TAG` 已設定且本機已有 exact `IMAGE_REPOSITORY:IMAGE_TAG`，直接結束。
- 如果 `IMAGE_TAG` 已設定但 exact image 不存在，只搜尋 `.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar`。
- 如果 `IMAGE_TAG` 未設定，才搜尋根目錄 `.docker_imgs/opencode-dev-yuta-*.tar`。
- 如果 `IMAGE_TAG` 未設定且找到多個 tar，在同一個 terminal 列出編號，讓使用者選擇要載入哪一個。
- 如果找不到 tar，就停止並要求把 tar 放到 `.docker_imgs/`。

`init-opencode-dev.sh` 會先呼叫這個無參數流程；image 安裝或確認成功後，才會繼續安裝或更新 host launcher runtime。因此初次安裝與更新都使用 `./init.sh`。

## 使用模型

在目前位置開啟 OpenCode：

```bash
opencode-dev
```

也可以指定專案位置：

```bash
opencode-dev /path/to/project
opencode-dev ../other-project
```

使用者要切換專案時，不需要修改設定；只要在 host 上切換目錄或指定不同 path，再重新執行 `opencode-dev`。

## 進階說明

預設 help 只顯示日常操作：

```bash
opencode-dev --help
```

維護、除錯或確認 container 行為時，再查看進階說明：

```bash
opencode-dev --admin-help
```

進階說明只補充維護/除錯指令與 container 實作細節，不重複預設 help 已經列出的日常操作。

## Container 生命週期

`opencode-dev` 採用短生命週期 container：

```text
opencode-dev 啟動
  -> 解析目前目錄或使用者指定 path
  -> OPENCODE_DEV_WORKSPACE=/resolved/host/path docker compose run --rm ...
  -> docker-compose.yml bind mount OPENCODE_DEV_WORKSPACE 到 /workspace
  -> 執行 opencode
  -> opencode 結束後 container 自動移除
```

這個模型避免了 running container 無法新增 bind mount 的 Docker 限制。每次啟動都可以針對不同 host path 建立新的 bind mount，同時仍透過 Compose named volumes 保留 OpenCode 登入狀態。

資料夾參數透過 Compose 變數插值傳入：

```yaml
volumes:
  - ${OPENCODE_DEV_WORKSPACE:?Set OPENCODE_DEV_WORKSPACE to the host project path}:/workspace
```

`opencode-dev` script 只負責把使用者輸入的 path 解析成絕對路徑，然後在執行 Compose 時設定 `OPENCODE_DEV_WORKSPACE`。container image 由 `compose.env` 固定，environment、volumes、working directory 與 host mapping 都維護在 `docker-compose.yml`。

image 啟動時會先進入 entrypoint。若偵測到 `/workspace` 的 UID/GID 與容器內 `opencode` 不一致，entrypoint 會先在容器內調整 `opencode` 的 UID/GID，然後再以 `opencode` 身份執行主命令。這讓不同 host 使用者 ID 的 bind mount 在大多數情境下都能直接讀寫。

## 單 Container 限制

腳本固定使用：

```text
container name: opencode-dev-yuta
```

啟動前會檢查是否已經有同名 container：

- 如果沒有，直接啟動新的短生命週期 container。
- 如果有，詢問使用者是否停止並移除既有 container。
- 如果使用者拒絕，腳本結束，不碰既有 container。

這個限制讓行為保持明確：同一時間只有一個 `opencode-dev-yuta` container 操作主機檔案，避免多個 container 同時共用 OpenCode state 或同時操作專案造成混亂。

## State 與 OAuth

OpenCode state 固定使用兩個 Docker named volumes：

```text
opencode-home-yuta  -> /home/opencode/.local/share/opencode
opencode-state-yuta -> /home/opencode/.local/state
```

這些 volumes 是每個使用者自己的本機資料，會保留：

- OAuth credential，例如 GitHub Copilot login
- OpenCode session data
- logs
- prompt history
- 其他 runtime state

container 使用 `--rm` 沒有問題，因為 container 本身是可丟棄的；登入狀態與 session state 不放在 container filesystem，而是放在 named volumes。

解除安裝 `opencode-dev` launcher 不會刪除這兩個 volumes，避免誤刪登入狀態與歷史資料。若使用者明確要清除 OpenCode state，可以手動刪除：

```bash
docker volume rm opencode-home-yuta opencode-state-yuta
```

刪除後，OpenCode 需要重新登入或重建 state。

## 為什麼不使用 .env

目前定型設計不使用 `.env`。原因是日常使用者不需要修改 container 拓樸：

```text
image name       固定在 compose.env
image tag        build/install/update 後寫入 compose.env 與 image.profile
container name   固定為 opencode-dev-yuta
state volumes    固定為 opencode-home-yuta / opencode-state-yuta
project mount    由 opencode-dev 的 path 參數或 pwd 決定
```

若需要調整 image、volume、Compose 或 OpenCode config，由維護者直接修改 repo 內的腳本或 Compose 設定即可。一般使用者只需要先安裝 image tar，之後執行：

```bash
cd /path/to/project
opencode-dev
```

或：

```bash
opencode-dev /path/to/project
```

## 與 Compose 的關係

`.devcontainer/docker-compose.yml` 是日常 `opencode-dev` 的主要 container 設定來源。`opencode-dev` 不直接用 `docker run` 啟動 container；它讀取 `.devcontainer/compose.env` 作為固定 image 來源，並只把目前專案路徑透過環境變數傳給 Compose：

```bash
OPENCODE_DEV_WORKSPACE=/path/to/project \
docker compose --env-file .devcontainer/compose.env -f .devcontainer/docker-compose.yml run --rm --name opencode-dev-yuta opencode opencode
```

如果要用 Compose 手動除錯，使用 `compose.env` 中固定的 image：

```bash
OPENCODE_DEV_WORKSPACE=/path/to/project \
docker compose --env-file .devcontainer/compose.env -f .devcontainer/docker-compose.yml run --rm opencode bash
```

如果直接使用 Compose，必須提供 `--env-file .devcontainer/compose.env`，並設定 `OPENCODE_DEV_WORKSPACE`。日常入口仍然應使用 `opencode-dev`，這樣使用者只需要輸入專案位置或直接使用目前位置。

## 指令摘要

```bash
./init.sh
```

先確認本機 Docker 已有 `image.profile` 指定的 image；如果沒有，從 `.docker_imgs/` 的本機 tar 載入。image ready 後，安裝 `opencode-dev` runtime 到 `~/.local/bin/opencode-dev-yuta/`，並把 `opencode-dev` function 註冊到 shell profile。

```bash
bash .devcontainer/scripts/init-opencode-dev.sh --uninstall
```

從 shell profile 移除 `opencode-dev` function 區塊，並刪除本工具管理的 install 目錄。

```bash
bash .devcontainer/scripts/build-image.sh
```

從 `.devcontainer/Dockerfile`（CA 模式）build image，依 OpenCode 版號 tag 成 `localhost/opencode-dev-yuta:<opencode-version>`，更新 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`，並輸出 Docker image tar。

```bash
bash .devcontainer/scripts/build-image.sh --dockerfile Dockerfile.insecure
```

使用 `.devcontainer/Dockerfile.insecure` build image，預設放寬 apt/npm/pip/curl/wget 的 SSL 驗證設定。

```bash
bash .devcontainer/scripts/build-image.sh \
  --dockerfile Dockerfile \
  --build-arg COMPANY_CA_CERT_B64="$(base64 < company-ca.crt | tr -d '\n')"
```

在 CA 模式下傳入公司 CA（base64）並更新系統 trust store。

```bash
bash .devcontainer/scripts/install-image.sh .docker_imgs/opencode-dev-yuta-<opencode-version>.tar
```

把 image tar 載入本機 Docker。不會修改 repo 內的 `image.profile` 或 `compose.env`。

```bash
bash .devcontainer/scripts/install-image.sh
```

先檢查本機是否已有 `image.profile` 指定的 image；如果 `IMAGE_TAG` 已設定，必須是 exact `IMAGE_REPOSITORY:IMAGE_TAG`。沒有時才從 `.docker_imgs/` 載入對應 tar。


```bash
opencode-dev
```

在目前目錄開啟 OpenCode。

```bash
opencode-dev /path/to/project
```

在指定專案位置開啟 OpenCode。

```bash
opencode-dev --uninstall
```

移除 shell profile 中的 `opencode-dev` 區塊，並刪除本工具管理的 `~/.local/bin/opencode-dev-yuta/`。

進階指令請使用：

```bash
opencode-dev --admin-help
```

它只補充維護/除錯指令，以及實際 container 掛載、container 名稱與 state volume 的細節。
