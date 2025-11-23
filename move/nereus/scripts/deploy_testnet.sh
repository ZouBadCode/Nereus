#!/bin/bash

# 設定顏色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ==========================================
# 自動定位並切換到專案根目錄
# ==========================================
# 取得腳本所在的目錄 (即 .../nereus/scripts)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 切換到上一層目錄 (即專案根目錄 .../nereus)
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" || exit

echo -e "${BLUE}工作目錄已切換至: $(pwd)${NC}"

# 檢查 Move.toml 是否存在
if [ ! -f "Move.toml" ]; then
    echo -e "${RED}錯誤: 在此目錄找不到 Move.toml。請確認目錄結構。${NC}"
    exit 1
fi
# ==========================================

echo -e "${BLUE}=== 開始部署 Nereus 到 Sui Testnet ===${NC}"

# 檢查 Gas
ACTIVE_ADDR=$(sui client active-address)
echo "當前地址: $ACTIVE_ADDR"

# 設定 budget 1 SUI
GAS_BUDGET=100000000
echo "當前地址: $GAS_BUDGET"

# 1. 發佈 Package
echo -e "${GREEN}正在發佈 Package...${NC}"
# 注意：--skip-dependency-verification 用於加速，生產環境建議移除
PUBLISH_RES=$(sui client publish --gas-budget $GAS_BUDGET --skip-dependency-verification --json)

# 檢查發佈是否成功
if [[ $(echo $PUBLISH_RES | jq -r '.effects.status.status') == "failure" ]]; then
    echo "❌ 發佈失敗！"
    echo $PUBLISH_RES
    exit 1
fi

DIGEST=$(echo "$PUBLISH_RES" | jq -r '.digest')

# 解析 Package ID ＆ TreasuryCap ID
PACKAGE_ID=$(echo $PUBLISH_RES | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
USDC_TREASURY_ID=$(echo $PUBLISH_RES | jq -r '.objectChanges[] | select(.objectType | contains("::usdc::TreasuryCapManager")) | .objectId')

echo "✅ Package ID: $PACKAGE_ID"
echo "✅ Treasury Manager ID: $USDC_TREASURY_ID"

# ==========================================
# 2 合併創建 Config 與 Truth Oracle Holder (使用單一 PTB)
# ==========================================
echo -e "${GREEN}正在通過 PTB 同時創建 Oracle Config 與 Holder...${NC}"

# 模擬參數
CODE_HASH="\"0x12345\""
BLOB_ID="\"blob_test_v1\""

# PTB 邏輯解析:
# 1. create_config -> 產出被指派為 'config'
# 2. create_truth_oracle_holder (傳入 'config' 變數) -> 產出被指派為 'holder'
# 3. transfer-objects -> 將 [config, holder] 一起轉給 @$ACTIVE_ADDR
# 注意：在 PTB 內部引用上一步的結果變數時，不需要加 @，直接用變數名即可
PTB_RES=$(sui client ptb \
    --move-call $PACKAGE_ID::truth_oracle::create_config "$CODE_HASH" "$BLOB_ID" \
    --assign config \
    --move-call $PACKAGE_ID::truth_oracle::create_truth_oracle_holder config \
    --assign holder \
    --transfer-objects "[config, holder]" "@$ACTIVE_ADDR" \
    --gas-budget $GAS_BUDGET \
    --json)

# 檢查執行結果
if echo "$PTB_RES" | grep -q "error"; then
    echo -e "${RED}❌ PTB 執行失敗${NC}"
    echo "$PTB_RES"
    exit 1
fi

# ==========================================
# 2.1 解析回傳值 (從同一筆交易中提取兩個 ID)
# ==========================================

# 提取 Config ID
CONFIG_ID=$(echo $PTB_RES | jq -r '.objectChanges[] | select(.objectType | contains("::OracleConfig")) | .objectId')

# 提取 Holder ID (即 ORACLE_ID)
ORACLE_ID=$(echo $PTB_RES | jq -r '.objectChanges[] | select(.objectType | contains("::TruthOracleHolder")) | .objectId')

if [ -z "$CONFIG_ID" ] || [ -z "$ORACLE_ID" ]; then
    echo -e "${RED}❌ 無法從 PTB 結果中解析 ID${NC}"
    echo "$PTB_RES"
    exit 1
fi

echo "✅ Config ID: $CONFIG_ID"
echo "✅ Truth Oracle Holder ID: $ORACLE_ID"

# 3. 創建市場 (Create Market)
# 參數: OracleHolder, Question(string), Description(string), EndTime(u64), SettlementTime(u64)
# 注意：String 在 CLI 需轉為 bytes 或直接傳字串 (視 SDK 版本，目前 CLI 支援字串)
echo -e "${GREEN}正在創建 Market...${NC}"
MARKET_TX=$(sui client call \
    --package $PACKAGE_ID \
    --module market \
    --function create_market \
    --args $ORACLE_ID "ETH > 3000?" "Ethereum Price Prediction" 1735689600 1735776000 \
    --gas-budget $GAS_BUDGET \
    --json)

MARKET_ID=$(echo $MARKET_TX | jq -r '.objectChanges[] | select(.objectType | contains("::market::Market")) | .objectId')
echo "✅ Market ID: $MARKET_ID"

# 4. 處理 USDC (模擬)
# 您的測試使用了 nereus::usdc。如果該模組有 init 函數產生 TreasuryCap，我們需要找到它來鑄造代幣。
# 這裡假設發佈 Package 時產生了 TreasuryCap<USDC>

if [ -z "$USDC_TREASURY_ID" ]; then
    echo "⚠️ 找不到 USDC TreasuryCap，可能是因為它不是在 init 中創建的，或是 Shared Object。"
else
    echo "✅ USDC Treasury ID: $USDC_TREASURY_ID"
    
    # 鑄造 USDC 給自己
    echo -e "${GREEN}鑄造 1000 USDC 給自己...${NC}"
    sui client call \
        --package $PACKAGE_ID \
        --module usdc \
        --function mint \
        --args $USDC_TREASURY_ID 1000000000000 $ACTIVE_ADDR \
        --gas-budget $GAS_BUDGET > /dev/null
fi

# 5. 儲存變數到 .env 檔案
echo -e "${BLUE}=== 儲存設定到 .env ===${NC}"
cat <<EOT > .env
PACKAGE_ID=$PACKAGE_ID
CONFIG_ID=$CONFIG_ID
ORACLE_ID=$ORACLE_ID
MARKET_ID=$MARKET_ID
USDC_TREASURY_ID=$USDC_TREASURY_ID
EOT

echo "部署完成！變數已存入 .env"