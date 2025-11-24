import { Transaction } from "@mysten/sui/transactions";
import {market, oracle} from "./package";
import { provideLPtx } from "./orderbook/addliquidity";

export function createMarketTx(
    tx: Transaction,
    objlist: any,
    topic: string,
    description: string,
    start_time: number,
    end_time: number
): Transaction {
    tx.moveCall({
        target: market+"::create_market",
        arguments: [
            objlist[0],
            tx.pure.string(topic),
            tx.pure.string(description),
            tx.pure.u64(start_time),
            tx.pure.u64(end_time)
        ]
    })
    tx.moveCall({
        target: "0x2::transfer::public_share_object",
        arguments: [
            objlist[0],
        ],
        typeArguments: [oracle+"::TruthOracleHolder"],
    })
    tx.moveCall({
        target: "0x2::transfer::public_share_object",
        arguments: [
            objlist[1],
        ],
        typeArguments: [oracle+"::OracleConfig"],
    })


    return tx;
}