import { useCurrentAccount, useSignAndExecuteTransaction } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { storeStore, Market } from "../store/storeStore";
import { buyNoTx } from "../store/move/buy_no";
import { useCallback } from "react";

export function useBuyNo() {
    const currentAccount = useCurrentAccount();
    const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction();
    const { fetchUser } = storeStore();

    const handleBuyNo = useCallback(async (market: Market, ticketAmount: bigint) => {
        if (!currentAccount) {
            alert("Please connect your wallet first");
            return;
        }

        // Ensure we have the user's USDC coins
        // We check the current state from the store directly to avoid stale closures
        let freshUser = storeStore.getState().user;
        
        if (freshUser.USDC.length === 0) {
            await fetchUser(currentAccount.address);
            freshUser = storeStore.getState().user;
        }
        
        if (freshUser.USDC.length === 0) {
            alert("No USDC found in your wallet");
            return;
        }

        if (!market.noprice) {
            alert("Market price not available");
            return;
        }

        const tx = new Transaction();
        
        try {
            buyNoTx(
                tx,
                freshUser.USDC,
                market.address,
                ticketAmount, // USDC amount to spend
                market.noprice, // Current price from market
                currentAccount.address
            );

            signAndExecuteTransaction(
                {
                    transaction: tx,
                },
                {
                    onSuccess: (result) => {
                        console.log("Transaction successful", result);
                        alert("Purchase successful!");
                        storeStore.getState().queryMarkets();
                        storeStore.getState().fetchUser(currentAccount.address);
                    },
                    onError: (error) => {
                        console.error("Transaction failed", error);
                        alert("Transaction failed: " + error.message);
                    },
                }
            );
        } catch (e) {
            console.error("Error constructing transaction", e);
            alert("Error: " + (e instanceof Error ? e.message : String(e)));
        }

    }, [currentAccount, signAndExecuteTransaction, fetchUser]);

    return { handleBuyNo };
}
