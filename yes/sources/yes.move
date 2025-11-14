module yes::yes;

use sui::coin::{Self, TreasuryCap, Coin};
use sui::url;

public struct YES has drop {}

fun init(witness: YES, ctx: &mut TxContext) {
    let (mut treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        9,
        b"YES",
        b"YES",
        b"Decentralized YES token",
        option::some(url::new_unsafe_from_bytes(b"https://www.google.com/url?sa=i&url=https%3A%2F%2Fwww.svgrepo.com%2Fsvg%2F327405%2Flogo-usd&psig=AOvVaw2A4ktX0YSLyC0Ntnfhe6Vh&ust=1761913741050000&source=images&cd=vfe&opi=89978449&ved=0CBUQjRxqFwoTCOC3osuPzJADFQAAAAAdAAAAABAE")),
        ctx
    );
    let treasury_cap_manager = TreasuryCapManager {
        id: object::new(ctx),
        treasury_cap: treasury_cap
    };
    transfer::public_freeze_object(coin_metadata);
    transfer::share_object(treasury_cap_manager);
}
