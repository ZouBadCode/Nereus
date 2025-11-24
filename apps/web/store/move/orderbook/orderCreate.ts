
import { Transaction } from "@mysten/sui/transactions";
import { market as PACKAGE_ID } from "../package";

// New order creation: deposit USDC first, then post order
// 修改後的 orderCreateTx
export function orderCreateTx(
    tx: Transaction,
    user: string,
    marketId: string,
    usdcAmount: bigint,
    expectedShares: number,
    role: number,
    token: number,
    exp: number,
    salt: number,
    fundingCoin: any
): Transaction {
    // 只負責執行 Move Call
    tx.moveCall({
        target: `${PACKAGE_ID}::deposit_usdc`,
        arguments: [
            tx.object(marketId),
            fundingCoin,
        ]
    });
    // Post order
    tx.moveCall({
        target: `${PACKAGE_ID}::post_order`,
        arguments: [
            tx.object(marketId),
            tx.moveCall({
                target: `${PACKAGE_ID}::create_order`,
                arguments: [
                    tx.pure.address(user), // maker
                    tx.pure.u64(usdcAmount),  // maker_amount
                    tx.pure.u64(expectedShares), // taker_amount
                    tx.pure.u8(role),           // maker_role (0 = BUY)
                    tx.pure.u8(token),           // token_id (1 = YES)
                    tx.pure.u64(exp),  // expiration
                    tx.pure.u64(salt),        // salt
                ]
            })
        ],
    });
    return tx;
}