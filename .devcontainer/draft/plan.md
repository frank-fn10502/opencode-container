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
- TODO 或許需要建立一個 ~/.agents 與 opencode-dev 環境當中的 ~/.xxx, 這樣或許可以使用一份 outline 讓主機與container兩者的 AI 可以看到一致的文件/command/skills
    - 這樣 copilot 或許可以撰寫 script 呼叫 opencode? 或許可以因此實作出初階的 agent flow?
- TODO 要研究是否需要安裝 agent browser?
- TODO 還沒有正式的測試新版的 base image 是否真的可以觸發 custom profile 的 Yes/No.

- TODO 如何正確且安全的移除多餘的 container? 
- TODO opencode 似乎可以外掛 MCP 與 tools.
    - 可以建立一個搜索內部文件庫的 tools