# 紀錄一些想法

- 需要盡可能的讓安裝與解安裝簡單化, 不要讓本機有太大的負擔.

## User Story
1. 使用者 clone 專案, 執行 init-opencode-dev.sh.
2. 使用者輸入 `opencode-dev` 在這個位置啟動 opencode 的 container
3. 使用 opencode 的功能
4. 關閉 opencode
5. 輪迴 2 ~ 4.
6. 使用者要更新或刪除這個功能, 呼教 xxx script 解除安裝 opencode-dev

### 使用者使用 profile 建立 opencode 環境
1. 編輯 user profile or 在專案資料夾編輯 proj profile
    - 使用外部 IDE/AI 直接編輯 Docker.<profilename> 檔案
    - 直接用 opencode-dev 開啟資料夾, 並指示 opencode 編輯 .opencode-dev-yuta 資料夾
    - 使用 opencode-dev 開啟 $HOME, 修改 user profile
2. `opencode-dev profile set <prifilename>`
    - `opencode-dev profile status` 查看現在的狀態
3. `opencode-dev` 開啟 opencode 環境.

## ToDo
- 需要先處理常見套件的 ssl 應對策略(curl, pip, apt, npm), 還有可能會出現 block 的問題.
- 需要建立 instruct 或 skill.
    - 還需要進一步的測試, 要如何讓 主機 與 opencode-dev 內部有幾乎相似的 AI 體驗?