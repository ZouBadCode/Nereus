import { Transaction } from "@mysten/sui/transactions";
import { market as PACKAGE_ID } from "./package";

const MODULE_NAME = "market";
const PRICE_SCALE = 1_000_000_000n;
const ASSET_NO = 0;
const SIDE_BUY = 0; 

function calculateShareAmount(usdcAmount: bigint, priceScaled: bigint): bigint {
    if (priceScaled <= 0n) throw new Error("Price must be greater than 0");
    return (usdcAmount * PRICE_SCALE) / priceScaled;
}

export function buyNoTx(
    tx: Transaction,
    usdcCoins: string[],
    marketId: string,
    usdcAmount: bigint,
    currentPrice: bigint, 
    userAddress: string,
    durationMs: number = 3600000
): Transaction {
    
    if (usdcCoins.length === 0) throw new Error("No USDC coins provided");

    // 1. Handle Coin
    const primaryCoin = tx.object(usdcCoins[0]);
    if (usdcCoins.length > 1) {
        tx.mergeCoins(primaryCoin, usdcCoins.slice(1).map(id => tx.object(id)));
    }
    const [depositCoin] = tx.splitCoins(primaryCoin, [tx.pure.u64(usdcAmount)]);

    // 2. Deposit USDC
    tx.moveCall({
        target: `${PACKAGE_ID}::deposit_usdc`,
        arguments: [tx.object(marketId), depositCoin]
    });

    // 3. Calculate Shares
    const takerShareAmount = calculateShareAmount(usdcAmount, currentPrice);
    if (takerShareAmount === 0n) throw new Error("Amount too small for current price");

    const expiration = BigInt(Date.now() + durationMs);
    const salt = BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));

    // 4. 建立並發布訂單 (Create & Post Order)
    tx.moveCall({
        target: `${PACKAGE_ID}::post_order`,
        arguments: [
            tx.object(marketId),
            tx.moveCall({
                target: `${PACKAGE_ID}::create_order`,
                arguments: [
                    tx.pure.address(userAddress),
                    tx.pure.u64(usdcAmount),
                    tx.pure.u64(takerShareAmount),
                    tx.pure.u8(SIDE_BUY),
                    tx.pure.u8(ASSET_NO),
                    tx.pure.u64(expiration),
                    tx.pure.u64(salt)
                ]
            })
        ]
    });

    return tx;
}
