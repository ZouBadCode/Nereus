import { market } from "../package";
import { Transaction } from "@mysten/sui/transactions";

export function removeLiquidityTx(tx: Transaction, marketId: string, amount: bigint) {
    tx.moveCall({
        target: `${market}::merge_complete_set`,
        arguments: [
            tx.object(marketId),
            tx.pure.u64(amount),
        ]
    });
    return tx;
}
