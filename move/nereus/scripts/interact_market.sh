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
echo "6. 查詢 Market Vault 餘額 (My Position)"
echo "-------------------------------------"
read -p "輸入選項 (1-6): " OPTION     

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
        echo -e "${YELLOW}=== 掛單 (Place Order) - PTB Mode ===${NC}"
        echo "使用 PTB 在單筆交易中執行: create_order -> post_order"
        
        # 1. 獲取當前使用者地址
        SENDER=$(sui client active-address)
        echo "Maker Address: $SENDER"
        echo "--------------------------------"

        # === Step A: 選擇方向 (Side) ===
        echo "請選擇交易方向:"
        echo "1) Buy (買入 - 用 USDC 換 Token)"
        echo "2) Sell (賣出 - 用 Token 換 USDC)"
        read -p "選項 (預設 1): " SIDE_OPT
        
        if [ "$SIDE_OPT" == "2" ]; then
            SIDE_VAL=1
            SIDE_STR="Sell"
            MAKER_CURRENCY="Token (YES/NO)"
            TAKER_CURRENCY="USDC"
        else
            SIDE_VAL=0
            SIDE_STR="Buy"
            MAKER_CURRENCY="USDC"
            TAKER_CURRENCY="Token (YES/NO)"
        fi

        # === Step B: 選擇標的 (Asset) ===
        echo "--------------------------------"
        echo "請選擇標的物:"
        echo "1) YES"
        echo "2) NO"
        read -p "選項 (預設 1): " TOKEN_OPT

        if [ "$TOKEN_OPT" == "2" ]; then
            TOKEN_VAL=0
            TOKEN_STR="NO"
        else
            TOKEN_VAL=1
            TOKEN_STR="YES"
        fi

        # 更新顯示幣種名稱
        if [ "$MAKER_CURRENCY" != "USDC" ]; then MAKER_CURRENCY=$TOKEN_STR; fi
        if [ "$TAKER_CURRENCY" != "USDC" ]; then TAKER_CURRENCY=$TOKEN_STR; fi

        echo "--------------------------------"
        echo -e "即將建立訂單: ${GREEN}${SIDE_STR} ${TOKEN_STR}${NC}"
        echo "--------------------------------"

        # === Step C: 輸入金額 ===
        read -p "Maker Amount (您願意付出 $MAKER_CURRENCY 的數量): " M_Input
        read -p "Taker Amount (您想要獲得 $TAKER_CURRENCY 的數量): " T_Input
        
        # 檢查輸入
        if [ -z "$M_Input" ] || [ -z "$T_Input" ]; then
            echo -e "${RED}❌ 金額不能為空${NC}"
            exit 1
        fi

        # 轉換單位 (x 10^9)
        M_AMT="${M_Input}000000000"
        T_AMT="${T_Input}000000000"
        
        # 生成隨機 Salt
        SALT=$RANDOM
        
        echo "--------------------------------"
        echo "Maker Info:"
        echo "  Action : $SIDE_STR $TOKEN_STR"
        echo "  Pay    : $M_Input $MAKER_CURRENCY"
        echo "  Get    : $T_Input $TAKER_CURRENCY"
        echo "  Salt   : $SALT"
        echo "--------------------------------"
        
        echo -e "${YELLOW}正在發送 PTB 交易...${NC}"

        # ==================================================================
        # PTB 指令鏈:
        # create_order(maker, m_amt, t_amt, role, token, exp, salt)
        # role:  使用變數 $SIDE_VAL (0 or 1)
        # token: 使用變數 $TOKEN_VAL (1 or 0)
        # ==================================================================
        
        PTB_RES=$(sui client ptb \
            --move-call $PACKAGE_ID::market::create_order \
                @$SENDER \
                ${M_AMT}u64 \
                ${T_AMT}u64 \
                ${SIDE_VAL}u8 \
                ${TOKEN_VAL}u8 \
                0u64 \
                ${SALT}u64 \
            --assign order_obj \
            --move-call $PACKAGE_ID::market::post_order \
                @$MARKET_ID \
                order_obj \
                @0x6 \
            --gas-budget 100000000 \
            --json 2>&1)

        # 清洗並檢查 (過濾 warning 避免 jq 解析錯誤)
        CLEAN_RES=$(echo "$PTB_RES" | grep -v "^\[warning\]")
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
        echo -e "${GREEN}查詢 Order Book (Direct Scan - Full View)...${NC}"
        
        clean_output() {
            sed 's/\x1b\[[0-9;]*m//g' | grep -v "warning" | grep -v "Client/Server"
        }

        RAW_MARKET=$(sui client object $MARKET_ID --json 2>&1 | clean_output)
        ACTIVE_ORDERS_DATA=$(echo "$RAW_MARKET" | jq -r '.. | .active_orders? | select(. != null)')
        TABLE_ID=$(echo "$ACTIVE_ORDERS_DATA" | jq -r '.fields.id.id // empty')
        
        if [ -z "$TABLE_ID" ]; then
            echo -e "${RED}❌ 無法讀取 Table ID。${NC}"
        else
            echo "Table ID: $TABLE_ID"
            DF_RES=$(sui client dynamic-field $TABLE_ID --json 2>&1 | clean_output)
            DF_COUNT=$(echo "$DF_RES" | jq -r '.data | length' 2>/dev/null)
            
            if [ -z "$DF_COUNT" ] || [ "$DF_COUNT" == "0" ]; then
                echo -e "${YELLOW}目前市場上沒有掛單。${NC}"
            else
                echo -e "${YELLOW}找到 $DF_COUNT 筆訂單，正在解析內容...${NC}"
                
                FIELD_IDS=$(echo "$DF_RES" | jq -r '.data[].objectId')
                
                # 初始化 4 個方向的字串與計數
                STR_BIDS_YES=""
                STR_ASKS_NO=""
                STR_BIDS_NO=""
                STR_ASKS_YES=""
                
                COUNT_BIDS_YES=0
                COUNT_ASKS_NO=0
                COUNT_BIDS_NO=0
                COUNT_ASKS_YES=0

                for fid in $FIELD_IDS; do
                    OBJ_DATA=$(sui client object $fid --json 2>&1 | clean_output)
                    ORDER_VAL=$(echo "$OBJ_DATA" | jq -r '.. | .value? | .fields? | .value? | .fields? | select(.maker != null)')
                    
                    if [ -z "$ORDER_VAL" ]; then continue; fi
                    
                    MAKER=$(echo "$ORDER_VAL" | jq -r '.maker')
                    SIDE=$(echo "$ORDER_VAL" | jq -r '.maker_role')   # 0=Buy, 1=Sell
                    TOKEN=$(echo "$ORDER_VAL" | jq -r '.token_id')    # 1=YES, 0=NO
                    M_AMT=$(echo "$ORDER_VAL" | jq -r '.maker_amount')
                    T_AMT=$(echo "$ORDER_VAL" | jq -r '.taker_amount')
                    
                    # 數值顯示處理
                    M_Len=${#M_AMT}
                    if [[ $M_Len -gt 9 ]]; then M_Show="${M_AMT:0:$((M_Len-9))}"; else M_Show="0.${M_AMT}"; fi
                    
                    T_Len=${#T_AMT}
                    if [[ $T_Len -gt 9 ]]; then T_Show="${T_AMT:0:$((T_Len-9))}"; else T_Show="0.${T_AMT}"; fi

                    LINE="Maker: ${MAKER:0:6}... | Pay: ${M_Show} USDC -> Get: ${T_Show}"

                    # === 分類邏輯 (4 Directions) ===
                    
                    # 1. Buy YES (Side=0, Token=1)
                    if [[ "$SIDE" == "0" && "$TOKEN" == "1" ]]; then
                        STR_BIDS_YES="${STR_BIDS_YES}${LINE} YES\n"
                        COUNT_BIDS_YES=$((COUNT_BIDS_YES+1))
                    
                    # 2. Buy NO (Side=0, Token=0) -> 這就是消失的那張！
                    elif [[ "$SIDE" == "0" && "$TOKEN" == "0" ]]; then
                        STR_BIDS_NO="${STR_BIDS_NO}${LINE} NO\n"
                        COUNT_BIDS_NO=$((COUNT_BIDS_NO+1))

                    # 3. Sell NO (Side=1, Token=0)
                    elif [[ "$SIDE" == "1" && "$TOKEN" == "0" ]]; then
                        STR_ASKS_NO="${STR_ASKS_NO}${LINE} USDC (Sell NO)\n"
                        COUNT_ASKS_NO=$((COUNT_ASKS_NO+1))

                    # 4. Sell YES (Side=1, Token=1)
                    elif [[ "$SIDE" == "1" && "$TOKEN" == "1" ]]; then
                        STR_ASKS_YES="${STR_ASKS_YES}${LINE} USDC (Sell YES)\n"
                        COUNT_ASKS_YES=$((COUNT_ASKS_YES+1))
                    fi
                done
                
                # === 顯示結果 ===
                echo "========================================"
                echo -e "${GREEN}Bids for YES (做多: 買入 YES)${NC}"
                echo "----------------------------------------"
                [ "$COUNT_BIDS_YES" -eq 0 ] && echo "無" || echo -e "$STR_BIDS_YES"
                
                echo "========================================"
                echo -e "${BLUE}Bids for NO  (做空: 買入 NO)${NC}"
                echo "----------------------------------------"
                [ "$COUNT_BIDS_NO" -eq 0 ] && echo "無" || echo -e "$STR_BIDS_NO"

                echo "========================================"
                echo -e "${RED}Asks for NO  (平倉/做多: 賣出 NO)${NC}"
                echo "----------------------------------------"
                [ "$COUNT_ASKS_NO" -eq 0 ] && echo "無" || echo -e "$STR_ASKS_NO"

                echo "========================================"
                echo -e "${YELLOW}Asks for YES (平倉/做空: 賣出 YES)${NC}"
                echo "----------------------------------------"
                [ "$COUNT_ASKS_YES" -eq 0 ] && echo "無" || echo -e "$STR_ASKS_YES"
                echo "========================================"
            fi
        fi
        ;;


    5)
        echo -e "${GREEN}查詢 Order Book (Pure PTB - New BCS)...${NC}"
        
        # 確保使用最新版 BCS
        # npm install @mysten/bcs@latest

        # 定義清洗函數
        clean_output() {
            sed 's/\x1b\[[0-9;]*m//g' | grep -v "warning" | grep -v "Client/Server"
        }

        # 定義查詢函數
        query_ptb_stdlib() {
            local FUNC=$1
            local TOKEN=$2
            local LABEL=$3
            
            echo "--------------------------------------------------"
            echo -e "正在查詢: $LABEL"
            
            RAW_OUT=$(sui client ptb \
                --move-call "0x1::option::some<u8>" ${TOKEN}u8 \
                --assign token_opt \
                --move-call "0x1::option::none<vector<u8>>" \
                --assign cursor_opt \
                --move-call "$PACKAGE_ID::market::$FUNC" @$MARKET_ID token_opt cursor_opt 100u64 \
                --dev-inspect \
                2>&1 | clean_output)

            if echo "$RAW_OUT" | grep -q "Status: Success"; then
                # 1. 抓取所有 Bytes 行
                BYTES_LINES=$(echo "$RAW_OUT" | grep "Bytes:")
                
                # 2. 找出最長的那一行 (真實數據)
                DATA_LINE=$(echo "$BYTES_LINES" | awk 'length($0) > 50')
                
                if [ -n "$DATA_LINE" ]; then
                    echo -e "${GREEN}結果: 有訂單！正在解碼...${NC}"
                    
                    # 3. 關鍵修正：提取純 JSON 陣列 string
                    # 使用 sed 將 "    Bytes: " 替換為空字串
                    CLEAN_BYTES=$(echo "$DATA_LINE" | sed 's/.*Bytes: //')
                    
                    # 4. 呼叫 Node.js 進行解碼
                    # 確保路徑正確指向 scripts/decode_order.js
                    node scripts/decode_order.js "$CLEAN_BYTES"
                else
                    echo -e "${YELLOW}結果: 無訂單 (Empty)${NC}"
                fi
            else
                echo -e "${RED}❌ PTB 執行失敗${NC}"
                echo "$RAW_OUT" | head -n 20
            fi
        }

        # ==========================================
        # 執行 4 個方向的掃描
        # ==========================================

        # 1. 買 YES (做多)
        query_ptb_stdlib "get_bids" "1" "Bids for YES (買入 YES - 做多)"

        # 2. 賣 YES (平倉/做空)
        query_ptb_stdlib "get_asks" "1" "Asks for YES (賣出 YES)"

        # 3. 買 NO (做空)
        query_ptb_stdlib "get_bids" "0" "Bids for NO  (買入 NO  - 做空)"

        # 4. 賣 NO (平倉/做多)
        query_ptb_stdlib "get_asks" "0" "Asks for NO  (賣出 NO )"
        
        echo "--------------------------------------------------"
        ;;

    6)
        echo -e "${GREEN}查詢 Market Vault 內部餘額 (Internal Balance)...${NC}"
        
        SENDER=$(sui client active-address)
        echo "User: $SENDER"
        echo -e "${YELLOW}正在讀取合約狀態 (Dev Inspect)...${NC}"
        
        # 1. 執行 PTB (注意: 恢復使用 @$SENDER)
        # 我們同時保留 stdout 和 stderr，以便後續分析
        RAW_OUTPUT=$(sui client ptb \
            --move-call $PACKAGE_ID::market::get_all_balances @$MARKET_ID @$SENDER \
            --dev-inspect \
            --json 2>&1)
            
        # 2. 定義一個 Node.js 輔助函數來解析 Little Endian Bytes
        # 這是最穩定的方法，因為 CLI 輸出的 "Bytes: [...]" 格式通常不會變
        parse_bytes_with_node() {
            local bytes_str="$1"
            node -e "
                try {
                    const arr = $bytes_str;
                    const buf = Buffer.from(arr);
                    // 讀取 64-bit Little Endian Unsigned Integer
                    const val = buf.readBigUInt64LE(0);
                    // 轉成人類可讀格式 (除以 10^9)
                    const human = Number(val) / 1000000000;
                    console.log(human.toFixed(2));
                } catch (e) {
                    console.log('0');
                }
            "
        }

        # 3. 嘗試提取 Bytes 資料
        # 輸出格式通常包含多行 "Bytes: [x, x, x...]"
        # 我們將它們存入陣列
        
        # 使用 grep 提取所有 Bytes 行
        BYTES_LINES=$(echo "$RAW_OUTPUT" | grep "Bytes: \[")
        
        # 檢查是否找到數據
        if [ -z "$BYTES_LINES" ]; then
            echo -e "${RED}❌ 查詢失敗！無法找到回傳數據。${NC}"
            echo "原始輸出片段:"
            echo "$RAW_OUTPUT" | head -n 20
        else
            # 將 grep 結果轉為陣列 (以換行符分隔)
            IFS=$'\n' read -rd '' -a LINES_ARY <<< "$BYTES_LINES"
            
            # 根據 Move 函數回傳順序: (YES, NO, USDC)
            # 通常順序是固定的
            LINE_YES="${LINES_ARY[0]}"
            LINE_NO="${LINES_ARY[1]}"
            LINE_USDC="${LINES_ARY[2]}"
            
            # 清洗字串，只保留 [ ... ] 部分
            # 例如 "   Bytes: [0, 0...]" -> "[0, 0...]"
            JSON_YES=$(echo "$LINE_YES" | sed 's/.*Bytes: //')
            JSON_NO=$(echo "$LINE_NO" | sed 's/.*Bytes: //')
            JSON_USDC=$(echo "$LINE_USDC" | sed 's/.*Bytes: //')
            
            # 呼叫 Node 解析
            VAL_YES=$(parse_bytes_with_node "$JSON_YES")
            VAL_NO=$(parse_bytes_with_node "$JSON_NO")
            VAL_USDC=$(parse_bytes_with_node "$JSON_USDC")

            echo "----------------------------------------"
            echo -e "Market Vault 存款 (Internal):"
            echo "----------------------------------------"
            echo -e "🟢 YES  Token : $VAL_YES"
            echo -e "🔴 NO   Token : $VAL_NO"
            echo -e "💰 USDC Coin  : $VAL_USDC"
            echo "----------------------------------------"
        fi
        ;;
        
    *)
        echo "無效選項"
        ;;
esac