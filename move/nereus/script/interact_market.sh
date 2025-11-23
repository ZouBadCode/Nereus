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
        echo "目標 Coin Type: ${PACKAGE_ID}::usdc::USDC"
        
        # 1. 執行 balance 指令並儲存 JSON 結果
        BALANCE_RES=$(sui client balance --coin-type ${PACKAGE_ID}::usdc::USDC --json 2> /dev/null)
        
        # 2. 解析並顯示
        # 說明: '.. | objects?' 會遞迴搜尋所有層級
        # select(has("coinObjectId")) 會找出包含 coin ID 的物件
        PARSED_COINS=$(echo "$BALANCE_RES" | jq -r '.. | objects? | select(has("coinObjectId")) | "Object ID: \(.coinObjectId) | Balance: \(.balance)"')

        if [ -z "$PARSED_COINS" ]; then
            echo -e "${RED}❌ 找不到 USDC 物件。請確認您是否已鑄造 USDC，或 Package ID 是否正確。${NC}"
            # 用於除錯，如果失敗顯示原始 JSON
            # echo "Debug Raw JSON: $BALANCE_RES" 
        else
            echo "$PARSED_COINS"
        fi
        ;;
    2)
        read -p "請輸入來源 USDC Coin Object ID: " COIN_ID
        read -p "請輸入金額 (USDC, 留空或 0 則開啟選單): " INPUT_AMT

        # === 邏輯判斷：如果為空或為 0 ===
        if [ -z "$INPUT_AMT" ] || [ "$INPUT_AMT" == "0" ]; then
            echo "⚠️  未輸入金額，請選擇預設值："
            echo "1) 1 USDC"
            echo "2) 10 USDC"
            echo "3) 100 USDC"
            read -p "請選擇 (1-3): " AMT_CHOICE

            case $AMT_CHOICE in
                1) INPUT_AMT=1 ;;
                2) INPUT_AMT=10 ;;
                3) INPUT_AMT=100 ;;
                *) 
                    echo "無效選擇，預設使用 1 USDC"
                    INPUT_AMT=1 
                    ;;
            esac
        fi

        # === 轉換為 MIST (USDC 9 位小數) ===
        # 字串拼接 9 個 0 (假設輸入是整數)
        AMOUNT_MIST="${INPUT_AMT}000000000"
        
        echo -e "${GREEN}準備存入金額: ${INPUT_AMT} USDC ($AMOUNT_MIST MIST)...${NC}"

        # === 步驟 A: 切分 Coin (Split Coin) ===
        # 因為 deposit 會吃掉整顆 Coin，所以要先切出指定金額
        echo "正在切分 Coin..."
        
        SPLIT_RES=$(sui client split-coin \
            --coin-id $COIN_ID \
            --amounts $AMOUNT_MIST \
            --gas-budget 50000000 \
            --json 2> /dev/null)

        # 檢查切分是否成功
        if [[ $(echo "$SPLIT_RES" | jq -r '.effects.status.status') != "success" ]]; then
            echo -e "${RED}❌ 切分失敗！可能是餘額不足或 Coin ID 錯誤。${NC}"
            echo "$SPLIT_RES"
            exit 1
        fi

        # 抓取新產生的 Coin ID (Created Object)
        # 邏輯：尋找類型為 USDC 的 Created Object
        NEW_COIN_ID=$(echo "$SPLIT_RES" | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("::usdc::USDC"))) | .objectId' | head -n 1)

        if [ -z "$NEW_COIN_ID" ]; then
            echo -e "${RED}❌ 無法取得新 Coin ID${NC}"
            exit 1
        fi
        
        echo "✅ 切分成功，新 Coin ID: $NEW_COIN_ID"

        # === 步驟 B: 存入 Market (Deposit) ===
        echo -e "${GREEN}正在存入 Market...${NC}"
        
        sui client call \
            --package $PACKAGE_ID \
            --module market \
            --function deposit_usdc \
            --args $MARKET_ID $NEW_COIN_ID \
            --gas-budget 50000000 2> /dev/null
            
        echo "✅ 存款交易已送出！"
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