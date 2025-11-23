#!/bin/bash

# 設定顏色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ==========================================
# 自動定位並切換到專案根目錄
# ==========================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" || exit

echo -e "${BLUE}工作目錄已切換至: $(pwd)${NC}"

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
GAS_BUDGET=1000000000

# 讀取 .env (確保有 PACKAGE_ID)
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo "❌ 找不到 .env 檔案，請先執行發布合約的腳本 (確保 PACKAGE_ID 存在)"
    exit 1
fi

echo "Package: $PACKAGE_ID"

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

# ==========================================
# 3. 創建市場 (Create Market)
# ==========================================
echo -e "${GREEN}正在創建 Market...${NC}"

# 時間參數
START_TIME=1735689600
END_TIME=1735776000

MARKET_TX=$(sui client call \
    --package $PACKAGE_ID \
    --module market \
    --function create_market \
    --args $ORACLE_ID "ETH > 3000?" "Ethereum Price Prediction" $START_TIME $END_TIME \
    --gas-budget $GAS_BUDGET \
    --json)

MARKET_ID=$(echo $MARKET_TX | jq -r '.objectChanges[] | select(.objectType | contains("::market::Market")) | .objectId')

if [ -z "$MARKET_ID" ] || [ "$MARKET_ID" == "null" ]; then
    echo -e "${RED}❌ 創建 Market 失敗${NC}"
    echo "$MARKET_TX"
    exit 1
fi

echo "✅ Market ID: $MARKET_ID"

# ==========================================
# 4. 處理 USDC (模擬)
# ==========================================
# 嘗試從之前的發布結果或 .env 獲取 TreasuryCap，如果沒有則跳過
if [ -z "$USDC_TREASURY_ID" ]; then
    # 嘗試從環境變數讀取，如果沒有則提示
    echo "⚠️ 未檢測到 USDC_TREASURY_ID，跳過鑄造測試幣。"
else
    echo "✅ USDC Treasury ID: $USDC_TREASURY_ID"
    echo -e "${GREEN}鑄造 1000 USDC 給自己...${NC}"
    sui client call \
        --package $PACKAGE_ID \
        --module usdc \
        --function mint \
        --args $USDC_TREASURY_ID 1000000000000 $ACTIVE_ADDR \
        --gas-budget $GAS_BUDGET \
        --json > /dev/null
fi

# ==========================================
# 5. 更新 .env 檔案
# ==========================================
echo -e "${BLUE}=== 更新設定到 .env ===${NC}"

# 使用 sed 或重寫方式更新變數，保留 PACKAGE_ID
# 這裡簡單起見，重新寫入關鍵變數
cat <<EOT > .env
PACKAGE_ID=$PACKAGE_ID
CONFIG_ID=$CONFIG_ID
ORACLE_ID=$ORACLE_ID
MARKET_ID=$MARKET_ID
USDC_TREASURY_ID=$USDC_TREASURY_ID
EOT

echo -e "${GREEN}部署完成！變數已更新至 .env${NC}"