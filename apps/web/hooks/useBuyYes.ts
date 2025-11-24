import { useCurrentAccount, useSignAndExecuteTransaction } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { storeStore, Market } from "../store/storeStore";
import { buyYesTx } from "../store/move/buy_yes";
import { useCallback } from "react";

export function useBuyYes() {
    const currentAccount = useCurrentAccount();
    const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction();
    const { fetchUser } = storeStore();

    const handleBuyYes = useCallback(async (market: Market, ticketAmount: bigint) => {
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

        if (!market.yesprice) {
            alert("Market price not available");
            return;
        }

        const tx = new Transaction();
        
        try {
            buyYesTx(
                tx,
                freshUser.USDC,
                market.address,
                ticketAmount, // USDC amount to spend
                market.yesprice, // Current price from market
                currentAccount.address
            );
            console.log("Constructed", tx);
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

    return { handleBuyYes };
}
