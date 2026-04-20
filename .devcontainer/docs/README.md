# OpenCode Dev Container Design

這份文件記錄目前定型的 `opencode-dev` Docker 使用模型。目標是讓使用者不用在 macOS、Windows、WSL 或 Linux 本機安裝 OpenCode，只要能執行 Docker，就能用同一個 image 操作自己的專案。

## 設計目標

- 使用本機 Docker image `localhost/opencode-dev-yuta:<opencode-version>-env.<revision>` 提供 OpenCode 與基本開發工具。
- init script 使用使用者權限安裝，不需要 sudo。
- init script 把 runtime 安裝到 `~/.local/bin/opencode-dev-yuta/`，並在 shell profile 加入可移除的 `opencode-dev` function 區塊。
- 安裝必須可逆；解除安裝只移除 init script 自己加入的 profile 標記區塊與自己管理的 install 目錄。
- 使用者不需要修改 Compose 或 `.env` 設定。
- 每次啟動時，把目標專案目錄 bind mount 到 container 的 `/workspace`。
- 如果沒有指定目標目錄，就使用執行 `opencode-dev` 時的目前 `pwd`。
- 每個專案第一次執行 `opencode-dev` 時都會建立 `.opencode-dev-yuta/`，用來放 project profile。
- user profile 放在 `~/.opencode-dev-yuta/Dockerfile.<profile>`；project profile 放在 `<project>/.opencode-dev-yuta/Dockerfile.<profile>`。
- OpenCode 的 OAuth、session、logs 和 runtime state 放在 Docker named volumes，不寫入專案目錄。
- 同一時間只允許一個名為 `opencode-dev-yuta` 的 container。

## Host 安裝策略

init script 使用使用者權限安裝，不需要 sudo。預設執行：

```bash
./init.sh
```

`init.sh` 是根目錄的使用者入口，內部會呼叫 `.devcontainer/scripts/init/init-opencode-dev.sh`。

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
~/.local/bin/opencode-dev-yuta/init/init-opencode-dev.sh
~/.local/bin/opencode-dev-yuta/init/install-image.sh
~/.local/bin/opencode-dev-yuta/runtime/opencode-dev.sh
~/.local/bin/opencode-dev-yuta/runtime/common.sh
~/.local/bin/opencode-dev-yuta/runtime/profiles.sh
~/.local/bin/opencode-dev-yuta/runtime/container.sh
~/.local/bin/opencode-dev-yuta/config/opencode.json
```

repo 內的 script 依用途分成三類：

```text
.devcontainer/scripts/init/
  init-opencode-dev.sh  初次安裝、更新 launcher、解除安裝
  install-image.sh      init 時確認或載入 base image

.devcontainer/scripts/runtime/
  opencode-dev-dispatcher.sh  shell function 呼叫的固定入口
  opencode-dev.sh             日常 opencode-dev 指令解析
  common.sh                   repo/install 路徑、base image、project path 共用邏輯
  profiles.sh                 profile 設定、Dockerfile 查找、profile image build
  container.sh                container lifecycle 與 compose run
  entrypoint-opencode.sh      image 內的 container entrypoint

admin/
  README.md                   維護者 build/update/push/pull 說明
  ca/                         CA-aware build 的 .crt 與 CA script
    README.md                 CA 收集與 CA-aware build 說明
    collect-ca.sh             嘗試從常見 registry TLS chain 收集 root CA
    build-ca-image.sh         從 admin/ca/*.crt build CA-aware image
  update-opencode-version.sh  維護者解析 latest OpenCode 版本並寫入設定
  build-image.sh              維護者 build insecure base image 與輸出 tar
  push-dockerhub.sh           維護者推送 image
  pull-and-pack-image.sh      維護者下載 image 並重新打包 tar
```

安裝後只會複製 `init/` 與 `runtime/` 需要的內容到 `~/.local/bin/opencode-dev-yuta/`；`admin/` 工具留在 repo 中給維護者使用。

`image.profile` 是 image 設定來源，保存 image repository、OpenCode 版本與環境 revision：

```bash
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
OPENCODE_VERSION="1.4.7"
ENV_REVISION="1"
IMAGE_TAG="${OPENCODE_VERSION}-env.${ENV_REVISION}"
```

`OPENCODE_VERSION` 是 Dockerfile 實際安裝的 OpenCode 版本。`ENV_REVISION` 是 opencode-dev default/base 環境 revision；同一個 OpenCode 版本下，只要 base 環境有會影響使用者的變更就遞增。`IMAGE_TAG` 已設定時，init 只接受 exact `IMAGE_REPOSITORY:IMAGE_TAG`；`IMAGE_TAG` 未設定時，才退回使用本機任一個 `IMAGE_REPOSITORY:*` 或讓使用者從 `.docker_imgs/` 選擇 tar。

`compose.env` 是 Compose 實際讀取 image 的固定來源。`build-image.sh` 成功後會寫入：

```bash
OPENCODE_DEV_IMAGE=localhost/opencode-dev-yuta:<opencode-version>-env.<revision>
```

`docker-compose.yml` 只讀這個 `OPENCODE_DEV_IMAGE`，不在啟動時重新猜測 base image。`build-image.sh` 與 `install-image.sh` 也會更新穩定 alias：

```text
localhost/opencode-dev-yuta:base
```

user/project profile 的 Dockerfile 可以固定 `FROM localhost/opencode-dev-yuta:base`，不用在 OpenCode image 版號更新後修改 `FROM`。

`.profile` 會記錄 init 實際寫入的 shell profile 路徑，讓 `opencode-dev --uninstall` 可以移除同一個 profile block，不需要使用者記得當初寫到哪個檔案。

`bin/opencode-dev` 是 dispatcher，負責檢查安裝目錄，然後把所有參數原樣轉給 `runtime/opencode-dev.sh`。`opencode-dev --uninstall` 是 `runtime/opencode-dev.sh` 的正式命令，因此也會出現在 `opencode-dev --help`。

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
bash .devcontainer/scripts/init/init-opencode-dev.sh --uninstall
```

`--profile` 只用來指定要修改哪個 shell profile。一般使用者不需要指定；測試或特殊 shell 設定才需要：

```bash
bash .devcontainer/scripts/init/init-opencode-dev.sh --profile ~/.zshrc
bash .devcontainer/scripts/init/init-opencode-dev.sh --uninstall --profile ~/.zshrc
```

自動偵測規則是：

```text
zsh            -> ~/.zshrc
bash on macOS  -> ~/.bash_profile
bash on Linux  -> ~/.bashrc
其他           -> ~/.profile
```

## Image 來源與封裝

公司環境不假設每台電腦都能穩定連外 build image。OpenCode 版本與 default/base 環境 revision 由 `.devcontainer/image.profile` 定義：

```text
OPENCODE_VERSION="1.4.7"
ENV_REVISION="1"
IMAGE_TAG="${OPENCODE_VERSION}-env.${ENV_REVISION}"
```

tag 格式是：

```text
localhost/opencode-dev-yuta:<opencode-version>-env.<revision>
```

維護者若要解析目前可安裝的 OpenCode 版本，只在 release host 上執行：

```bash
./admin/update-opencode-version.sh
```

這個 script 會使用 `OPENCODE_VERSION=latest` 建立暫時 image，讀取 `opencode --version`，再寫回 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`。如果 OpenCode 版本有變，`ENV_REVISION` 預設重設為 `1`；如果版本沒變，會保留目前 revision。若 default/base 環境在同一個 OpenCode 版本下有變更，維護者應手動增加 `ENV_REVISION`，或執行：

```bash
./admin/update-opencode-version.sh --env-revision 2
```

一般 build 不會再依 build 結果決定 tag，而是照 `image.profile` 指定版本安裝並驗證。預設採用 `.devcontainer/Dockerfile.insecure`，先確保內網可用。建立並打包 tar：

```bash
./admin/build-image.sh
```

如果要建立 CA-aware image，先把 `.crt` 放進 `admin/ca/`，再執行：

```bash
./admin/ca/build-ca-image.sh
```

也可以先嘗試自動收集常見 registry 在 TLS handshake 中回傳的 certificate chain：

```bash
./admin/ca/collect-ca.sh
```

這個 script 先使用 `openssl s_client -showcerts` 看到的憑證，預設保存 `Basic Constraints: CA:TRUE` 的憑證；如果 TLS response 沒有送出 self-signed root CA，會再嘗試依照 AIA CA Issuers URL 取得 root CA。AIA 只支援 `http://` 與 `https://` URL；如果公司憑證只提供 `ldap:///...`，script 會提示無法下載，仍需從 OS/browser trust store 匯出公司 root CA。可用 `--no-aia` 停用 AIA；除錯時可用 `--save-chain`、`--save-leaf` 或 `--save-chain-top`。

若 `admin/ca/` 裡沒有任何 `.crt`，script 會停止並提示無法建立。

`build-image.sh` 會把 `OPENCODE_VERSION` 傳入 Dockerfile，驗證 build 出來的 `opencode --version` 與 `image.profile` 一致，並更新 `localhost/opencode-dev-yuta:base` alias。這些檔案應一併 commit 到 repo，讓使用者拉取新版後可以直接執行 `./init.sh` 安裝。

預設輸出：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

使用者拿到 tar 後，在自己的電腦載入 image：

```bash
bash .devcontainer/scripts/init/install-image.sh .docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

`install-image.sh` 只接受直接放在 `.docker_imgs/` 下、檔名符合 `opencode-dev-yuta-*.tar` 的 tar。它不接受 URL、不接受其他資料夾，也不遞迴搜尋子資料夾。tar 內必須含有 `localhost/opencode-dev-yuta:<opencode-version>-env.<revision>` 的 image。載入成功後，如果 host launcher 已經安裝，它會同步更新 `~/.local/bin/opencode-dev-yuta/image.profile` 與 `~/.local/bin/opencode-dev-yuta/compose.env`。`install-image.sh` 不會修改 repo 內的 `.devcontainer/image.profile` 或 `.devcontainer/compose.env`，這些檔案由 release script 維護並 commit 到 repo。

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
bash .devcontainer/scripts/init/install-image.sh
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

第一次在某個專案執行時，launcher 會確保存在：

```text
<project>/.opencode-dev-yuta/
```

launcher 會把完整 profile Dockerfile guide 複製到 `~/.opencode-dev-yuta/README.md`，並把很薄的 project README 複製到 `<project>/.opencode-dev-yuta/README.md`。project README 只負責指出完整規則的位置；完整規則仍以 user guide 為準。

## Profile 模型

profile 是一個 Dockerfile 檔案，檔名固定為：

```text
Dockerfile.<profile>
```

user profile 放在：

```text
~/.opencode-dev-yuta/Dockerfile.<profile>
```

project profile 放在：

```text
<project>/.opencode-dev-yuta/Dockerfile.<profile>
```

選擇中的 profile 記錄在：

```text
<project>/.opencode-dev-yuta/config.env
```

profile guide 放在：

```text
~/.opencode-dev-yuta/README.md                 完整規則與範例
<project>/.opencode-dev-yuta/README.md         指向完整規則的薄指引
container: /opencode-dev/user/README.md        user guide 的唯讀掛載
```

如果目前專案路徑就是使用者的 home directory，選擇會記錄在：

```text
~/.opencode-dev-yuta/config.env
```

如果目前專案路徑就是使用者的 home directory，`~/.opencode-dev-yuta` 只會被視為 user profile 目錄，不會再被重複當成 project profile。

`opencode-dev profile status` 會列出目前 project 的 selected profile、config 路徑，以及可用的 user 與 project profile。profile 顯示名稱使用 `username/Dockerfile.<profile>` 與 `projectname/Dockerfile.<profile>`，例如：

```text
user profiles:
  frank/Dockerfile.default
  frank/Dockerfile.opencode-python

project profiles:
  service-api/Dockerfile.python
```

預設 profile 是 `default`。launcher 會從 `.devcontainer/config/user-profiles/` 同步內建 user profile template 到 `~/.opencode-dev-yuta/`，並在工具更新後覆蓋同名內建檔案。除了保留名稱 `default` 之外，內建 profile 都使用 `opencode-` 前綴，避免和使用者自訂名稱撞名：

```text
Dockerfile.default
Dockerfile.opencode-python
Dockerfile.opencode-dotnet
Dockerfile.opencode-npm
```

`default` profile 啟動時會直接使用 `localhost/opencode-dev-yuta:base`，不會另外 build profile image。`Dockerfile.default` 會保留作為可見模板，但啟動 default 時不會用它 build。指定 profile 並開啟 OpenCode：

```bash
opencode-dev profile set opencode-python
```

切回預設 profile：

```bash
opencode-dev profile set default
```

launcher 會先找 project profile，再找 user profile。若 project 與 user 有同名 profile，project profile 優先，並在第一次遇到該覆蓋關係時提示。若 profile Dockerfile 或 selected profile 發生變化，launcher 會在啟動 OpenCode 前提示原因並自動準備對應的 profile image。若非 `default` profile 偵測到 base image 已更新，launcher 會詢問使用者是否現在重建；使用者也可以略過重建，先沿用既有 profile image。

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
  -> 確保 <project>/.opencode-dev-yuta/ 與 user default profile 存在
  -> 讀取 .opencode-dev-yuta/config.env 決定 selected profile
  -> 如果 selected profile 是 default，直接使用 localhost/opencode-dev-yuta:base
  -> 如果不是 default，找到 Dockerfile.<profile>，project profile 優先於同名 user profile
  -> 若非 default profile image 不存在或已過期，自動 build 或詢問
  -> OPENCODE_DEV_WORKSPACE=/resolved/host/path OPENCODE_DEV_USER_CONFIG=~/.opencode-dev-yuta docker compose run --rm ...
  -> docker-compose.yml bind mount OPENCODE_DEV_WORKSPACE 到 /workspace
  -> docker-compose.yml bind mount OPENCODE_DEV_USER_CONFIG 到 /opencode-dev/user:ro
  -> 執行 opencode
  -> opencode 結束後 container 自動移除
```

這個模型避免了 running container 無法新增 bind mount 的 Docker 限制。每次啟動都可以針對不同 host path 建立新的 bind mount，同時仍透過 Compose named volumes 保留 OpenCode 登入狀態。

資料夾參數透過 Compose 變數插值傳入：

```yaml
volumes:
  - ${OPENCODE_DEV_WORKSPACE:?Set OPENCODE_DEV_WORKSPACE to the host project path}:/workspace
  - ${OPENCODE_DEV_USER_CONFIG:?Set OPENCODE_DEV_USER_CONFIG to the user opencode-dev config path}:/opencode-dev/user:ro
```

`opencode-dev` script 會把使用者輸入的 path 解析成絕對路徑，確保 project config 目錄存在，依 profile Dockerfile 準備 profile image，然後在執行 Compose 時設定 `OPENCODE_DEV_IMAGE`、`OPENCODE_DEV_WORKSPACE` 與 `OPENCODE_DEV_USER_CONFIG`。base image 由 `compose.env` 固定，environment、volumes、working directory 與 host mapping 都維護在 `docker-compose.yml`。

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
base image       固定在 compose.env
image tag        build/install/update 後寫入 compose.env 與 image.profile
base alias       build/install/update 後指向 localhost/opencode-dev-yuta:base
container name   固定為 opencode-dev-yuta
state volumes    固定為 opencode-home-yuta / opencode-state-yuta
project mount    由 opencode-dev 的 path 參數或 pwd 決定
profile files    由 ~/.opencode-dev-yuta 與 <project>/.opencode-dev-yuta 提供
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

`.devcontainer/docker-compose.yml` 是日常 `opencode-dev` 的主要 container 設定來源。`opencode-dev` 不直接用 `docker run` 啟動 container；它讀取 `.devcontainer/compose.env` 作為固定 base image 來源，必要時先 build profile image，並把實際要執行的 image 與目前專案路徑透過環境變數傳給 Compose：

```bash
OPENCODE_DEV_IMAGE=localhost/opencode-dev-yuta-env:<profile-tag> \
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
bash .devcontainer/scripts/init/init-opencode-dev.sh --uninstall
```

從 shell profile 移除 `opencode-dev` function 區塊，並刪除本工具管理的 install 目錄。

```bash
./admin/build-image.sh
```

從 `.devcontainer/Dockerfile.insecure` build image，依 `.devcontainer/image.profile` 指定的 OpenCode 版號與 env revision tag 成 `localhost/opencode-dev-yuta:<opencode-version>-env.<revision>`，更新 base alias，並輸出 Docker image tar。

```bash
./admin/update-opencode-version.sh
```

只在 release host 上建立暫時 image 解析目前 OpenCode 版本，並寫回 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`。

```bash
./admin/ca/collect-ca.sh
```

嘗試從 Docker Hub、npm、PyPI、Debian apt 與 Microsoft package registry 的 TLS response 收集憑證鏈到 `admin/ca/`。

```bash
./admin/ca/build-ca-image.sh
```

從 `.devcontainer/Dockerfile`（CA 模式）build image。會讀取 `admin/ca/*.crt`，沒有 `.crt` 時停止並提示無法建立。

```bash
bash .devcontainer/scripts/init/install-image.sh .docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

把 image tar 載入本機 Docker。不會修改 repo 內的 `image.profile` 或 `compose.env`。

```bash
bash .devcontainer/scripts/init/install-image.sh
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
