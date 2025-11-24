import { market } from "../package";

// 不再負責 Merge，只負責執行 Move Call
export function provideLPtx(tx, fundingCoin: any, marketId: string, amount: bigint) {
    tx.moveCall({
        target: `${market}::mint_complete_set`,
        arguments: [
            tx.object(marketId),
            fundingCoin, // 直接使用傳入的 Coin Object
            tx.pure.u64(amount),
        ]
    });
    return tx;
}