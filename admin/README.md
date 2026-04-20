# opencode-dev Admin

這個資料夾只給維護者使用。一般使用者只需要 `./init.sh` 與 `opencode-dev`，不需要執行這裡的 script。

## 版本模型

image 版本由 `.devcontainer/image.profile` 定義：

```sh
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
OPENCODE_VERSION="1.4.7"
ENV_REVISION="1"
IMAGE_TAG="${OPENCODE_VERSION}-env.${ENV_REVISION}"
```

`OPENCODE_VERSION` 是 Dockerfile 會安裝的 OpenCode 版本。

`ENV_REVISION` 是 opencode-dev default/base 環境 revision。同一個 OpenCode 版本下，只要 base image 內容有影響使用者的變更，就遞增它。例如新增 apt 套件、改 shell/PATH、改預設 config、改 CA 行為。

非必要不要執行 `update-opencode-version.sh`。大多數維護工作只需要調整 Dockerfile 或設定，必要時 bump `ENV_REVISION`，然後執行 `build-image.sh`。

## 常見流程

只改 default/base 環境，但 OpenCode 版本不變：

```bash
# 手動增加 .devcontainer/image.profile 的 ENV_REVISION
./admin/build-image.sh
```

需要解析目前可安裝的 OpenCode 版本時，才執行：

```bash
./admin/update-opencode-version.sh
./admin/build-image.sh
```

`update-opencode-version.sh` 會用 `OPENCODE_VERSION=latest` 建立暫時 image，讀取 `opencode --version`，再寫回 `.devcontainer/image.profile` 與 `.devcontainer/compose.env`。其他主機不需要執行這個步驟。

如果公司需要匯入 CA：

```bash
./admin/build-image.sh \
  --dockerfile Dockerfile \
  --build-arg COMPANY_CA_CERT_B64="$(base64 < company-ca.crt | tr -d '\n')"
```

如果需要全面放寬 SSL 檢查：

```bash
./admin/build-image.sh --dockerfile Dockerfile.insecure
```

build 成功後會輸出：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

請將以下內容一起 commit：

```text
.devcontainer/image.profile
.devcontainer/compose.env
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

## Docker Hub

推送 image：

```bash
./admin/push-dockerhub.sh 1.4.7-env.1
./admin/push-dockerhub.sh 1.4.7-env.1 --latest
```

從 Docker Hub 下載指定版本並重新打包 tar：

```bash
./admin/pull-and-pack-image.sh 1.4.7-env.1
```
