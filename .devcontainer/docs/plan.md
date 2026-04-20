# 紀錄一些想法

- 需要盡可能的讓安裝與解安裝簡單化, 不要讓本機有太大的負擔.

## User Story
1. 使用者 clone 專案, 執行 init-opencode-dev.sh.
2. 使用者輸入 `opencode-dev` 在這個位置啟動 opencode 的 container
3. 使用 opencode 的功能
4. 關閉 opencode
5. 輪迴 2 ~ 4.
6. 使用者要更新或刪除這個功能, 呼教 xxx script 解除安裝 opencode-dev

## Stage
> 暫時不處理

- 每個 container 中途安裝的套件要如何保留? (暫時保留這個限制)

## ToDo
- 需要先載入公司的 CA
- 需要先處理常見套件的 ssl 應對策略(curl, pip, apt, npm), 還有可能會出現 block 的問題.
- 需要考慮在公司電腦編譯時如何塞入 CA


- TODO base image 需要加入 cmake.

- 在 /home/<user> 資料夾使用 `opencode-dev` 也要正確的識別 .opencode-dev-yuta 是個 user 級別的設定
- 需要提供一個 create 與 copy 的指令
    - 提供一個 template
    - 可以指定 profile  copy 到 project 或者 user?
- 需要提供一些範例讓 AI 可以協助使用者建立客製化的 Dockerfile
    - dockerfile 可能需要拆分步驟, 因為公司網路很容易斷線...
- 需要預設一些 user profile
    - python
    - npm

