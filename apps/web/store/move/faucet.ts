import { Transaction } from "@mysten/sui/transactions";
import { base, usdCap } from "../move/package";
export function NaYuTx(
    tx: Transaction,
): Transaction {
    tx.moveCall({
        target: base+ "::usdc::faucet",
        arguments: [tx.object(usdCap)],
    })  
    return tx;
}