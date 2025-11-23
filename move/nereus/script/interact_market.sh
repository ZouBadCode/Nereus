#!/bin/bash

# 1. 切換到專案根目錄
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" || exit

# 2. 現在可以安全地讀取根目錄下的 .env
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo "❌ 找不到 .env 檔案，請先執行 deploy_testnet.sh"
    exit 1
fi

# 讀取 .env
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo "❌ 找不到 .env 檔案，請先執行 deploy_testnet.sh"
    exit 1
fi

GREEN='\033[0;32m'
NC='\033[0m'

echo "Package: $PACKAGE_ID"
echo "Market:  $MARKET_ID"

# 選擇操作
echo "請選擇操作:"
echo "1. 查詢 USDC 餘額"
echo "2. 存入 USDC 到 Market (Deposit)"
echo "3. 掛買單 (Buy YES)"
echo "4. 查看 Market 狀態"
read -p "輸入選項 (1-4): " OPTION

case $OPTION in
    1)
        echo -e "${GREEN}查詢 USDC Coin...${NC}"
        echo "目標 Coin Type: 0x2::coin::Coin<${PACKAGE_ID}::usdc::USDC>"
        
        # 使用 sui client objects 抓取所有物件，並用 jq 過濾出 USDC
        # 格式: 0x2::coin::Coin<PACKAGE_ID::usdc::USDC>
        
        OBJECTS=$(sui client objects --json 2> /dev/null)
        
        # 檢查是否有結果，並以易讀格式顯示 ID 和餘額
        echo "$OBJECTS" | jq -r ".data[] | select(.type | contains(\"::usdc::USDC\")) | \"Object ID: \(.objectId) | Balance: \(.content.fields.balance)\""
        
        # 如果沒有找到，顯示提示
        COUNT=$(echo "$OBJECTS" | jq ".data[] | select(.type | contains(\"::usdc::USDC\"))" | wc -l)
        if [ "$COUNT" -eq "0" ]; then
            echo -e "${RED}❌ 找不到 USDC 物件。請確認您是否已鑄造 USDC，或 Package ID 是否正確。${NC}"
        fi
        ;;
    2)
        read -p "請輸入要存入的 USDC Coin Object ID: " COIN_ID
        read -p "請輸入金額: " AMOUNT
        
        echo -e "${GREEN}正在將 USDC 切分並存入...${NC}"
        # 這裡簡化：假設傳入的 Coin 金額剛好，或是合約會處理。
        # 在 CLI 中，如果 Coin 金額大於 deposit，通常需要先 split，或者合約支援 split。
        # 假設合約簽名是 deposit_usdc(market, coin, ctx)
        
        sui client call \
            --package $PACKAGE_ID \
            --module market \
            --function deposit_usdc \
            --args $MARKET_ID $COIN_ID \
            --gas-budget 50000000
        ;;
    3)
        # create_order(maker, maker_amount, taker_amount, maker_role, token_id, expiration, salt)
        # post_order(market, order, ctx)
        # 在 Move 中 create_order 只是返回 struct，無法直接由 CLI 調用並傳遞給 post_order (因為 struct 不能在 Tx 間傳遞)
        # 您的合約應該有一個 Entry function 封裝這兩個動作，例如 `place_order`。
        # 如果沒有，您需要在合約中新增一個 entry fun place_order(...) { let o = create_order(...); post_order(market, o); }
        
        echo "⚠️ 注意：需要合約中有 entry fun place_order"
        read -p "Maker Amount (USDC): " M_AMT
        read -p "Taker Amount (YES): " T_AMT
        
        # 假設有一個封裝好的 Entry Function
        sui client call \
            --package $PACKAGE_ID \
            --module market \
            --function place_order_entry \
            --args $MARKET_ID $M_AMT $T_AMT 0 1 0 12345 \
            --gas-budget 50000000
        ;;
    4)
        echo -e "${GREEN}查看 Market 物件內容...${NC}"
        sui client object $MARKET_ID
        ;;
    *)
        echo "無效選項"
        ;;
esac