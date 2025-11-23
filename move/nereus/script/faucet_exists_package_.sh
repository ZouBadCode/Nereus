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
# 4. 處理 USDC (模擬)
# ==========================================
# 嘗試從之前的發布結果或 .env 獲取 TreasuryCap，如果沒有則跳過
if [ -z "$USDC_TREASURY_ID" ]; then
    # 嘗試從環境變數讀取，如果沒有則提示
    echo "⚠️ 未檢測到 USDC_TREASURY_ID，跳過鑄造測試幣。"
else
    echo "USDC Treasury ID: $USDC_TREASURY_ID"
    echo -e "${GREEN}鑄造 1000 USDC 給自己...${NC}"
    
    # 修改處：將輸出存入變數 MINT_RES，並過濾掉警告訊息 (stderr)
    MINT_RES=$(sui client call \
        --package $PACKAGE_ID \
        --module usdc \
        --function faucet \
        --args $USDC_TREASURY_ID \
        --gas-budget $GAS_BUDGET \
        --json 2> /dev/null)

    # 檢查交易狀態
    if [[ $(echo "$MINT_RES" | jq -r '.effects.status.status') == "success" ]]; then
        DIGEST=$(echo "$MINT_RES" | jq -r '.digest')
        # 嘗試抓取新生成的 Coin Object ID (如果是 mint，通常會有 created 或 mutated)
        NEW_COIN=$(echo "$MINT_RES" | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("::usdc::USDC"))) | .objectId' | head -n 1)
        
        echo -e "${GREEN}✅ 鑄造成功！${NC}"
        echo "交易 ID (Digest): $DIGEST"
        if [ ! -z "$NEW_COIN" ]; then
            echo "新鑄造的 USDC Object ID: $NEW_COIN"
        fi
    else
        echo -e "${RED}❌ 鑄造失敗！詳細錯誤如下：${NC}"
        # 如果失敗，印出完整 JSON 以便除錯
        echo "$MINT_RES"
    fi
fi