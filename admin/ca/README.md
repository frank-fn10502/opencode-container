# CA 憑證與 CA-aware Image

這個資料夾集中管理 CA 相關流程。一般維護者若只是要先讓內網環境跑起來，使用上一層的 insecure build 即可：

```bash
./admin/build-image.sh
```

只有要建立會信任公司 CA 的 CA-aware image 時，才需要使用這個資料夾。

## 放置 Root CA

把公司提供或從 OS/browser trust store 匯出的 root CA 放在這裡，副檔名必須是 `.crt`：

```text
admin/ca/company-root-ca.crt
admin/ca/company-intermediate-ca.crt
```

`build-ca-image.sh` 會讀取這個資料夾下所有 `.crt`，合併成 bundle，透過 `COMPANY_CA_CERT_B64` 傳給 `.devcontainer/docker/Dockerfile`。

如果這個資料夾沒有任何 `.crt`，`build-ca-image.sh` 會停止，不會建立 CA-aware image。

## 自動收集

可以先嘗試從常見 registry 的 TLS chain 收集 CA：

```bash
./admin/ca/collect-ca.sh
```

`collect-ca.sh` 會使用：

```bash
openssl s_client -connect HOST:PORT -servername HOST -showcerts
```

預設行為：

- 探測 Docker Hub、npm、PyPI、Debian apt、Microsoft package registry。
- 從 TLS handshake response 中保存 `Basic Constraints: CA:TRUE` 的憑證。
- 如果 TLS response 沒有送出 self-signed root CA，會嘗試依照 AIA CA Issuers URL 往上取得 root CA。
- AIA 只支援 `http://` 與 `https://` URL；如果公司憑證只提供 `ldap:///...`，script 會提示無法下載，請從 OS/browser trust store 匯出 root CA，或向 IT 取得 `.crt`。
- 不會把 leaf/server certificate 當成 CA trust anchor。

如果 AIA 也無法取得 root CA，script 會保留已觀察到的 intermediate CA，並提醒仍需從 OS/browser trust store 匯出 root CA，或向 IT 取得 root CA `.crt`。

可以停用 AIA，只保存 TLS response 直接看到的 CA：

```bash
./admin/ca/collect-ca.sh --no-aia
```

除錯用模式：

```bash
./admin/ca/collect-ca.sh --save-chain
./admin/ca/collect-ca.sh --save-leaf
./admin/ca/collect-ca.sh --save-chain-top
```

`--save-leaf` 只適合除錯；leaf/server certificate 通常不是 CA，不應該當成長期信任的 root CA。

## 建立 CA-aware Image

確認 `admin/ca/` 內有 `.crt` 後執行：

```bash
./admin/ca/build-ca-image.sh
```

完成後會輸出：

```text
.docker_imgs/opencode-dev-yuta-<opencode-version>-env.<revision>.tar
```

這個 tar 是公司內網發布包的一部分，不 commit 到 git。
