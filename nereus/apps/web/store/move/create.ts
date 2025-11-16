import { Transaction } from "@mysten/sui/transactions";
import {market} from "./package";

export function createMarketTx(
    tx: Transaction,
    topic: string,
    description: string,
    start_time: number,
    end_time: number
): Transaction {
    tx.moveCall({
        target: market+"::create_market",
        arguments: [
            tx.pure.string(topic),
            tx.pure.string(description),
            tx.pure.u64(start_time),
            tx.pure.u64(end_time)
        ]
    })
    return tx;
}