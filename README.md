# opencode-dev

`opencode-dev` 讓使用者不用在主機直接安裝 OpenCode。它會用本機 Docker image 啟動 container，並把目前資料夾或指定專案資料夾掛到 container 的 `/workspace`。

## 需求

- Docker
- 已取得公司提供的 Docker image tar

image tar 預設放在專案根目錄：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>.tar
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

指定專案資料夾：

```bash
opencode-dev /path/to/project
opencode-dev ../other-project
```

如果指定的資料夾不存在，script 會建立它。每次啟動只會把該資料夾掛到 container 的 `/workspace`。

容器預設使用 `opencode` 使用者。啟動時會自動檢查 `/workspace` 的擁有者 UID/GID；若與 `opencode` 不一致，entrypoint 會在容器內動態調整 `opencode` 的 UID/GID 後再執行主程式，降低 host bind mount 的權限衝突。

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
opencode-dev --uninstall
```

移除 shell profile 中的 `opencode-dev` 區塊，並刪除 `~/.local/bin/opencode-dev-yuta/` 中由本工具安裝的 runtime。

解除安裝不會刪除 Docker image，也不會刪除 OpenCode 的 Docker volumes，避免誤刪登入狀態與 session data。

## 更新 Image

更新時使用和初次安裝相同的入口：

```bash
./init.sh
```

發佈新版時，維護者會執行 `build-image.sh`，它會自動更新 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`，並把 image tar 輸出到 `.docker_imgs/`。這些變更會一併 commit 到 repo。

使用者只要把對應 tar 放到：

```text
.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar
```

然後重新執行 `./init.sh`。

`./init.sh` 會：

- 檢查本機是否已有 `.devcontainer/image.profile` 指定的 exact image。
- 如果沒有，從 `.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar` 載入。
- 重新部署 `~/.local/bin/opencode-dev-yuta/` 裡的 runtime scripts。
- 保留使用者既有的 Docker volumes 與登入狀態。

## 維護者

從預設 CA 模式 Dockerfile build 並打包 image tar：

```bash
bash .devcontainer/scripts/build-image.sh
```

如果公司需要匯入 CA，使用 build-arg 傳入 base64：

```bash
bash .devcontainer/scripts/build-image.sh \
	--dockerfile Dockerfile \
	--build-arg COMPANY_CA_CERT_B64="$(base64 < company-ca.crt | tr -d '\n')"
```

如果要使用全面放寬 SSL 檢查的模式（apt/npm/pip/curl/wget），改用 insecure 版本：

```bash
bash .devcontainer/scripts/build-image.sh --dockerfile Dockerfile.insecure
```

`build-image.sh` 會自動更新 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`，並輸出 tar 到：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>.tar
```

完成後請將 `image.profile`、`compose.env` 與 tar 一併 commit，讓其他使用者可以直接透過 `./init.sh` 安裝新版。

更完整的設計細節在 [.devcontainer/docs/README.md](.devcontainer/docs/README.md)。測試工具說明在 [test_opencode/README.md](test_opencode/README.md)。

推送 image 到 Docker Hub（例如 `frank10502/opencode-dev-yuta`）可用 `.devcontainer/scripts/` 下的 helper：

```bash
./.devcontainer/scripts/push-dockerhub.sh 1.4.7
./.devcontainer/scripts/push-dockerhub.sh 1.4.7 --latest
```

它會把本機 `localhost/opencode-dev-yuta:<tag>`（若 `.devcontainer/image.profile` 有 `IMAGE_REPOSITORY` 會自動套用）轉成 Docker Hub repo `frank10502/opencode-dev-yuta:<tag>` 並推送。
