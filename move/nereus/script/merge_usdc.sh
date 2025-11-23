#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. 切換目錄
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" || exit

# 2. 讀取 .env
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo -e "${RED}❌ 找不到 .env 檔案${NC}"
    exit 1
fi

echo -e "${BLUE}=== 開始 USDC 合併程序 (PTB + Comma Fix) ===${NC}"

COIN_TYPE="${PACKAGE_ID}::usdc::USDC"
echo "目標 Coin Type: $COIN_TYPE"

# 3. 抓取 Coin
echo -e "${YELLOW}正在查詢鏈上 Coin 列表...${NC}"
RAW_BALANCE=$(sui client balance --coin-type $COIN_TYPE --json 2>&1)
CLEAN_BALANCE=$(echo "$RAW_BALANCE" | grep -v "^\[warning\]")

if [ -z "$CLEAN_BALANCE" ] || [ "$CLEAN_BALANCE" == "null" ]; then
    echo -e "${RED}❌ 無法讀取餘額或餘額為空。${NC}"
    exit 1
fi

# 解析 ID 列表
ID_LIST_STRING=$(echo "$CLEAN_BALANCE" | jq -r '.. | objects? | select(has("coinObjectId")) | .coinObjectId')
COIN_IDS=($ID_LIST_STRING)
COIN_COUNT=${#COIN_IDS[@]}

echo "--------------------------------"
echo -e "找到 USDC 物件數量: ${GREEN}$COIN_COUNT${NC}"

if [ "$COIN_COUNT" -le 1 ]; then
    echo "✅ 數量為 0 或 1，無需合併。"
    exit 0
fi

# 4. 準備合併參數
PRIMARY_COIN=${COIN_IDS[0]}
SOURCE_COINS=("${COIN_IDS[@]:1}")

echo "主 Coin (接收者): $PRIMARY_COIN"
echo "將合併其餘 ${#SOURCE_COINS[@]} 顆 Coin..."

# ========================================================
# 關鍵修正：加上逗號 (Comma)
# 格式需求: "[@obj1,@obj2,@obj3]"
# ========================================================
PTB_ARRAY_STRING="["
for coin in "${SOURCE_COINS[@]}"; do
    # 每個 ID 後面加上逗號
    PTB_ARRAY_STRING="${PTB_ARRAY_STRING}@${coin},"
done

# 移除最後一個多餘的逗號
PTB_ARRAY_STRING="${PTB_ARRAY_STRING%,}"
# 補上右括號
PTB_ARRAY_STRING="${PTB_ARRAY_STRING}]"

echo "PTB 參數陣列: $PTB_ARRAY_STRING"
echo -e "${YELLOW}正在發送 PTB 合併交易...${NC}"

# 5. 執行 PTB
# 注意：這裡的引號非常重要 "$PTB_ARRAY_STRING"
RAW_RES=$(sui client ptb \
    --merge-coins @$PRIMARY_COIN "$PTB_ARRAY_STRING" \
    --gas-budget 500000000 \
    --json 2>&1)

# 清洗輸出
CLEAN_RES=$(echo "$RAW_RES" | grep -v "^\[warning\]")
STATUS=$(echo "$CLEAN_RES" | jq -r '.effects.status.status')

if [[ "$STATUS" == "success" ]]; then
    DIGEST=$(echo "$CLEAN_RES" | jq -r '.digest')
    echo -e "${GREEN}✅ 合併成功！${NC}"
    echo "交易 Digest: $DIGEST"
    echo "所有資金已集中到: $PRIMARY_COIN"
else
    echo -e "${RED}❌ 合併失敗！${NC}"
    echo "--------------------------------"
    echo "錯誤原因 / 原始回傳:"
    PARSED_ERROR=$(echo "$CLEAN_RES" | jq -r '.effects.status // empty' 2>/dev/null)
    
    if [ -n "$PARSED_ERROR" ]; then
        echo "$PARSED_ERROR"
    else
        echo "$CLEAN_RES"
    fi
fi