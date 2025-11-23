// scripts/decode_order.js
const { bcs } = require('@mysten/bcs');

// --- 關鍵修正 ---
// 手動定義 Address 類型，避開 bcs.Address 可能 undefined 的問題
// Sui 地址是 32 bytes 的二進位數據
const Address = bcs.bytes(32).transform({
    input: (val) => val,
    output: (val) => '0x' + Buffer.from(val).toString('hex'),
});

// 定義 Move Struct
const Order = bcs.struct('Order', {
    maker: Address,          // 使用我們手動定義的 Address
    maker_amount: bcs.u64(),
    taker_amount: bcs.u64(),
    maker_role: bcs.u8(),
    token_id: bcs.u8(),
    expiration: bcs.u64(),
    salt: bcs.u64(),
});

// 讀取並驗證輸入
const args = process.argv.slice(2);
const inputString = args[0];

if (!inputString || inputString.trim() === '') {
    console.error("錯誤: 未提供有效的 Bytes 數據");
    process.exit(1);
}

try {
    // 清洗數據：確保輸入是純 JSON 陣列
    // 有時候 Shell 會傳入帶有空白的字串，這裡做個保險
    const cleanInput = inputString.trim();
    
    if (!cleanInput.startsWith('[') || !cleanInput.endsWith(']')) {
        throw new Error("輸入格式錯誤，期望 JSON 陣列 [...]");
    }

    const bytes = JSON.parse(cleanInput);
    const u8Array = new Uint8Array(bytes);

    // 解碼
    const orders = bcs.vector(Order).parse(u8Array);

    // 格式化輸出
    const formatted = orders.map(order => ({
        Maker: order.maker,
        Pay_USDC: (BigInt(order.maker_amount) / 1_000_000_000n).toString(),
        Get_Token: (BigInt(order.taker_amount) / 1_000_000_000n).toString(),
        Role: order.maker_role === 0 ? 'Buy' : 'Sell',
        Token: order.token_id === 1 ? 'YES' : 'NO'
    }));

    console.log(JSON.stringify(formatted, null, 2));

} catch (e) {
    console.error("解碼失敗:", e.message);
    // 除錯用：印出前 50 個字元看看收到了什麼
    console.error("收到數據開頭:", inputString.substring(0, 50));
}