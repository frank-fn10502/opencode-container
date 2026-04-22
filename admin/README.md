# opencode-dev Admin

這個資料夾只給維護者使用。一般使用者只需要 `./init.sh` 與 `opencode-dev`，不需要執行這裡的 script。

git 只追蹤 script、設定檔與文件。`.docker_imgs/*.tar` 是公司內網發布包的一部分，不 commit 到 git。

## 版本模型

image 版本由 `.devcontainer/image.profile` 定義：

```sh
IMAGE_REPOSITORY=localhost/opencode-dev-yuta
OPENCODE_VERSION=1.4.7
ENV_REVISION=1
IMAGE_TAG=1.4.7-env.1
OPENCODE_DEV_IMAGE=localhost/opencode-dev-yuta:1.4.7-env.1
VM_REVISION=1
VM_IMAGE_TAG=1.4.7-env.1-vm.1
OPENCODE_VM_IMAGE=localhost/opencode-dev-yuta:1.4.7-env.1-vm.1
```

`OPENCODE_VERSION` 是 Dockerfile 會安裝的 OpenCode 版本。

`ENV_REVISION` 是 opencode-dev default/base 環境 revision。同一個 OpenCode 版本下，只要 base image 內容有影響使用者的變更，就遞增它。例如新增 apt 套件、改 shell/PATH、改預設 config、改 CA 行為。

`VM_REVISION` 是 opencode-vm 環境 revision。只調整常駐 VM 需要的套件，例如 ssh、tmux、rsync、process/network tools 時，遞增 `VM_REVISION`。`build-image.sh` 會在 base image 完成後自動 build 對應的 VM image。

非必要不要執行 `update-opencode-version.sh`。大多數維護工作只需要調整 Dockerfile 或設定，必要時 bump `ENV_REVISION`，然後執行 `build-image.sh`。

預設 build 採用 `.devcontainer/Dockerfile.insecure`。內網環境先求能跑，再視需要建立 CA-aware image。

## 常見流程

只改 default/base 環境，但 OpenCode 版本不變：

```bash
# 手動增加 .devcontainer/image.profile 的 ENV_REVISION
./admin/build-image.sh
```

需要解析目前可安裝的 OpenCode 版本時，只在版本更新主機執行：

```bash
./admin/update-opencode-version.sh
./admin/build-image.sh
```

`update-opencode-version.sh` 會用 `OPENCODE_VERSION=latest` 建立暫時 image，讀取 `opencode --version`，再寫回 `.devcontainer/image.profile`。其他主機不需要執行這個步驟。

公司內部只需要一台 build 主機執行 `build-image.sh` 或 `build-ca-image.sh`，產生 `.docker_imgs/` 下的 base 與 VM tar。發布時把 repo 內容與 `.docker_imgs/*.tar` 一起打包成內網發布包；git 仍然只 commit script、設定檔與文件。

如果公司需要匯入 CA，相關流程集中在 [ca/README.md](ca/README.md)。常用入口：

```bash
./admin/ca/collect-ca.sh
./admin/ca/build-ca-image.sh
```

一般內網預設 build 已經採用全面放寬 SSL 檢查的 insecure Dockerfile：

```bash
./admin/build-image.sh
```

build 成功後會輸出本機發布用 tar：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>-vm.<vm-revision>.tar
```

請 commit 有變更的 script、設定檔與文件，例如：

```text
.devcontainer/image.profile
admin/
.devcontainer/scripts/
.devcontainer/docs/
```

不要 commit `.docker_imgs/opencode-dev-yuta-*.tar`。這些檔案只放進公司內網發布包。

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
