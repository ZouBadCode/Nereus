
import { Transaction } from "@mysten/sui/transactions";
import { market as PACKAGE_ID } from "./package";

const PRICE_SCALE = 1_000_000_000n; // 1.0 = 10^9
const ASSET_YES = 1;
const SIDE_BUY = 0; // 0 = Buy Role

// 計算預期獲得的 YES 份額： MakerAmount (USDC) / Price = Shares
function calculateShareAmount(usdcAmount: bigint, priceRaw: bigint): bigint {
    if (priceRaw <= 0n) throw new Error("Price must be greater than 0");
    // 公式: (USDC * SCALE) / Price
    return (usdcAmount * PRICE_SCALE) / priceRaw;
}

export function buyYesTx(
    tx: Transaction,
    usdcCoins: string[],      // 用戶擁有的 USDC Object IDs
    marketId: string,         // Market Object ID
    usdcAmount: bigint,       // 用戶想投入的 USDC 金額
    currentPrice: bigint,     // 當前 YES 價格 (基於 10^9)
    userAddress: string,      // 用戶地址
    durationMs: number = 3600000 // 預設訂單有效期 1 小時
): Transaction {
    
    if (!usdcCoins || usdcCoins.length === 0 || !usdcCoins[0]) throw new Error("No USDC coins provided");
    
    const primaryCoin = tx.object(usdcCoins[0]!);
    
    if (usdcCoins.length > 1) {
        tx.mergeCoins(primaryCoin, usdcCoins.slice(1).map(id => tx.object(id!)));
    }

    const [depositCoin] = tx.splitCoins(primaryCoin, [tx.pure.u64(usdcAmount)]);





    tx.moveCall({
        target: `${PACKAGE_ID}::deposit_usdc`,
        arguments: [
            tx.object(marketId),
            depositCoin
        ]
    });

    // --- 3. 計算 Taker Amount (Shares) ---
    const takerShareAmount = calculateShareAmount(usdcAmount, currentPrice);
    if (takerShareAmount === 0n) throw new Error("Amount too small for current price");

    const expiration = BigInt(Date.now() + durationMs);
    const salt = BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));

    // --- 4. 建立並發布訂單 (Create & Post Order) ---
    tx.moveCall({
        target: `${PACKAGE_ID}::post_order`,
        arguments: [
            tx.object(marketId),
            tx.moveCall({
                target: `${PACKAGE_ID}::create_order`,
                arguments: [
                    tx.pure.address(userAddress),  // maker
                    tx.pure.u64(usdcAmount),       // maker_amount (USDC)
                    tx.pure.u64(takerShareAmount), // taker_amount (Expected Shares)
                    tx.pure.u8(SIDE_BUY),          // maker_role (0 = BUY)
                    tx.pure.u8(ASSET_YES),         // token_id (1 = YES)
                    tx.pure.u64(expiration),       // expiration
                    tx.pure.u64(salt)              // salt
                ]
            })
        ]
    });

    return tx;
}