# OpenCode Dev Container Design

這份文件記錄目前定型的 `opencode-dev` Docker 使用模型。目標是讓使用者不用在 macOS、Windows、WSL 或 Linux 本機安裝 OpenCode，只要能執行 Docker，就能用同一個 image 操作自己的專案。

## 設計目標

- 使用同一個 `localhost/opencode-dev:local` image 提供 OpenCode 與基本開發工具。
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
./.devcontainer/scripts/init-opencode-dev.sh
```

安裝後，使用者開新 shell 就能直接執行：

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
~/.local/bin/opencode-dev-yuta/scripts/init-opencode-dev.sh
~/.local/bin/opencode-dev-yuta/scripts/opencode-dev.sh
~/.local/bin/opencode-dev-yuta/config/opencode.json
```

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
  -> docker run --rm -it --name opencode-dev-yuta ...
  -> bind mount 目標目錄到 /workspace
  -> 執行 opencode
  -> opencode 結束後 container 自動移除
```

這個模型避免了 running container 無法新增 bind mount 的 Docker 限制。每次啟動都可以針對不同 host path 建立新的 bind mount，同時仍透過 named volumes 保留 OpenCode 登入狀態。

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
opencode-home-yuta  -> /home/node/.local/share/opencode
opencode-state-yuta -> /home/node/.local/state
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
image name       固定由 repo 維護
container name   固定為 opencode-dev-yuta
state volumes    固定為 opencode-home-yuta / opencode-state-yuta
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
bash .devcontainer/scripts/init-opencode-dev.sh
```

安裝 `opencode-dev` runtime 到 `~/.local/bin/opencode-dev-yuta/`，並把 `opencode-dev` function 註冊到 shell profile。

```bash
bash .devcontainer/scripts/init-opencode-dev.sh --uninstall
```

從 shell profile 移除 `opencode-dev` function 區塊，並刪除本工具管理的 install 目錄。

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
