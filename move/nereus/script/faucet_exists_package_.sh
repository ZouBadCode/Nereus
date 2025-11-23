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
# 4. 處理 USDC (模擬) - 使用 PTB 批量領水並合併
# ==========================================
if [ -z "$USDC_TREASURY_ID" ]; then
    echo "⚠️ 未檢測到 USDC_TREASURY_ID (或 Manager ID)，跳過鑄造。"
else
    echo "Manager/Treasury ID: $USDC_TREASURY_ID"
    
    # === 修改：詢問要領取幾次 ===
    read -p "請問要執行幾次 Faucet? (預設 1 次, 輸入 0 跳過): " INPUT_TIMES

    # 設定預設值邏輯
    if [ -z "$INPUT_TIMES" ]; then
        MINT_TIMES=1
    else
        MINT_TIMES=$INPUT_TIMES
    fi

    # 如果輸入 0 或負數則跳過
    if [ "$MINT_TIMES" -le 0 ]; then
        echo "已跳過 Faucet 動作。"
    else
        echo -e "${GREEN}準備執行 PTB 批量領水 (共 $MINT_TIMES 次)...${NC}"

        # 1. 建構 PTB 指令字串
        # 我們動態產生多個 --move-call 參數
        PTB_ARGS=""
        for ((i=1; i<=MINT_TIMES; i++)); do
            # 假設 faucet 函數簽名是 faucet(ctx, manager)
            # 參數前面加 @ 代表是 Object ID
            PTB_ARGS="$PTB_ARGS --move-call $PACKAGE_ID::usdc::faucet @$USDC_TREASURY_ID"
        done

        # 2. 執行 PTB 交易
        PTB_RES=$(sui client ptb $PTB_ARGS --gas-budget $GAS_BUDGET --json 2> /dev/null)

        if [[ $(echo "$PTB_RES" | jq -r '.effects.status.status') == "success" ]]; then
            DIGEST=$(echo "$PTB_RES" | jq -r '.digest')
            echo -e "${GREEN}✅ 批量領水成功！${NC} (交易 ID: $DIGEST)"
        else
            echo -e "${RED}❌ PTB 領水失敗！${NC}"
            echo "$PTB_RES"
            # 領水失敗不強制 exit，讓腳本繼續跑完後續流程
        fi

        # ==========================================
        # 5. 自動合併 Coin (Merge Coins)
        # ==========================================
        # 只有當執行次數 > 1 才需要檢查合併
        if [ "$MINT_TIMES" -gt 1 ]; then
            echo -e "${BLUE}等待鏈上狀態更新 (3秒)...${NC}"
            sleep 3 # 稍微等待，確保 indexer 抓得到新 Coin

            echo -e "${BLUE}正在檢查並合併 USDC Coins...${NC}"

            # 1. 抓取所有 USDC 的 Object ID
            # 使用 sui client coins (比 balance 好解析)
            COINS_JSON=$(sui client coins --coin-type $PACKAGE_ID::usdc::USDC --json 2> /dev/null)
            
            # 提取所有 ID 到陣列
            COIN_IDS=($(echo "$COINS_JSON" | jq -r '.data[].coinObjectId'))
            COIN_COUNT=${#COIN_IDS[@]}

            echo "目前持有 $COIN_COUNT 顆 USDC Coin 物件。"

            if [ "$COIN_COUNT" -gt 1 ]; then
                # 第一顆當作主 Coin (Primary)
                PRIMARY_COIN=${COIN_IDS[0]}
                
                # 剩下的當作要被合併的 Coin (Source)
                # 陣列切片：從 index 1 開始到最後
                SOURCE_COINS=${COIN_IDS[@]:1}
                
                echo "主 Coin: $PRIMARY_COIN"
                echo -e "${GREEN}正在將其餘 $(($COIN_COUNT - 1)) 顆 Coin 合併...${NC}"

                MERGE_RES=$(sui client merge-coin \
                    --primary-coin $PRIMARY_COIN \
                    --coin-to-merge $SOURCE_COINS \
                    --gas-budget $GAS_BUDGET \
                    --json 2> /dev/null)

                if [[ $(echo "$MERGE_RES" | jq -r '.effects.status.status') == "success" ]]; then
                     echo -e "${GREEN}✅ 合併完成！${NC} 所有資金已集中到 $PRIMARY_COIN"
                else
                     echo -e "${RED}❌ 合併失敗！${NC}"
                     # 顯示部分錯誤訊息
                     echo "$MERGE_RES" | jq -r '.effects.status.error // "Unknown Error"'
                fi
            else
                echo "Coin 數量無需合併。"
            fi
        fi
    fi
fi