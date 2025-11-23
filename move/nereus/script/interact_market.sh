#!/bin/bash

# 設定顏色
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ==========================================
# 1. 自動定位並切換到專案根目錄
# ==========================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" || exit

# 2. 讀取 .env
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo -e "${RED}❌ 找不到 .env 檔案，請先執行 deploy_testnet.sh${NC}"
    exit 1
fi

echo -e "${BLUE}=== Nereus Market 互動介面 ===${NC}"
echo "Package: $PACKAGE_ID"
echo "Market:  $MARKET_ID"

# ==========================================
# 選單
# ==========================================
echo "-------------------------------------"
echo "請選擇操作:"
echo "1. 查詢 USDC 餘額 (Balance)"
echo "2. 存入 USDC 到 Market (Deposit)"
echo "3. 掛買單 (Place Order - Buy YES)"
echo "4. 查看 Market 狀態"
echo "5. 查詢買賣單 (Bids YES / Asks NO)"
echo "-------------------------------------"
read -p "輸入選項 (1-5): " OPTION     

case $OPTION in
    1)
        echo -e "${GREEN}查詢 USDC Coin...${NC}"
        
        # 執行指令並清洗警告訊息
        BALANCE_RES=$(sui client balance --coin-type ${PACKAGE_ID}::usdc::USDC --json 2>&1 | grep -v "^\[warning\]")
        
        # 解析並顯示
        PARSED_COINS=$(echo "$BALANCE_RES" | jq -r '.. | objects? | select(has("coinObjectId")) | "Object ID: \(.coinObjectId) | Balance: \(.balance)"')

        if [ -z "$PARSED_COINS" ]; then
            echo -e "${RED}❌ 找不到 USDC 物件。${NC}"
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
                *) INPUT_AMT=1 ;;
            esac
        fi

        # === 轉換為 MIST (USDC 9 位小數) ===
        AMOUNT_MIST="${INPUT_AMT}000000000"
        echo -e "${GREEN}準備存入金額: ${INPUT_AMT} USDC ($AMOUNT_MIST MIST)...${NC}"

        # === 步驟 A: 切分 Coin (Split Coin) ===
        echo "正在切分 Coin..."
        
        SPLIT_RES=$(sui client split-coin \
            --coin-id $COIN_ID \
            --amounts $AMOUNT_MIST \
            --gas-budget 100000000 \
            --json 2>&1 | grep -v "^\[warning\]")

        # 檢查切分是否成功
        if [[ $(echo "$SPLIT_RES" | jq -r '.effects.status.status') != "success" ]]; then
            echo -e "${RED}❌ 切分失敗！請確認餘額是否足夠。${NC}"
            echo "$SPLIT_RES" | jq .effects.status
            exit 1
        fi

        # 抓取新產生的 Coin ID
        NEW_COIN_ID=$(echo "$SPLIT_RES" | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("::usdc::USDC"))) | .objectId' | head -n 1)

        if [ -z "$NEW_COIN_ID" ]; then
            echo -e "${RED}❌ 無法取得新 Coin ID${NC}"
            exit 1
        fi
        
        echo "✅ 切分成功，新 Coin ID: $NEW_COIN_ID"

        # === 步驟 B: 存入 Market (Deposit) ===
        echo -e "${GREEN}正在存入 Market...${NC}"
        
        DEPOSIT_RES=$(sui client call \
            --package $PACKAGE_ID \
            --module market \
            --function deposit_usdc \
            --args $MARKET_ID $NEW_COIN_ID \
            --gas-budget 100000000 \
            --json 2>&1 | grep -v "^\[warning\]")
        
        if [[ $(echo "$DEPOSIT_RES" | jq -r '.effects.status.status') == "success" ]]; then
            echo -e "${GREEN}✅ 存款成功！${NC}"
        else
            echo -e "${RED}❌ 存款失敗！${NC}"
            echo "$DEPOSIT_RES" | jq .effects.status
        fi
        ;;

    3)
        echo -e "${YELLOW}=== 掛單 (Buy YES) - PTB Mode ===${NC}"
        echo "使用 PTB 在單筆交易中執行: create_order -> post_order"
        
        # 1. 獲取當前使用者地址 (create_order 需要傳入 maker 地址)
        SENDER=$(sui client active-address)
        echo "Maker Address: $SENDER"

        read -p "您願意付出多少 USDC? (Maker Amount): " M_Input
        read -p "您想要獲得多少 YES? (Taker Amount): " T_Input
        
        # 轉換單位 (x 10^9)
        M_AMT="${M_Input}000000000"
        T_AMT="${T_Input}000000000"
        
        # 生成隨機 Salt
        SALT=$RANDOM
        
        echo "--------------------------------"
        echo "Maker (付出): $M_Input USDC"
        echo "Taker (獲得): $T_Input YES"
        echo "Salt: $SALT"
        echo "--------------------------------"
        
        echo -e "${YELLOW}正在發送 PTB 交易...${NC}"

        # ==================================================================
        # PTB 指令解釋：
        # 1. --move-call ...create_order : 執行創建訂單函數
        #    參數: @Maker @M_Amt @T_Amt Role(0=Buy) Token(1=YES) Exp(0) Salt
        # 2. --assign order_obj : 將上一步的結果(Order Struct)存入變數 order_obj
        # 3. --move-call ...post_order : 將訂單提交到市場
        #    參數: @MarketID order_obj
        # ==================================================================
        
        RAW_RES=$(sui client ptb \
            --move-call $PACKAGE_ID::market::create_order \
                @$SENDER \
                $M_AMT \
                $T_AMT \
                0u8 \
                1u8 \
                0u64 \
                ${SALT}u64 \
            --assign order_obj \
            --move-call $PACKAGE_ID::market::post_order \
                @$MARKET_ID \
                order_obj \
            --gas-budget 100000000 \
            --json 2>&1)

        # 清洗輸出
        CLEAN_RES=$(echo "$RAW_RES" | grep -v "^\[warning\]")
        STATUS=$(echo "$CLEAN_RES" | jq -r '.effects.status.status' 2>/dev/null)

        if [[ "$STATUS" == "success" ]]; then
            DIGEST=$(echo "$CLEAN_RES" | jq -r '.digest')
            echo -e "${GREEN}✅ PTB 掛單成功！${NC}"
            echo "交易 ID: $DIGEST"
        else
            echo -e "${RED}❌ PTB 掛單失敗！${NC}"
            echo "--------------------------------"
            echo "錯誤詳情:"
            # 嘗試解析錯誤，若失敗則印出全文
            PARSED_ERROR=$(echo "$CLEAN_RES" | jq -r '.effects.status // empty' 2>/dev/null)
            if [ -n "$PARSED_ERROR" ]; then
                echo "$PARSED_ERROR"
            else
                echo "$CLEAN_RES"
            fi
        fi
        ;;
    4)
        echo -e "${GREEN}讀取 Market 掛單狀態...${NC}"
        
        # 1. 抓取 Market 物件 (更強力的過濾，移除所有 [ 開頭的行)
        RAW_MARKET=$(sui client object $MARKET_ID --json --dry-run 2>&1 | grep -v "^\[")
        
        # 2. 使用遞迴搜尋直接找出 active_orders 的內容
        # 說明: .. 搜尋所有層級，找出 key 為 active_orders 的物件
        ACTIVE_ORDERS_DATA=$(echo "$RAW_MARKET" | jq -r '.. | .active_orders? | select(. != null)')
        
        # 3. 解析關鍵資訊
        # LinkedTable 的結構通常在 fields 裡面
        TABLE_ID=$(echo "$ACTIVE_ORDERS_DATA" | jq -r '.fields.id.id // empty')
        ORDER_SIZE=$(echo "$ACTIVE_ORDERS_DATA" | jq -r '.fields.size // "0"')
        
        echo "--------------------------------"
        if [ -z "$TABLE_ID" ]; then
            echo -e "${RED}無法讀取訂單 Table ID。可能原因：${NC}"
            echo "1. Market ID 錯誤 ($MARKET_ID)"
            echo "2. CLI 輸出格式改變"
            echo "原始資料片段: ${ACTIVE_ORDERS_DATA:0:100}..." 
        else
            echo -e "掛單總數 (Size): ${GREEN}$ORDER_SIZE${NC}"
            echo "訂單 Table ID : $TABLE_ID"
        fi
        echo "--------------------------------"

        # 4. 如果有 Table ID 且數量不為 0，才查詢詳細列表
        if [ -n "$TABLE_ID" ] && [ "$ORDER_SIZE" != "0" ] && [ "$ORDER_SIZE" != "null" ]; then
            echo -e "${YELLOW}正在查詢詳細訂單列表...${NC}"
            
            # 查詢 Dynamic Fields
            DF_RES=$(sui client dynamic-field $TABLE_ID --json 2>&1 | grep -v "^\[")
            
            # 檢查 DF_RES 是否為有效 JSON
            if [[ ${DF_RES:0:1} != "{" ]]; then
               echo -e "${RED}查詢失敗，回傳非 JSON 資料。${NC}"
            else
               echo "--- 訂單物件 ID 列表 ---"
               # 解析並顯示
               echo "$DF_RES" | jq -r '.data[]? | "Order Object ID: \(.objectId) | Name type: \(.name.type)"'
               
               echo -e "\n${BLUE}提示：要查看特定訂單內容，請複製 Object ID 使用 'sui client object <ID>' 查詢。${NC}"
            fi
        else
            echo "目前市場上沒有掛單，或無法讀取列表。"
        fi
        ;;

    5)
        echo -e "${GREEN}查詢 Order Book (Bids YES / Asks NO)...${NC}"
        
        # 1. 獲取 Market 的 active_orders Table ID
        RAW_MARKET=$(sui client object $MARKET_ID --json 2>&1 | grep -v "^\[")
        ACTIVE_ORDERS_DATA=$(echo "$RAW_MARKET" | jq -r '.. | .active_orders? | select(. != null)')
        TABLE_ID=$(echo "$ACTIVE_ORDERS_DATA" | jq -r '.fields.id.id // empty')
        
        if [ -z "$TABLE_ID" ]; then
            echo -e "${RED}無法讀取 active_orders Table ID。${NC}"
        else
            echo "Table ID: $TABLE_ID"
            echo -e "${YELLOW}正在讀取鏈上訂單資料...${NC}"
            
            # 2. 抓取 Table 中所有 Dynamic Field 的 ID
            DF_RES=$(sui client dynamic-field $TABLE_ID --json 2>&1 | grep -v "^\[")
            FIELD_IDS=$(echo "$DF_RES" | jq -r '.data[].objectId')
            
            # 初始化顯示字串
            STR_BIDS_YES=""
            STR_ASKS_NO=""
            COUNT_BIDS=0
            COUNT_ASKS=0

            # 3. 迴圈讀取每個訂單內容並分類
            for fid in $FIELD_IDS; do
                # 讀取 Field Object
                OBJ_DATA=$(sui client object $fid --json 2>&1 | grep -v "^\[")
                
                # 相容路徑
                ORDER_VAL=$(echo "$OBJ_DATA" | jq -r '(.data.content // .content).fields.value.fields.value.fields // empty')
                
                # 如果解析失敗(例如空值)，跳過
                if [ -z "$ORDER_VAL" ] || [ "$ORDER_VAL" == "null" ]; then
                    continue
                fi
                
                MAKER=$(echo "$ORDER_VAL" | jq -r '.maker')
                SIDE=$(echo "$ORDER_VAL" | jq -r '.maker_role')   # 0=Buy, 1=Sell
                TOKEN=$(echo "$ORDER_VAL" | jq -r '.token_id')    # 1=YES, 0=NO
                M_AMT=$(echo "$ORDER_VAL" | jq -r '.maker_amount')
                T_AMT=$(echo "$ORDER_VAL" | jq -r '.taker_amount')
                
                # === 數值顯示處理 (macOS Bash 3.2 相容寫法) ===
                
                # Maker Amount (USDC)
                M_Len=${#M_AMT}
                if [[ $M_Len -gt 9 ]]; then
                    # 計算截取長度 = 總長 - 9
                    Cut_Len=$((M_Len - 9))
                    M_Display="${M_AMT:0:$Cut_Len}"
                else
                    M_Display="$M_AMT (MIST)"
                fi

                # Taker Amount (YES/NO)
                T_Len=${#T_AMT}
                if [[ $T_Len -gt 9 ]]; then
                    Cut_Len=$((T_Len - 9))
                    T_Display="${T_AMT:0:$Cut_Len}"
                else
                    T_Display="$T_AMT (MIST)"
                fi

                # --- 邏輯判斷 ---
                
                # 1. Bids YES (買 YES): Side=0 (Buy) AND Token=1 (YES)
                if [[ "$SIDE" == "0" && "$TOKEN" == "1" ]]; then
                    STR_BIDS_YES="${STR_BIDS_YES}Maker: ${MAKER:0:6}... | Pay: ${M_Display} USDC -> Get: ${T_Display} YES\n"
                    COUNT_BIDS=$((COUNT_BIDS+1))
                
                # 2. Asks NO (賣 NO): Side=1 (Sell) AND Token=0 (NO)
                elif [[ "$SIDE" == "1" && "$TOKEN" == "0" ]]; then
                    STR_ASKS_NO="${STR_ASKS_NO}Maker: ${MAKER:0:6}... | Give: ${M_Display} NO -> Want: ${T_Display} USDC\n"
                    COUNT_ASKS=$((COUNT_ASKS+1))
                fi
            done
            
            # 4. 顯示結果
            echo "========================================"
            echo -e "${GREEN}Bids for YES (買入 YES)${NC}"
            echo "----------------------------------------"
            if [ "$COUNT_BIDS" -eq 0 ]; then
                echo "無"
            else
                echo -e "$STR_BIDS_YES"
            fi
            
            echo "========================================"
            echo -e "${RED}Asks for NO (賣出 NO)${NC}"
            echo "----------------------------------------"
            if [ "$COUNT_ASKS" -eq 0 ]; then
                echo "無"
            else
                echo -e "$STR_ASKS_NO"
            fi
            echo "========================================"
        fi
        ;;

    *)
        echo "無效選項"
        ;;
esac