import { Transaction } from "@mysten/sui/transactions";
import {oracle} from "./package";

export function createMarketTx(
    tx: Transaction,
    code_hash: string,
    blobID: string
): Transaction {
    tx.moveCall({
        target: oracle+"::create_config",
        arguments: [
            tx.pure.string(code_hash),
            tx.object(blobID),
        ]
    })
    return tx;
}