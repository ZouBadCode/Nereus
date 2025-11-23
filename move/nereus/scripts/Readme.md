# Nereus Market CLI Tools

這是一套用於與 Nereus 預測市場 (Sui Move 合約) 進行互動的自動化 Shell 腳本工具。它允許開發者在 Testnet 上快速部署合約、領取測試幣、掛單與查詢訂單。

## 📋 前置需求 (Prerequisites)

在開始之前，請確保您的電腦已安裝以下工具：

1.  **Sui CLI**: [安裝指南](https://docs.sui.io/guides/developer/getting-started/sui-install)
2.  **jq**: 用於處理 JSON 輸出 (腳本核心依賴)。
    - macOS: `brew install jq`
    - Linux: `sudo apt-get install jq`
3.  **Node.js & npm**: 用於解碼鏈上 BCS 數據 (選項 5 必需)。

---

## ⚙️ 安裝與設定 (Setup)

**⚠️ 重要提示：使用「選項 5 (查詢訂單)」前必做**

互動腳本中的 **選項 5 (查詢買賣單)** 需要使用 Node.js 來解碼 Sui 的二進位數據 (BCS)。請務必在專案根目錄下執行以下指令來安裝依賴：

```bash
# 1. 進入專案根目錄 (包含 Move.toml 的目錄)
# 請根據您的實際路徑調整
cd ./nereus/move/nereus/script
or
cd ./script

# 2. 初始化 npm (若尚未初始化)
npm init -y

# 3. 安裝 Sui BCS 套件 (建議指定版本以確保相容性)
npm install @mysten/bcs
```

> **注意**：如果您沒有執行上述步驟，使用選項 5 時會出現 `Cannot find module` 或 `decode_order.js` 相關錯誤。

---

## 🚀 使用流程

請依照以下順序操作：

### 1. 部署合約 (Deploy)

此腳本會自動編譯 Move 合約、發佈至 Testnet、初始化 Oracle 與 Market，並將生成的 Object ID 儲存至 `.env` 檔案中。

```bash
# 執行部署腳本
./scripts/deploy_testnet.sh
```

- **輸出**：成功後，根目錄會出現一個 `.env` 檔案，內含 `PACKAGE_ID`, `MARKET_ID` 等資訊。
- **自動領水**：此腳本執行過程中，會自動為部署者鑄造初始的 USDC 測試幣。

### 2. 領取更多測試代幣 (Faucet)

若您需要更多代幣來進行測試：

1.  **SUI (Gas 費)**:
    - 請至 Sui Discord 的 `#testnet-faucet` 頻道領取。
    - 或在終端機執行：
      ```bash
      sui client faucet
      ```
2.  **USDC (交易用)**:
    - 如果您有專用的 `faucet_exists_package.sh` 腳本，請執行它。
    - 或者，您可以手動呼叫 `mint` 函數（需使用部署時獲得的 TreasuryCap）。

### 3. 整理錢包 (Merge Coins) - _推薦_

如果您多次執行部署或多次領取 USDC，錢包內會有大量零散的 USDC 物件。這會導致掛單時因選擇到餘額不足的物件而失敗。

**強烈建議在互動前執行此步驟：**

```bash
# 執行合併腳本
./scripts/merge_usdc.sh
```

### 4. 互動操作 (Interact)

這是主要的操作介面，包含查詢餘額、存款、掛單與查詢訂單簿。

```bash
# 執行互動腳本
./scripts/interact_market.sh
```

#### 功能選單說明：

- **1. 查詢 USDC 餘額 (Balance)**
  - 顯示您錢包中所有 USDC 物件的 ID 與金額。
- **2. 存入 USDC 到 Market (Deposit)**
  - 將 USDC 存入市場的 Vault。
  - 腳本會自動幫您執行 `Split Coin`，您只需輸入想要存入的金額。
- **3. 掛買單 (Place Order - Buy YES)**
  - 發送交易建立訂單 (Create Order) 並提交 (Post Order)。
  - 使用 PTB (Programmable Transaction Block) 技術，將創建與提交合併為一筆交易。
- **4. 查看 Market 狀態**
  - 顯示市場的基本資訊，如 `active_orders` 的總數量 (Size) 和 Table ID。
- **5. 查詢買賣單 (Bids YES / Asks NO)**
  - **⚠️ 需完成上方的 npm 安裝步驟**。
  - 讀取鏈上訂單，並透過 Node.js 解碼 BCS 數據，顯示完整的 Maker 地址、價格與數量。

---

## 🛠 疑難排解 (Troubleshooting)

**Q: 執行腳本時出現 `Permission denied`？**
A: 請賦予腳本執行權限：

```bash
chmod +x scripts/*.sh
```

**Q: 選項 5 出現 `Error: Cannot find module ... decode_order.js`？**
A: 請確認您的資料夾名稱是否為 **`scripts`** (複數)。如果您的資料夾叫 `script` (單數)，請改名：

```bash
mv script scripts
```

並且確保您已在專案根目錄執行了 `npm install @mysten/bcs`。

**Q: 出現 `parse error: Invalid numeric literal`？**
A: 這通常是因為 Sui CLI 輸出了警告訊息（如版本不匹配）干擾了 JSON 解析。目前的腳本已內建 `clean_output` 函數來過濾這些雜訊。如果仍有問題，請檢查您的 `sui --version` 是否過舊，建議更新至最新版。
