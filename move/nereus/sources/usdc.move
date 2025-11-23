module nereus::usdc;

use sui::coin::{Self, TreasuryCap, Coin};
use sui::url;

public struct USDC has drop {}
public struct TreasuryCapManager has key {
    id: UID,
    treasury_cap: TreasuryCap<USDC>,
}

fun init(witness: USDC, ctx: &mut TxContext) {
    let (mut treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        9,
        b"USDC",
        b"USDC",
        b"Decentralized USD stablecoin backed by digital assets, crypto",
        option::some(
            url::new_unsafe_from_bytes(
                b"https://www.google.com/url?sa=i&url=https%3A%2F%2Fwww.svgrepo.com%2Fsvg%2F327405%2Flogo-usd&psig=AOvVaw2A4ktX0YSLyC0Ntnfhe6Vh&ust=1761913741050000&source=images&cd=vfe&opi=89978449&ved=0CBUQjRxqFwoTCOC3osuPzJADFQAAAAAdAAAAABAE",
            ),
        ),
        ctx,
    );
    let treasury_cap_manager = TreasuryCapManager {
        id: object::new(ctx),
        treasury_cap: treasury_cap,
    };
    transfer::public_freeze_object(coin_metadata);
    transfer::share_object(treasury_cap_manager);
}

// Need Constraints to ensure only one TreasuryCapManager per address
public(package) fun borrow_treasury_cap(
    treasury_cap_manager: &mut TreasuryCapManager,
): &mut TreasuryCap<USDC> {
    &mut treasury_cap_manager.treasury_cap
}

public(package) fun mint_usdc(
    treasury_cap: &mut TreasuryCap<USDC>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<USDC> {
    coin::mint<USDC>(treasury_cap, amount, ctx)
}

public fun faucet(treasury_cap_manager: &mut TreasuryCapManager, ctx: &mut TxContext) {
    let treasury_cap = borrow_treasury_cap(treasury_cap_manager);
    transfer::public_transfer(mint_usdc(treasury_cap, 1_000_000_000, ctx), ctx.sender());
}
