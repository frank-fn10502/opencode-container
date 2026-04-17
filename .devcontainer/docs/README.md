# OpenCode Dev Container Design

這份文件記錄目前定型的 `opencode-dev` Docker 使用模型。目標是讓使用者不用在 macOS、Windows、WSL 或 Linux 本機安裝 OpenCode，只要能執行 Docker，就能用同一個 image 操作自己的專案。

## 設計目標

- 使用同一個 `localhost/opencode-dev:local` image 提供 OpenCode 與基本開發工具。
- 使用者不需要修改 Compose 或 `.env` 設定。
- 每次啟動時，把目標專案目錄 bind mount 到 container 的 `/workspace`。
- 如果沒有指定目標目錄，就使用執行 `opencode-dev` 時的目前 `pwd`。
- OpenCode 的 OAuth、session、logs 和 runtime state 放在 Docker named volumes，不寫入專案目錄。
- 同一時間只允許一個名為 `opencode-dev` 的 container。

## 使用模型

日常使用入口是：

```bash
opencode-dev
```

這會把目前目錄掛到 container 內：

```text
host:      $(pwd)
container: /workspace
```

也可以指定任意專案目錄：

```bash
opencode-dev /path/to/project
opencode-dev ../other-project
```

此時掛載關係是：

```text
host:      /path/to/project
container: /workspace
```

container 內的 OpenCode 永遠以 `/workspace` 作為專案根目錄。使用者要切換專案時，不需要修改設定；只要在 host 上切換目錄或指定不同 path，再重新執行 `opencode-dev`。

## Container 生命週期

`opencode-dev` 採用短生命週期 container：

```text
opencode-dev 啟動
  -> docker run --rm -it --name opencode-dev ...
  -> bind mount 目標目錄到 /workspace
  -> 執行 opencode
  -> opencode 結束後 container 自動移除
```

這個模型避免了 running container 無法新增 bind mount 的 Docker 限制。每次啟動都可以針對不同 host path 建立新的 bind mount，同時仍透過 named volumes 保留 OpenCode 登入狀態。

## 單 Container 限制

腳本固定使用：

```text
container name: opencode-dev
```

啟動前會檢查是否已經有同名 container：

- 如果沒有，直接啟動新的短生命週期 container。
- 如果有，詢問使用者是否停止並移除既有 container。
- 如果使用者拒絕，腳本結束，不碰既有 container。

這個限制讓行為保持明確：同一時間只有一個 `opencode-dev` container 操作主機檔案，避免多個 container 同時共用 OpenCode state 或同時操作專案造成混亂。

## State 與 OAuth

OpenCode state 固定使用兩個 Docker named volumes：

```text
opencode-home  -> /home/node/.local/share/opencode
opencode-state -> /home/node/.local/state
```

這些 volumes 是每個使用者自己的本機資料，會保留：

- OAuth credential，例如 GitHub Copilot login
- OpenCode session data
- logs
- prompt history
- 其他 runtime state

container 使用 `--rm` 沒有問題，因為 container 本身是可丟棄的；登入狀態與 session state 不放在 container filesystem，而是放在 named volumes。

不要刪除這兩個 volumes，否則 OpenCode 需要重新登入或重建 state：

```bash
docker volume rm opencode-home opencode-state
```

## 為什麼不使用 .env

目前定型設計不使用 `.env`。原因是日常使用者不需要修改 container 拓樸：

```text
image name       固定由 repo 維護
container name   固定為 opencode-dev
state volumes    固定為 opencode-home / opencode-state
project mount    由 opencode-dev 的 path 參數或 pwd 決定
```

若需要調整 image、volume、Compose 或 OpenCode config，由維護者直接修改 repo 內的腳本或 Compose 設定即可。一般使用者只需要：

```bash
cd /path/to/project
opencode-dev
```

或：

```bash
opencode-dev /path/to/project
```

## 與 Compose 的關係

`.devcontainer/compose.yaml` 保留給 VS Code Dev Containers、手動除錯和既有 runner 使用。日常 `opencode-dev` 指令不依賴 Compose，而是直接呼叫 `docker run`，因為這樣可以在每次啟動時掛載任意 host path。

如果使用 Compose 啟動 `opencode` service，該 service 仍會掛載這個 repo 到 `/workspace`。這不是日常「任意專案 path」入口；日常入口應使用 `opencode-dev`。

## 指令摘要

```bash
opencode-dev
```

掛載目前目錄到 `/workspace` 並執行 OpenCode。

```bash
opencode-dev /path/to/project
```

掛載指定目錄到 `/workspace` 並執行 OpenCode。

```bash
opencode-dev shell /path/to/project
```

掛載指定目錄到 `/workspace` 並開啟 bash。

```bash
opencode-dev -- --help
```

掛載目前目錄到 `/workspace`，並把 `--help` 傳給 `opencode`。

```bash
opencode-dev status
opencode-dev stop
```

查看、停止並移除現有 `opencode-dev` container。
