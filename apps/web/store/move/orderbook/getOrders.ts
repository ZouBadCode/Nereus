import { Transaction } from "@mysten/sui/transactions";
import { SuiClient } from "@mysten/sui/client";
import { bcs } from "@mysten/sui/bcs";
import { market } from "../package";

// Define Order struct
const Order = bcs.struct('Order', {
    maker: bcs.Address,
    maker_amount: bcs.u64(),
    taker_amount: bcs.u64(),
    maker_role: bcs.u8(),
    token_id: bcs.u8(),
    expiration: bcs.u64(),
    salt: bcs.u64(),
});

export async function getBids(client: SuiClient, marketId: string, tokenId: number | null, cursor: Uint8Array | null, limit: number) {
    return fetchOrders(client, 'get_bids', marketId, tokenId, cursor, limit);
}

export async function getAsks(client: SuiClient, marketId: string, tokenId: number | null, cursor: Uint8Array | null, limit: number) {
    return fetchOrders(client, 'get_asks', marketId, tokenId, cursor, limit);
}

async function fetchOrders(client: SuiClient, funcName: string, marketId: string, tokenId: number | null, cursor: Uint8Array | null, limit: number) {
    const tx = new Transaction();
    
    // Prepare arguments
    // token_id: Option<u8>
    const tokenArg = tokenId !== null ? tx.pure.option('u8', tokenId) : tx.pure.option('u8', null);
    
    // cursor: Option<vector<u8>>
    const cursorArg = cursor ? tx.pure.option('vector<u8>', Array.from(cursor)) : tx.pure.option('vector<u8>', null);
    
    tx.moveCall({
        target: `${market}::${funcName}`,
        arguments: [
            tx.object(marketId),
            tokenArg,
            cursorArg,
            tx.pure.u64(limit)
        ]
    });

    const result = await client.devInspectTransactionBlock({
        transactionBlock: tx,
        sender: "0x0000000000000000000000000000000000000000000000000000000000000000", 
    });

    if (result.results && result.results.length > 0) {
        const firstResult = result.results[0];
        if (!firstResult || !firstResult.returnValues) return { orders: [], nextCursor: null };
        
        const returnValues = firstResult.returnValues;
        if (returnValues && returnValues.length === 2) {
            // First return value: vector<Order>
            const firstVal = returnValues[0];
            if (!firstVal) return { orders: [], nextCursor: null };
            const ordersBytes = Uint8Array.from(firstVal[0]);
            // Parse vector<Order>
            const orders = bcs.vector(Order).parse(ordersBytes);

            // Second return value: Option<vector<u8>>
            const secondVal = returnValues[1];
            if (!secondVal) return { orders: [], nextCursor: null };
            const cursorBytes = Uint8Array.from(secondVal[0]);
            // Parse Option<vector<u8>>
            const nextCursor = bcs.option(bcs.vector(bcs.u8())).parse(cursorBytes);

            return { orders, nextCursor };
        }
    }
    return { orders: [], nextCursor: null };
}
