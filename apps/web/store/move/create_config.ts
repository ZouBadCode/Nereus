
import { Transaction } from "@mysten/sui/transactions";
import { oracle } from "./package";


export function createMarketTx(
    tx: Transaction,
    code_hash: string,
    blobID: string
): any {
    // console.log(code_hash, blobID);
    // 1. 呼叫 create_config，取得 config 物件
    const [config] = tx.moveCall({
        target: oracle + "::create_config",
        arguments: [
            tx.pure.string(code_hash),
            tx.pure.string(blobID),
        ],
    });

    if (!config) {
        throw new Error("Config object from create_config moveCall is undefined.");
    }

    // 2. 呼叫 create_truth_oracle_holder，傳入 config
    const [holder]=tx.moveCall({
        target: oracle + "::create_truth_oracle_holder",
        arguments: [
            config,
        ],
    });

    return [holder,config];
}

