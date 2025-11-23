#!/bin/bash

# 設定顏色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Sui Address Switcher ===${NC}"

# 1. 檢查是否安裝了 jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}警告: 未安裝 'jq'，腳本無法執行。${NC}"
    echo "請安裝: brew install jq (Mac) 或 sudo apt install jq (Linux)"
    exit 1
fi

# 2. 獲取並解析 JSON
# 使用 grep -v 過濾掉 warning 訊息，確保 JSON 格式乾淨
JSON_DATA=$(sui client addresses --json 2>/dev/null | grep -v "warning")

# === [關鍵修正] 解析邏輯 ===
# 您的 JSON 結構是: { "addresses": [ ["alias", "addr"], ... ] }
# 也就是說 addresses 裡面是陣列(Array)而非物件(Object)
# 下面的 jq 指令會自動判斷：如果是陣列就取 [0]/[1]，如果是物件就取 .alias/.address

# 讀取別名 (Alias) - 相容 Array [0] 和 Object .alias
ALIASES=($(echo "$JSON_DATA" | jq -r '.addresses[] | if type=="array" then .[0] else .alias end'))

# 讀取地址 (Address) - 相容 Array [1] 和 Object .address
ADDRESSES=($(echo "$JSON_DATA" | jq -r '.addresses[] | if type=="array" then .[1] else .address end'))

# 讀取當前活躍地址
ACTIVE_ADDR=$(echo "$JSON_DATA" | jq -r '.activeAddress // empty')

# 如果 JSON 裡沒包含 activeAddress，手動查詢一次
if [ -z "$ACTIVE_ADDR" ]; then
    ACTIVE_ADDR=$(sui client active-address 2>/dev/null)
fi

# 3. 顯示選單
count=${#ALIASES[@]}

if [ "$count" -eq 0 ]; then
    echo -e "${YELLOW}❌ 找不到任何地址，或解析失敗。${NC}"
    exit 1
fi

echo "--------------------------------------------------------"
printf "%-4s %-20s %-10s\n" "No." "Alias" "Address"
echo "--------------------------------------------------------"

for (( i=0; i<$count; i++ )); do
    ALIAS="${ALIASES[$i]}"
    ADDR="${ADDRESSES[$i]}"
    
    # 縮短顯示地址 (前6後4)
    SHORT_ADDR="${ADDR:0:6}...${ADDR: -4}"
    
    # 標記當前活躍地址
    if [[ "$ADDR" == "$ACTIVE_ADDR" ]]; then
        PREFIX="${GREEN}*${NC}"
        COLOR="${GREEN}"
    else
        PREFIX=" "
        COLOR="${NC}"
    fi

    printf "${PREFIX} %d) ${COLOR}%-20s %-10s${NC}\n" "$((i+1))" "$ALIAS" "$SHORT_ADDR"
done
echo "--------------------------------------------------------"

# 4. 讀取用戶輸入
read -p "請輸入要切換的編號 (1-$count): " CHOICE

# 驗證輸入是否為數字
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    echo "❌ 無效輸入"
    exit 1
fi

INDEX=$((CHOICE-1))

if [ "$INDEX" -ge 0 ] && [ "$INDEX" -lt "$count" ]; then
    TARGET_ALIAS="${ALIASES[$INDEX]}"
    TARGET_ADDR="${ADDRESSES[$INDEX]}"
    
    echo -e "正在切換到: ${CYAN}$TARGET_ALIAS${NC} ..."
    
    # 執行切換指令
    SWITCH_RES=$(sui client switch --address "$TARGET_ADDR" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ 切換成功！${NC}"
        echo "Active Address: $TARGET_ADDR"
    else
        echo -e "${YELLOW}⚠️  切換時發生警告或錯誤:${NC}"
        echo "$SWITCH_RES"
    fi
else
    echo "❌ 選項超出範圍"
fi