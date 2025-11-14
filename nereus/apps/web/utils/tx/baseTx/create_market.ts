import { Transaction } from "@mysten/sui/transactions";
import { package_addr } from "../package";

export const buyTicket = (topic, description, start_time, end_time) => {
    const tx = new Transaction();
    tx.moveCall({
        target: `${package_addr}::market::create_market`,
        arguments: [
            tx.pure.string(topic),
            tx.pure.string(description),
            tx.pure.u64(start_time),
            tx.pure.u64(end_time)
        ]
    });
    return tx;
};